"""Closed schemas + canonical JSON + envelope digest (spec Contracts, D-003/D-017).

Deterministic serialization is the backbone of publish idempotency: the
publication-envelope digest is the idempotency key, so canonical_json must be
byte-stable and the relation set must be dedup'd + order-independent.
"""

import hashlib
import json
import posixpath
import re

from foundation import errors

# Artifact Ref identity (B1): repo_id is part of the identity so the same commit
# OID in two registered repos (fork/clone) is a distinct Ref.
ARTIFACT_REF_FIELDS = ("repo_id", "commit_oid", "path", "digest", "artifact_kind")

# Pin identity formats (M1): a git commit OID is 40 (sha1) or 64 (sha256) lowercase
# hex; the content digest is sha256 hex. This stops abbreviated/upper-case variants
# of the same object from becoming distinct Ref identities.
_COMMIT_OID_RE = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_REPO_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

# Provenance vocabulary V1 (FR-004): closed set. Unknown kind fails closed.
RELATION_KINDS = frozenset({"derived-from", "supersedes-artifact", "evidences"})


def canonical_json(obj):
    """Byte-stable JSON: sorted keys, tight separators, UTF-8, no trailing NL."""
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def collection_identity(repo_id, path):
    """Derive the canonical Collection Home identity from repo ID + repo-relative path."""
    if not isinstance(repo_id, str) or not _REPO_ID_RE.fullmatch(repo_id):
        raise errors.FoundationError(
            errors.SCHEMA_ERROR,
            f"collection repo_id is invalid: {repo_id!r}",
        )
    if not isinstance(path, str) or path == "":
        raise errors.FoundationError(
            errors.SCHEMA_ERROR,
            "collection path must be a non-empty repo-relative path",
        )
    identity = f"{repo_id}/{path}"
    return validate_collection_identity(identity)


def validate_collection_identity(value):
    """Validate the closed ``repo_id/repo-relative-path`` collection identity form."""
    if not isinstance(value, str) or value == "" or "/" not in value:
        raise errors.FoundationError(
            errors.SCHEMA_ERROR,
            "collection_identity must be repo_id/repo-relative-path",
        )
    repo_id, path = value.split("/", 1)
    if not _REPO_ID_RE.fullmatch(repo_id):
        raise errors.FoundationError(
            errors.SCHEMA_ERROR,
            f"collection_identity repo_id is invalid: {repo_id!r}",
        )
    segments = path.split("/")
    if (
        path == ""
        or path.startswith("~")
        or path.startswith("/")
        or "\\" in path
        or "\x00" in path
        or any(segment in ("", ".", "..", "~") for segment in segments)
        or posixpath.normpath(path) != path
    ):
        raise errors.FoundationError(
            errors.SCHEMA_ERROR,
            "collection_identity path must be canonical and repo-relative",
        )
    return value


def validate_artifact_ref(obj):
    """Return a normalized Artifact Ref or raise SCHEMA_ERROR (closed shape)."""
    if not isinstance(obj, dict):
        raise errors.FoundationError(errors.SCHEMA_ERROR, "artifact_ref must be an object")
    keys = set(obj)
    expected = set(ARTIFACT_REF_FIELDS)
    if keys != expected:
        missing = sorted(expected - keys)
        unknown = sorted(keys - expected)
        raise errors.FoundationError(
            errors.SCHEMA_ERROR,
            f"artifact_ref field mismatch (missing={missing}, unknown={unknown})",
        )
    for field in ARTIFACT_REF_FIELDS:
        value = obj[field]
        if not isinstance(value, str) or value == "":
            raise errors.FoundationError(
                errors.SCHEMA_ERROR, f"artifact_ref.{field} must be a non-empty string"
            )
    if not _COMMIT_OID_RE.fullmatch(obj["commit_oid"]):
        raise errors.FoundationError(
            errors.SCHEMA_ERROR, "artifact_ref.commit_oid must be 40 or 64 lowercase hex"
        )
    if not _SHA256_RE.fullmatch(obj["digest"]):
        raise errors.FoundationError(
            errors.SCHEMA_ERROR, "artifact_ref.digest must be 64 lowercase hex (sha256)"
        )
    # path must be canonical + repo-relative (same rule as collection_identity), so one
    # physical artifact cannot get two Ref identities via non-canonical spellings
    # (e.g. "./a.md" vs "a.md") and sidestep PUBLICATION_CONFLICT.
    path = obj["path"]
    segments = path.split("/")
    if (
        path.startswith("~")
        or path.startswith("/")
        or "\\" in path
        or "\x00" in path
        or any(segment in ("", ".", "..", "~") for segment in segments)
        or posixpath.normpath(path) != path
    ):
        raise errors.FoundationError(
            errors.SCHEMA_ERROR, "artifact_ref.path must be canonical and repo-relative"
        )
    return {field: obj[field] for field in ARTIFACT_REF_FIELDS}


def validate_relation(obj):
    """Return a normalized relation {kind, object} or raise SCHEMA_ERROR."""
    if not isinstance(obj, dict) or set(obj) != {"kind", "object"}:
        raise errors.FoundationError(
            errors.SCHEMA_ERROR, "relation must be {kind, object}"
        )
    kind = obj["kind"]
    # isinstance guard BEFORE the membership test: an unhashable kind (list/dict) would
    # otherwise raise an untyped TypeError from `kind not in frozenset`.
    if not isinstance(kind, str) or kind not in RELATION_KINDS:
        raise errors.FoundationError(
            errors.SCHEMA_ERROR, f"unknown relation kind: {kind!r}"
        )
    return {"kind": kind, "object": validate_artifact_ref(obj["object"])}


def canonical_relations(relations):
    """Validate, dedup, and deterministically sort a relation set.

    Dedup + sort make the relation set order-independent so a reordered or
    duplicated relation list produces the same envelope digest.
    """
    if relations is None:
        relations = []
    if not isinstance(relations, list):
        raise errors.FoundationError(errors.SCHEMA_ERROR, "relations must be a list")
    seen = {}
    for rel in relations:
        norm = validate_relation(rel)
        seen[canonical_json(norm)] = norm
    return [seen[key] for key in sorted(seen)]


def publication_envelope(collection_identity, artifact_ref, relations):
    """Build the canonical publication envelope (idempotency-key source)."""
    return {
        "collection_identity": validate_collection_identity(collection_identity),
        "artifact_ref": validate_artifact_ref(artifact_ref),
        "relations": canonical_relations(relations),
    }


def envelope_digest(collection_identity, artifact_ref, relations):
    """sha256 of the canonical publication envelope (hex)."""
    envelope = publication_envelope(collection_identity, artifact_ref, relations)
    return hashlib.sha256(canonical_json(envelope).encode("utf-8")).hexdigest()
