"""Consume an InitiativeScope and bind it to Foundation-resolvable artifacts.

This is the consumer boundary that program T04 and T06 define. Two things it
deliberately does NOT do:

- It does not define what an Artifact Ref is. Foundation owns that shape
  (`foundation/schema.py` `validate_artifact_ref`), and the scope has already been
  validated by its producer before arriving here.
- It does not decide resolvability. `foundation.core.resolve` answers that. A consumer
  that re-implemented the check would drift from Foundation silently, which is the
  same defect the T04 drift-check removed from the PRD prose.

InitiativeScope is the single integration contract (ADR-004). Both source kinds arrive
in the same shape, so nothing here branches on where the scope came from beyond
recording it: `manual-initiative-scope` keeps existing cross-repo runs working without
Product Scope installed, and `accepted-scope-delta` carries a projection from it.
"""

from foundation import core, errors as foundation_errors

from .errors import (
    TOPOLOGY_CYCLE,
    UNBINDABLE_REQUIREMENT,
    UNKNOWN_TOPOLOGY_ENDPOINT,
    OrchestrationError,
)


def _resolve_or_fail(foundation_home, requirement):
    ref = requirement["content_artifact_ref"]
    try:
        core.resolve(foundation_home, ref)
    except (foundation_errors.Unresolvable, foundation_errors.FoundationError) as exc:
        raise OrchestrationError(
            UNBINDABLE_REQUIREMENT,
            "requirement %s does not resolve through Foundation (%s)"
            % (requirement["requirement_id"], exc),
        )
    return {
        "requirement_id": requirement["requirement_id"],
        "version": requirement["version"],
        "artifact_ref": ref,
        "resolved": True,
    }


def _ready_order(requirement_ids, topology):
    """Deterministic topological order, or raise on an unknown endpoint or a cycle.

    Ties are broken by requirement ID so the same scope always yields the same order;
    a nondeterministic order would make a resumed run look different from the first.
    """
    known = set(requirement_ids)
    incoming = {rid: 0 for rid in requirement_ids}
    outgoing = {rid: [] for rid in requirement_ids}
    for edge in topology:
        source, target = edge["from"], edge["to"]
        for endpoint in (source, target):
            if endpoint not in known:
                raise OrchestrationError(
                    UNKNOWN_TOPOLOGY_ENDPOINT,
                    "topology endpoint %s is not in the initiative scope" % endpoint,
                )
        outgoing[source].append(target)
        incoming[target] += 1

    ready = sorted(rid for rid, count in incoming.items() if count == 0)
    order = []
    while ready:
        current = ready.pop(0)
        order.append(current)
        for target in sorted(outgoing[current]):
            incoming[target] -= 1
            if incoming[target] == 0:
                ready.append(target)
        ready.sort()

    if len(order) != len(requirement_ids):
        raise OrchestrationError(
            TOPOLOGY_CYCLE,
            "requirement topology contains a cycle; no deterministic order exists",
        )
    return order


def bind_initiative_scope(foundation_home, initiative_scope):
    """Bind every requirement in the scope, or fail without binding any.

    All-or-nothing on purpose: a partial binding would let a run start against a graph
    whose remaining nodes were never verified, and report progress that means less than
    it appears to.
    """
    requirements = initiative_scope["requirements"]
    bindings = [_resolve_or_fail(foundation_home, r) for r in requirements]
    order = _ready_order(
        [r["requirement_id"] for r in requirements],
        initiative_scope["requirement_topology"],
    )
    return {
        "initiative_scope_id": initiative_scope["initiative_scope_id"],
        "source_kind": initiative_scope["source_kind"],
        "scope_digest": initiative_scope["scope_digest"],
        "bindings": bindings,
        "ready_order": order,
    }
