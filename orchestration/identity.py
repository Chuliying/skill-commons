"""Repo identity, participant registry and bootstrap slice proposals (PRD FR-001).

Bootstrap exists to break a circular dependency the PRD records: an earlier design
required participant Spec/QA/plan refs in order to produce the slices that told each
participant what to build. So this step reads only what already exists — a committed
Initiative PRD ref, the registry, the owner's assignment and the owner's declared
topology — and never asks for an artifact the participant has not written yet.

Everything here is pure. It reads no Git state and writes none, which is what makes
`build_slice_proposals` deterministic and safely re-runnable.
"""

from .errors import (
    DUPLICATE_REPO_ID,
    OWNERSHIP_CONFLICT,
    UNKNOWN_TOPOLOGY_ENDPOINT,
    UNSUPPORTED_PARTICIPANT_COUNT,
    UNSUPPORTED_PROFILE,
    OrchestrationError,
)

# Closed contract (PRD FR-002 binding matrix). A profile outside this table does not
# get a cross-repo slice at all; its existing single-repo flow is untouched.
WORKFLOW_PROFILES = {
    "team-feature": {
        "required_bindings": ("prd", "spec", "qa-plan", "execution-plan"),
        "optional_bindings": (),
    },
    "personal-feature": {
        "required_bindings": ("execution-plan",),
        "optional_bindings": ("prd-snapshot",),
    },
}


def required_bindings(workflow_profile):
    return WORKFLOW_PROFILES[workflow_profile]["required_bindings"]


def _validate_registry(registry):
    """Repo IDs are identity, so near-duplicates are refused rather than normalized.

    Case folding is checked because two entries differing only in case would resolve
    to one repo on a case-insensitive filesystem while looking distinct in the
    registry -- an ownership split that is invisible in the declared inputs.
    """
    participant_count = len(registry)
    if not 2 <= participant_count <= 5:
        raise OrchestrationError(
            UNSUPPORTED_PARTICIPANT_COUNT,
            "participant count %d is outside the supported range 2-5"
            % participant_count,
        )

    seen_folded = {}
    for entry in registry:
        repo_id = entry["repo_id"]
        profile = entry.get("workflow_profile")
        if profile not in WORKFLOW_PROFILES:
            raise OrchestrationError(
                UNSUPPORTED_PROFILE,
                "repo %s declares unsupported workflow profile %r" % (repo_id, profile),
            )
        folded = repo_id.casefold()
        if folded in seen_folded:
            raise OrchestrationError(
                DUPLICATE_REPO_ID,
                "repo IDs %r and %r collide under case folding"
                % (seen_folded[folded], repo_id),
            )
        seen_folded[folded] = repo_id
    return {entry["repo_id"]: entry for entry in registry}


def _validate_assignments(assignments, repo_ids):
    """Each requirement belongs to exactly one repo slice (PRD FR-001)."""
    owner_of = {}
    for entry in assignments:
        requirement_id = entry["requirement_id"]
        repo_id = entry["repo_id"]
        if repo_id not in repo_ids:
            raise OrchestrationError(
                OWNERSHIP_CONFLICT,
                "requirement %s assigned to unregistered repo %s"
                % (requirement_id, repo_id),
            )
        if requirement_id in owner_of and owner_of[requirement_id] != repo_id:
            raise OrchestrationError(
                OWNERSHIP_CONFLICT,
                "requirement %s is assigned to both %s and %s"
                % (requirement_id, owner_of[requirement_id], repo_id),
            )
        owner_of[requirement_id] = repo_id
    return owner_of


def _validate_topology(topology, requirement_ids):
    """Edges must be owner-declared and reference assigned requirements only.

    No edge is ever inferred: a dependency the owner did not declare would change the
    execution order without appearing in the provenance the proposal carries.
    """
    for edge in topology:
        for endpoint in (edge["from"], edge["to"]):
            if endpoint not in requirement_ids:
                raise OrchestrationError(
                    UNKNOWN_TOPOLOGY_ENDPOINT,
                    "topology endpoint %s is not an assigned requirement" % endpoint,
                )
    return [{"from": edge["from"], "to": edge["to"]} for edge in topology]


def build_slice_proposals(initiative_prd_ref, registry, assignments, topology):
    """Produce one immutable slice proposal per participant.

    The proposal deliberately carries no Spec/QA/plan reference: those artifacts are
    what the slice asks the participant to produce, and requiring them here is the
    circular dependency this step exists to avoid.
    """
    repos = _validate_registry(registry)
    owner_of = _validate_assignments(assignments, set(repos))
    declared_topology = _validate_topology(topology, set(owner_of))

    by_repo = {}
    for requirement_id, repo_id in sorted(owner_of.items()):
        by_repo.setdefault(repo_id, []).append(requirement_id)

    slices = []
    for repo_id in sorted(by_repo):
        profile = repos[repo_id]["workflow_profile"]
        requirement_ids = by_repo[repo_id]
        owned = set(requirement_ids)
        slices.append({
            "repo_id": repo_id,
            "owner": repos[repo_id].get("owner"),
            "workflow_profile": profile,
            "requirement_ids": requirement_ids,
            "required_bindings": list(required_bindings(profile)),
            # Exact incoming/outgoing edges, so a participant sees its own boundary
            # without reading the whole initiative.
            "incoming_edges": [e for e in declared_topology
                               if e["to"] in owned and e["from"] not in owned],
            "outgoing_edges": [e for e in declared_topology
                               if e["from"] in owned and e["to"] not in owned],
            "prd_provenance": initiative_prd_ref,
        })

    return {
        "initiative_prd_ref": initiative_prd_ref,
        "slices": slices,
        "topology": declared_topology,
    }
