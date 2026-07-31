"""Canonical, closed contracts for Product Scope (PRD FR-002/003/004/007).

Closed shape is not pedantry here: identity is what the activation CAS keys on, so
an unknown field or a reordered list must not be able to produce a second identity
for the same decision. Canonical ordering is applied before digesting for the same
reason.

Artifact Ref is NOT defined here. Foundation owns it (foundation/schema.py
validate_artifact_ref); this module delegates so there is one shape, not two.
"""

import hashlib
import json

from foundation import errors as foundation_errors
from foundation import schema as foundation_schema

from . import errors

ENVELOPE_FIELDS = (
    "product_id",
    "proposal_id",
    "base_scope_revision",
    "source_artifact_ref",
    "requirement_changes",
    "declared_relations",
    "proposal_kind",
)
PROPOSAL_KINDS = ("team-prd", "personal-change", "baseline-import")

DELTA_FIELDS = (
    "product_id",
    "proposal_ref",
    "parent_scope_revision",
    "accepted_changes",
    "accepted_relations",
    "requirement_impact",
    "decision_context",
    "delta_digest",
)
DECISION_CONTEXT_FIELDS = (
    "mode",
    "source_package_path",
    "source_package_digest",
    "decided_at",
)
DECISION_MODES = ("team-gate-1", "personal-apply")

INITIATIVE_FIELDS = (
    "initiative_scope_id",
    "source_kind",
    "product_id",
    "scope_revision",
    "requirements",
    "requirement_topology",
    "scope_digest",
)
SOURCE_KINDS = ("accepted-scope-delta", "manual-initiative-scope")

ANALYSIS_FIELDS = (
    "envelope_digest",
    "base_scope_revision",
    "deterministic_matches",
    "advisory_candidates",
    "canonical_diff",
    "conflicts",
    "impact_candidates",
)
DIFF_FIELDS = ("added", "modified", "superseded", "removed", "unchanged")


def _fail(message):
    raise errors.ProductScopeError(errors.SCHEMA_ERROR, message)


def canonical_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _digest(obj):
    return hashlib.sha256(canonical_json(obj).encode("utf-8")).hexdigest()


def _closed(obj, fields, label):
    if not isinstance(obj, dict):
        _fail("%s must be an object" % label)
    keys = set(obj)
    expected = set(fields)
    if keys != expected:
        missing = sorted(expected - keys)
        unknown = sorted(keys - expected)
        _fail("%s field mismatch (missing=%s, unknown=%s)" % (label, missing, unknown))


def _nonempty_str(value, label):
    if not isinstance(value, str) or value == "":
        _fail("%s must be a non-empty string" % label)


def _artifact_ref(value, label):
    """Delegate to Foundation and translate its error into ours."""
    try:
        return foundation_schema.validate_artifact_ref(value)
    except foundation_errors.FoundationError as exc:
        _fail("%s is not a valid Foundation Artifact Ref (%s)" % (label, exc))


def _sorted_changes(changes, label):
    if not isinstance(changes, list):
        _fail("%s must be a list" % label)
    for change in changes:
        _closed(change, ("requirement_id", "operation"), "%s entry" % label)
        _nonempty_str(change["requirement_id"], "%s.requirement_id" % label)
        if change["operation"] not in ("ADD", "MODIFY", "SUPERSEDE", "REMOVE"):
            _fail("%s.operation must be ADD, MODIFY, SUPERSEDE or REMOVE" % label)
    return sorted(changes, key=lambda c: (c["requirement_id"], c["operation"]))


def _reject_duplicate_requirement_ids(changes, label):
    requirement_ids = set()
    for change in changes:
        requirement_id = change["requirement_id"]
        if requirement_id in requirement_ids:
            raise errors.ProductScopeError(
                errors.DUPLICATE_REQUIREMENT_ID,
                "%s must not repeat requirement_id: %s" % (label, requirement_id),
            )
        requirement_ids.add(requirement_id)


def _sorted_relations(relations, label):
    if not isinstance(relations, list):
        _fail("%s must be a list" % label)
    return sorted(relations, key=canonical_json)


def validate_envelope(obj):
    """Return a canonical ScopeChangeEnvelope v1."""
    _closed(obj, ENVELOPE_FIELDS, "envelope")
    for field in ("product_id", "proposal_id", "base_scope_revision"):
        _nonempty_str(obj[field], "envelope.%s" % field)
    if obj["proposal_kind"] not in PROPOSAL_KINDS:
        _fail("envelope.proposal_kind must be one of %s" % (PROPOSAL_KINDS,))
    return {
        "product_id": obj["product_id"],
        "proposal_id": obj["proposal_id"],
        "base_scope_revision": obj["base_scope_revision"],
        "source_artifact_ref": _artifact_ref(
            obj["source_artifact_ref"], "envelope.source_artifact_ref"
        ),
        "requirement_changes": _sorted_changes(
            obj["requirement_changes"], "envelope.requirement_changes"
        ),
        "declared_relations": _sorted_relations(
            obj["declared_relations"], "envelope.declared_relations"
        ),
        "proposal_kind": obj["proposal_kind"],
    }


def envelope_digest(obj):
    """Digest of the CANONICAL envelope, so ordering cannot fork identity."""
    return _digest(validate_envelope(obj))


def build_analysis(
    envelope_digest,
    base_scope_revision,
    deterministic_matches,
    advisory_candidates,
    canonical_diff,
    conflicts,
    impact_candidates,
):
    """Assemble a read-only ScopeAnalysis v1.

    deterministic and advisory stay in separate keys and are never merged: the whole
    point of ADR-003 is that a reader can tell which class a statement belongs to.
    advisory_candidates=None means the semantic service is absent, which is reported
    as unavailable rather than as "no candidates" (PRD ERR-008).
    """
    _nonempty_str(base_scope_revision, "analysis.base_scope_revision")
    if not isinstance(canonical_diff, dict) or set(canonical_diff) != set(DIFF_FIELDS):
        _fail("analysis.canonical_diff must carry exactly %s" % (DIFF_FIELDS,))
    advisory = (
        {"status": "unavailable"}
        if advisory_candidates is None
        else sorted(advisory_candidates, key=canonical_json)
    )
    return {
        "envelope_digest": envelope_digest,
        "base_scope_revision": base_scope_revision,
        "deterministic_matches": sorted(deterministic_matches, key=canonical_json),
        "advisory_candidates": advisory,
        "canonical_diff": {k: sorted(canonical_diff[k]) for k in DIFF_FIELDS},
        "conflicts": sorted(conflicts, key=canonical_json),
        "impact_candidates": sorted(impact_candidates, key=canonical_json),
    }


def validate_delta(obj):
    """Return a canonical AcceptedScopeDelta v1."""
    _closed(obj, DELTA_FIELDS, "delta")
    for field in ("product_id", "proposal_ref", "delta_digest"):
        _nonempty_str(obj[field], "delta.%s" % field)
    context = obj["decision_context"]
    _closed(context, DECISION_CONTEXT_FIELDS, "delta.decision_context")
    if context["mode"] not in DECISION_MODES:
        _fail("delta.decision_context.mode must be one of %s" % (DECISION_MODES,))
    for field in DECISION_CONTEXT_FIELDS:
        _nonempty_str(context[field], "delta.decision_context.%s" % field)
    accepted_changes = _sorted_changes(obj["accepted_changes"], "delta.accepted_changes")
    _reject_duplicate_requirement_ids(accepted_changes, "delta.accepted_changes")
    return {
        "product_id": obj["product_id"],
        "proposal_ref": obj["proposal_ref"],
        "parent_scope_revision": obj["parent_scope_revision"],
        "accepted_changes": accepted_changes,
        "accepted_relations": _sorted_relations(
            obj["accepted_relations"], "delta.accepted_relations"
        ),
        "requirement_impact": _sorted_relations(
            obj["requirement_impact"], "delta.requirement_impact"
        ),
        "decision_context": {field: context[field] for field in DECISION_CONTEXT_FIELDS},
        "delta_digest": obj["delta_digest"],
    }


def validate_delta_against_analysis(delta, analysis, explicitly_accepted=()):
    """Refuse a delta that smuggles an advisory candidate into accepted relations.

    ADR-003 says semantic similarity may only produce candidates, and that nothing
    becomes an accepted relation without the existing Gate 1 or personal-apply decision
    accepting it. Stating that in prose is not enforcement: without this check a caller
    could copy a candidate straight into `accepted_relations` and every contract
    validator would still pass, which is exactly what the earlier test failed to notice
    because it built its own delta with an empty relation list.

    `explicitly_accepted` is what the owner actually selected at the gate.
    """
    delta = validate_delta(delta)
    if (
        delta["proposal_ref"] != analysis.get("envelope_digest")
        or delta["parent_scope_revision"] != analysis.get("base_scope_revision")
    ):
        raise errors.ProductScopeError(
            errors.IDENTITY_MISMATCH,
            "delta identity must match analysis envelope digest and base scope revision",
        )
    advisory = analysis.get("advisory_candidates")
    if not isinstance(advisory, list):
        return delta          # semantic service unavailable: no candidates existed
    accepted_keys = {canonical_json(item) for item in explicitly_accepted}
    candidate_keys = {canonical_json(item) for item in advisory}
    for relation in delta["accepted_relations"]:
        key = canonical_json(relation)
        if key in candidate_keys and key not in accepted_keys:
            raise errors.ProductScopeError(
                errors.ADVISORY_NOT_ACCEPTED,
                "advisory candidate entered accepted_relations without an explicit "
                "acceptance: %s" % key,
            )
    return delta


def validate_initiative_scope(obj):
    """Return a canonical InitiativeScope v1.

    An empty requirements list is refused: projection is an explicit owner action
    (ADR-004), and an empty scope would let a caller claim a projection happened
    while conveying no owner-selected boundary (PRD ERR-009).
    """
    _closed(obj, INITIATIVE_FIELDS, "initiative_scope")
    _nonempty_str(obj["initiative_scope_id"], "initiative_scope.initiative_scope_id")
    _nonempty_str(obj["scope_digest"], "initiative_scope.scope_digest")
    if obj["source_kind"] not in SOURCE_KINDS:
        _fail("initiative_scope.source_kind must be one of %s" % (SOURCE_KINDS,))
    if obj["source_kind"] == "accepted-scope-delta":
        for field in ("product_id", "scope_revision"):
            _nonempty_str(obj[field], "initiative_scope.%s" % field)
    requirements = obj["requirements"]
    if not isinstance(requirements, list) or not requirements:
        _fail("initiative_scope.requirements must be a non-empty owner-selected list")
    normalized = []
    for requirement in requirements:
        _closed(
            requirement,
            ("requirement_id", "version", "content_artifact_ref", "digest"),
            "initiative_scope.requirements entry",
        )
        _nonempty_str(requirement["requirement_id"], "requirement_id")
        _nonempty_str(requirement["version"], "version")
        _nonempty_str(requirement["digest"], "digest")
        normalized.append(
            {
                "requirement_id": requirement["requirement_id"],
                "version": requirement["version"],
                "content_artifact_ref": _artifact_ref(
                    requirement["content_artifact_ref"], "content_artifact_ref"
                ),
                "digest": requirement["digest"],
            }
        )
    return {
        "initiative_scope_id": obj["initiative_scope_id"],
        "source_kind": obj["source_kind"],
        "product_id": obj["product_id"],
        "scope_revision": obj["scope_revision"],
        "requirements": sorted(normalized, key=lambda r: r["requirement_id"]),
        "requirement_topology": _sorted_relations(
            obj["requirement_topology"], "initiative_scope.requirement_topology"
        ),
        "scope_digest": obj["scope_digest"],
    }
