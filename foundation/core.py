"""Foundation TCB: register / publish / resolve / query (spec FR-002..007, Flow).

All publish-path checks evaluate the current authoritative home head (never a
derived cache, D-006); idempotency-first precedes the CAS write-guard (D-005);
Home CAS is on expected_home_revision (D-004). Resolve returns digest-verified
bytes only; query/change-fact return edge/status facts only (C4).
"""

import json
import re
import subprocess

from foundation import errors, gitobj, graph, home, schema

ENVELOPE_PREFIX = "envelope-"
REGISTRY_PREFIX = "registry-"
_REPO_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def _parse(state, prefix):
    """Yield (name, parsed_object, raw_bytes) for entries under `prefix`.

    A corrupt/tampered entry (undecodable bytes, non-JSON, or not a JSON object) is a
    corrupt *authoritative home*, not caller input: fail closed with HOME_ERROR (ERR-005),
    never an untyped exception at the TCB boundary. The per-kind validators below enforce
    exact closed shape + types + filename<->content binding + canonical bytes, so unknown
    fields / wrong types / impersonating filenames / non-canonical tampering all fail
    closed too (the entry-level analogue of read_head's ref validation).
    """
    out = []
    for name, data in state.items():
        if not name.startswith(prefix):
            continue
        try:
            obj = json.loads(data.decode())
        except (UnicodeDecodeError, ValueError, RecursionError, MemoryError) as exc:
            # RecursionError (deeply-nested JSON) is a RuntimeError, not a ValueError — it
            # must not escape untyped at the TCB boundary / crash the CLI.
            raise errors.FoundationError(errors.HOME_ERROR, f"corrupt home entry {name!r}: {type(exc).__name__}")
        if not isinstance(obj, dict):
            raise errors.FoundationError(errors.HOME_ERROR, f"corrupt home entry {name!r}: not a JSON object")
        out.append((name, obj, data))
    return out


def _home_state_guard(parse_fn):
    """Wrap a home-state parser so ANY corruption-induced failure over UNTRUSTED stored
    state becomes a typed HOME_ERROR (ERR-005). This is "Legal Home (V1)" condition 5
    (spec): the boundary validates the home against the closed legal-state definition, and
    ANY exception raised while doing so means the state is not a valid V1 home -> fail
    closed. We catch `Exception` (not an enumerated tuple) DELIBERATELY: enumerating types
    is what made this class regress five times (UnicodeDecodeError -> RecursionError ->
    unhashable-kind TypeError -> surrogate UnicodeEncodeError -> ...). A broad catch over
    a pure validator of attacker-controlled bytes is the correct fail-closed posture --
    even a validator bug then reports "corrupt home" rather than escaping untyped at the
    TCB. Both _registry and _published share this one guard, so a sibling cannot regress by
    leaving a new exception type uncaught. A corrupt home is never the caller's fault, so an
    inner SCHEMA_ERROR is remapped to HOME_ERROR too. (BaseException -- KeyboardInterrupt,
    SystemExit -- is intentionally NOT caught.)
    """
    def guarded(state):
        try:
            return parse_fn(state)
        except errors.FoundationError as exc:
            if exc.code == errors.HOME_ERROR:
                raise
            raise errors.FoundationError(errors.HOME_ERROR, f"corrupt home state: {exc.detail}")
        except Exception as exc:
            raise errors.FoundationError(errors.HOME_ERROR, f"corrupt home state: {type(exc).__name__}")
    return guarded


@_home_state_guard
def _registry(state):
    reg, locators = {}, set()
    for name, entry, data in _parse(state, REGISTRY_PREFIX):
        repo_id = entry.get("repo_id")
        if (
            set(entry) != {"repo_id", "locator", "kind"}
            or not isinstance(repo_id, str)
            or not isinstance(entry.get("locator"), str)
            or entry.get("kind") != "registry"
            or not _REPO_ID_RE.fullmatch(repo_id)
            or entry["locator"] == ""
            or name != f"{REGISTRY_PREFIX}{repo_id}.json"           # filename must bind to content repo_id
            or data != schema.canonical_json(entry).encode()       # exact canonical bytes
        ):
            raise errors.FoundationError(errors.HOME_ERROR, f"corrupt registry entry {name!r}")
        if repo_id in reg or entry["locator"] in locators:         # identity + locator uniqueness
            raise errors.FoundationError(errors.HOME_ERROR, "corrupt registry: duplicate repo_id or locator")
        reg[repo_id] = entry["locator"]
        locators.add(entry["locator"])
    return reg


@_home_state_guard
def _published(state):
    envs, seen_refs, identities = [], set(), set()
    for name, env, data in _parse(state, ENVELOPE_PREFIX):
        if set(env) != {"collection_identity", "artifact_ref", "relations"}:   # exact closed shape (reject unknown fields)
            raise errors.FoundationError(errors.HOME_ERROR, f"corrupt envelope entry {name!r}: shape")
        try:
            canonical = schema.publication_envelope(env["collection_identity"], env["artifact_ref"], env["relations"])
            recomputed = schema.envelope_digest(env["collection_identity"], env["artifact_ref"], env["relations"])
        except errors.FoundationError as exc:
            raise errors.FoundationError(errors.HOME_ERROR, f"corrupt envelope entry {name!r}: {exc.detail}")
        except (ValueError, TypeError, KeyError, RecursionError, MemoryError) as exc:
            # Any non-FoundationError from recomputing UNTRUSTED stored state is a corrupt
            # home, not caller input -> HOME_ERROR. Durable: this class has repeatedly
            # regressed via a new exception type slipping past a too-narrow catch.
            raise errors.FoundationError(errors.HOME_ERROR, f"corrupt envelope entry {name!r}: {type(exc).__name__}")
        # exact canonical bytes + filename<->digest binding: catches unknown-field, reorder,
        # whitespace, and any tamper as HOME_ERROR (not a caller-blamed SCHEMA_ERROR).
        if data != schema.canonical_json(canonical).encode() or name != f"{ENVELOPE_PREFIX}{recomputed}.json":
            raise errors.FoundationError(errors.HOME_ERROR, f"corrupt envelope entry {name!r}: non-canonical or digest mismatch")
        ref_key = schema.canonical_json(canonical["artifact_ref"])
        if ref_key in seen_refs:                    # one envelope per Ref (read-time PUBLICATION_CONFLICT invariant)
            raise errors.FoundationError(errors.HOME_ERROR, "corrupt home: multiple envelopes for one artifact_ref")
        seen_refs.add(ref_key)
        identities.add(canonical["collection_identity"])
        envs.append(canonical)
    if len(identities) > 1:                         # one home <-> one collection (CH-5; no mixed/foreign identity)
        raise errors.FoundationError(errors.HOME_ERROR, "corrupt home: mixed collection_identity (split-brain)")
    return envs


def _receipt(envelope, digest):
    # No home commit OID embedded (avoids self-reference); revision is paired separately.
    return {
        "envelope_digest": digest,
        "artifact_ref": envelope["artifact_ref"],
        "relations": envelope["relations"],
        "kind": "publish",
    }


def _validate_publish_authority(git_dir, state, envelope):
    """Validate a candidate/replay against the current authoritative Home state."""
    ref, rels = envelope["artifact_ref"], envelope["relations"]
    published = _published(state)
    registry = _registry(state)

    if ref["repo_id"] not in registry:
        raise errors.FoundationError(errors.SCHEMA_ERROR, f"repo unregistered: {ref['repo_id']}")

    published_keys = {schema.canonical_json(env["artifact_ref"]) for env in published}
    for rel in rels:
        if schema.canonical_json(rel["object"]) not in published_keys:
            raise errors.FoundationError(errors.SCHEMA_ERROR, "relation object is not published")

    graph.check_supersedes_kinds(ref, rels)
    graph.check_acyclic(published if envelope in published else published + [envelope])
    gitobj.resolve_verified(
        registry[ref["repo_id"]],
        ref["commit_oid"],
        ref["path"],
        ref["digest"],
    )


def _introducing_revision(git_dir, head, entry_name):
    proc = subprocess.run(
        ["git", "--git-dir", git_dir, "log", "--diff-filter=A", "--format=%H", head, "--", entry_name],
        capture_output=True,
        text=True,
    )
    lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
    return lines[-1] if lines else head


def register(git_dir, repo_id, locator, expected_home_revision):
    """Register a repo's stable id + locator (FR-002). Idempotent; conflicts fail closed."""
    if not isinstance(repo_id, str) or not _REPO_ID_RE.fullmatch(repo_id):
        raise errors.FoundationError(errors.SCHEMA_ERROR, f"invalid repo_id: {repo_id!r}")
    if not isinstance(locator, str) or locator == "":
        raise errors.FoundationError(errors.SCHEMA_ERROR, "locator must be a non-empty string")
    try:
        locator.encode("utf-8")  # reject surrogates/non-UTF-8 at the caller boundary (SCHEMA_ERROR)
    except UnicodeEncodeError:
        raise errors.FoundationError(errors.SCHEMA_ERROR, "locator must be UTF-8 encodable")
    head = home.read_head(git_dir)  # evaluate against current authoritative head (D-006)
    state = home.read_state(git_dir, head)
    _published(state)  # every core op fails closed on a corrupt home (incl. envelope corruption)
    registry = _registry(state)
    if registry.get(repo_id) == locator:
        return head  # idempotent no-op -> current home revision, not the caller's stale one (#9)
    if repo_id in registry:
        raise errors.FoundationError(errors.SCHEMA_ERROR, "registry conflict: repo_id already bound to another locator")
    for rid, loc in registry.items():
        if loc == locator:
            raise errors.FoundationError(errors.SCHEMA_ERROR, "registry conflict: locator already bound to another repo_id")
    entry = {"repo_id": repo_id, "locator": locator, "kind": "registry"}
    name = f"{REGISTRY_PREFIX}{repo_id}.json"
    return home.commit_entries(git_dir, expected_home_revision, {name: schema.canonical_json(entry).encode()})


def publish(git_dir, collection_identity, artifact_ref, relations, expected_home_revision):
    """Publish an Artifact Ref (+atomic relations). Fail-closed validation, Home CAS,
    envelope-digest idempotency. Returns {replay, receipt, resulting_home_revision}."""
    envelope = schema.publication_envelope(collection_identity, artifact_ref, relations)
    digest = schema.envelope_digest(collection_identity, artifact_ref, relations)
    ref, rels = envelope["artifact_ref"], envelope["relations"]
    entry_name = f"{ENVELOPE_PREFIX}{digest}.json"

    head = home.read_head(git_dir)  # current authoritative head (D-006)
    state = home.read_state(git_dir, head)

    # idempotency-first (D-005): exact envelope already present -> one-step replay.
    # Integrity (#3/ADV-21-family): trust the CONTENT, not the filename — a planted
    # entry with the right digest-name but non-matching bytes is a corrupt/poisoned
    # home, never a replay.
    if entry_name in state:
        if state[entry_name] != schema.canonical_json(envelope).encode():
            raise errors.FoundationError(
                errors.HOME_ERROR,
                "home entry corrupt: stored envelope does not match its digest-named content",
            )
        _validate_publish_authority(git_dir, state, envelope)
        return {
            "replay": True,
            "receipt": _receipt(envelope, digest),
            "resulting_home_revision": _introducing_revision(git_dir, head, entry_name),
        }

    published = _published(state)
    ref_json = schema.canonical_json(ref)

    # PUBLICATION_CONFLICT: same Ref, different envelope (relations)
    for env in published:
        if schema.canonical_json(env["artifact_ref"]) == ref_json:
            raise errors.FoundationError(errors.PUBLICATION_CONFLICT, "same Ref published with different relations")

    _validate_publish_authority(git_dir, state, envelope)

    # Home CAS write-guard (D-004): stale expected -> STALE_HOME_REVISION zero-write
    new_head = home.commit_entries(
        git_dir, expected_home_revision, {entry_name: schema.canonical_json(envelope).encode()}
    )
    return {"replay": False, "receipt": _receipt(envelope, digest), "resulting_home_revision": new_head}


def _published_ref_keys(state):
    return {schema.canonical_json(env["artifact_ref"]) for env in _published(state)}


def resolve(git_dir, artifact_ref):
    """Return digest-verified read-only bytes + resolution receipt, or fail closed.
    Never reads worktree/HEAD; returns no provenance edges."""
    ref = schema.validate_artifact_ref(artifact_ref)
    state = home.read_state(git_dir, home.read_head(git_dir))
    if schema.canonical_json(ref) not in _published_ref_keys(state):
        raise errors.Unresolvable("ref-unpublished", ref)
    registry = _registry(state)
    if ref["repo_id"] not in registry:
        raise errors.Unresolvable("repo-unregistered", ref)
    try:
        data = gitobj.resolve_verified(registry[ref["repo_id"]], ref["commit_oid"], ref["path"], ref["digest"])
    except errors.Unresolvable as unresolvable:
        # gitobj raises with reason only; attach the offending Ref (typed-fact contract, #10c)
        raise errors.Unresolvable(unresolvable.reason, ref)
    return {
        "artifact_ref": ref,
        "bytes": data,
        "resolution_receipt": {"artifact_ref": ref, "verified_digest": ref["digest"], "kind": "resolution"},
    }


def change_fact(git_dir, artifact_ref):
    """PULL change-fact: resolvability status + raw supersedes in-edges. No verdict (C4)."""
    ref = schema.validate_artifact_ref(artifact_ref)
    head = home.read_head(git_dir)
    state = home.read_state(git_dir, head)
    envs = _published(state)
    reason = _resolvability(state, ref)
    status = (
        "RESOLVABLE"
        if reason == "RESOLVABLE"
        else {"status": "UNRESOLVABLE", "reason": reason}
    )
    in_edges = [e for e in graph.direct_edges(envs, ref)["in"] if e["kind"] == "supersedes-artifact"]
    return {"resolvability": status, "supersedes_in_edges": in_edges}


def _resolvability(state, ref):
    """Resolvability from a captured home state (no head re-read, Fix 2). Published?
    from the Home snapshot; source-repo object availability is live (Fix 1)."""
    if schema.canonical_json(ref) not in _published_ref_keys(state):
        return "ref-unpublished"
    registry = _registry(state)
    if ref["repo_id"] not in registry:
        return "repo-unregistered"
    try:
        gitobj.resolve_verified(registry[ref["repo_id"]], ref["commit_oid"], ref["path"], ref["digest"])
        return "RESOLVABLE"
    except errors.Unresolvable as unresolvable:
        return unresolvable.reason


def query(git_dir, artifact_ref, kind=None):
    """Direct edges + optional typed transitive + resolvability + home_revision.

    Snapshot semantics (D-009, no-index): capture the Home head ONCE; all Home-derived
    facts come from that single snapshot and `home_revision` == the captured head.
    `resolvability` is live source-repo availability (not versioned by home_revision,
    Fix 1). Edge/status facts only (C4). transitive is the relation-directed DAG
    edge set of one kind reachable from ref (all successor/lineage branches, never
    an undirected connected component or a single "current" pick, B3).
    """
    ref = schema.validate_artifact_ref(artifact_ref)
    head = home.read_head(git_dir)          # captured once; raises HOME_ERROR if unresolvable (#5)
    state = home.read_state(git_dir, head)
    envs = _published(state)
    transitive = graph.transitive_edges(envs, ref, kind) if kind is not None else None
    return {
        "direct_edges": graph.direct_edges(envs, ref),
        "transitive": ({"kind": kind, "edges": transitive} if kind is not None else None),
        "resolvability": _resolvability(state, ref),
        "home_revision": head,
    }
