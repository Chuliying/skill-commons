"""Provenance graph over published envelopes (spec FR-004/FR-007, D-008/D-009).

Pure logic: it is always rebuilt from the caller-supplied envelope set (the
authoritative home state at head, D-006/D-009), so there is no stale cache here.
Returns edge/status facts only — never a "current"/"stale" verdict (C4).
"""

from foundation import errors, schema


def ref_key(ref):
    """Stable identity key for an Artifact Ref."""
    return schema.canonical_json(schema.validate_artifact_ref(ref))


def _edges(envelopes):
    """Yield normalized edges {kind, subject, object} from envelopes."""
    for env in envelopes:
        subject = schema.validate_artifact_ref(env["artifact_ref"])
        for rel in env.get("relations", []):
            norm = schema.validate_relation(rel)
            yield {"kind": norm["kind"], "subject": subject, "object": norm["object"]}


def _sorted_edges(edges):
    return sorted(edges, key=schema.canonical_json)


def check_supersedes_kinds(subject_ref, relations):
    """supersedes-artifact must relate same artifact_kind (FR-004), else SCHEMA_ERROR."""
    subject = schema.validate_artifact_ref(subject_ref)
    for rel in relations or []:
        norm = schema.validate_relation(rel)
        if norm["kind"] == "supersedes-artifact":
            if norm["object"]["artifact_kind"] != subject["artifact_kind"]:
                raise errors.FoundationError(
                    errors.SCHEMA_ERROR,
                    "supersedes-artifact endpoints must share artifact_kind",
                )


def check_acyclic(envelopes):
    """Raise SCHEMA_ERROR if the union edge graph has a cycle or self-edge."""
    adjacency = {}
    for edge in _edges(envelopes):
        src, dst = ref_key(edge["subject"]), ref_key(edge["object"])
        if src == dst:
            raise errors.FoundationError(errors.SCHEMA_ERROR, "self-edge in provenance graph")
        adjacency.setdefault(src, set()).add(dst)
        adjacency.setdefault(dst, set())

    # Iterative DFS (explicit stack) so deep provenance chains fail closed with a
    # typed error, never an untyped RecursionError (B3).
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {node: WHITE for node in adjacency}
    for start in sorted(adjacency):
        if color[start] != WHITE:
            continue
        color[start] = GRAY
        stack = [(start, iter(sorted(adjacency[start])))]
        while stack:
            node, children = stack[-1]
            advanced = False
            for nxt in children:
                if color[nxt] == GRAY:
                    raise errors.FoundationError(errors.SCHEMA_ERROR, "cycle in provenance graph")
                if color[nxt] == WHITE:
                    color[nxt] = GRAY
                    stack.append((nxt, iter(sorted(adjacency[nxt]))))
                    advanced = True
                    break
            if not advanced:
                color[node] = BLACK
                stack.pop()


def direct_edges(envelopes, ref):
    """Return {out, in} direct edges for ref (both directions), deterministically."""
    key = ref_key(ref)
    out_edges = [e for e in _edges(envelopes) if ref_key(e["subject"]) == key]
    in_edges = [e for e in _edges(envelopes) if ref_key(e["object"]) == key]
    return {"out": _sorted_edges(out_edges), "in": _sorted_edges(in_edges)}


def transitive_edges(envelopes, ref, kind):
    """Directional closure of one relation kind as a deterministic DAG edge set.

    ``supersedes-artifact`` follows incoming edges because a successor points to
    the artifact it supersedes. ``derived-from`` and ``evidences`` follow outgoing
    declaration edges. This returns every branch in the requested direction without
    turning the graph into an undirected connected-component query (B3/C4).
    """
    if kind not in schema.RELATION_KINDS:
        raise errors.FoundationError(errors.SCHEMA_ERROR, f"unknown relation kind: {kind!r}")
    out_adj, in_adj = {}, {}
    for edge in _edges(envelopes):
        if edge["kind"] != kind:
            continue
        out_adj.setdefault(ref_key(edge["subject"]), []).append(edge)
        in_adj.setdefault(ref_key(edge["object"]), []).append(edge)

    follow_incoming = kind == "supersedes-artifact"
    adjacency = in_adj if follow_incoming else out_adj
    collected = {}
    frontier = [ref_key(ref)]
    seen = set()
    while frontier:
        node = frontier.pop()
        if node in seen:
            continue
        seen.add(node)
        for edge in adjacency.get(node, []):
            collected[schema.canonical_json(edge)] = edge
            next_ref = edge["subject"] if follow_incoming else edge["object"]
            frontier.append(ref_key(next_ref))
    return [collected[key] for key in sorted(collected)]
