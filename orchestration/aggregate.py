"""Advisory aggregate and the verification boundary (PRD FR-006).

The aggregate answers one question -- what should I do next -- and it must answer it the
same way every time, so precedence and ordering are fixed rather than emergent:
`STALE > FAILED > BLOCKED`, then typed topological order, then repo ID, then node ID.
A target with several conditions keeps only its highest-precedence action, otherwise the
operator is handed the same node twice with different advice.

`ADVISORY_COMPLETE` is the ceiling. There is no `VERIFIED` in V1 (spec D-O4): a local
operator controls the workspace and the command output, so no amount of local evidence
is release evidence. Fields that merely look trusted are ignored rather than honoured --
if a forged `trusted: true` could raise the aggregate, the boundary would be decoration.
"""

from .errors import UNKNOWN_EVIDENCE_STATE, OrchestrationError

AGGREGATE_STATES = ("ADVISORY_COMPLETE", "STALE", "FAILED", "BLOCKED", "IN_PROGRESS")
# Highest first. This ordering is the contract, not an implementation detail.
PRECEDENCE = ("STALE", "FAILED", "BLOCKED")
RESULT_STATES = ("OBSERVED", "FAILED", "BLOCKED")

RECOVERY = {
    "STALE": "REBIND_IMPACT",
    "FAILED": "RESOLVE_FAILURE",
    "BLOCKED": "RESOLVE_BLOCKER",
}


def _topological_index(graph):
    """Position of each node in a deterministic topological order over depends-on."""
    node_ids = [n["id"] for n in graph["nodes"]]
    incoming = {n: 0 for n in node_ids}
    outgoing = {n: [] for n in node_ids}
    for edge in graph["edges"]:
        if edge["kind"] != "depends-on":
            continue
        # A raw KeyError here would be a fail-OPEN crash in a module whose whole posture
        # is fail-closed: the caller cannot distinguish it from a bug and may retry.
        for endpoint in (edge["from"], edge["to"]):
            if endpoint not in incoming:
                raise OrchestrationError(
                    UNKNOWN_EVIDENCE_STATE,
                    "edge references node %s that is not in the graph" % endpoint,
                )
        outgoing[edge["to"]].append(edge["from"])
        incoming[edge["from"]] += 1
    ready = sorted(n for n, count in incoming.items() if count == 0)
    order = []
    while ready:
        current = ready.pop(0)
        order.append(current)
        for dependent in sorted(outgoing[current]):
            incoming[dependent] -= 1
            if incoming[dependent] == 0:
                ready.append(dependent)
        ready.sort()
    # Any node left out of a cyclic graph still gets a stable position.
    for node_id in node_ids:
        if node_id not in order:
            order.append(node_id)
    return {node_id: index for index, node_id in enumerate(order)}


def aggregate(graph, results, stale_node_ids):
    """Closed aggregate state plus a complete, deterministically ordered action list."""
    for node_id, result in results.items():
        state = result.get("state")
        if state not in RESULT_STATES:
            raise OrchestrationError(
                UNKNOWN_EVIDENCE_STATE,
                "result for %s carries unknown state %r; allowed: %s"
                % (node_id, state, RESULT_STATES),
            )

    repo_of = {n["id"]: n.get("repo_id") for n in graph["nodes"]}
    # Results and stale IDs for nodes outside the graph produced phantom actions with
    # repo_id None. Silently ranking an action for a node nobody can act on is worse
    # than refusing the input.
    for node_id in list(results) + list(stale_node_ids):
        if node_id not in repo_of:
            raise OrchestrationError(
                UNKNOWN_EVIDENCE_STATE,
                "result or stale record names node %s that is not in the graph" % node_id,
            )
    position = _topological_index(graph)

    # One condition per target: the highest precedence wins so advice is never doubled.
    condition = {}
    for node_id in stale_node_ids:
        condition[node_id] = "STALE"
    for node_id, result in results.items():
        if result["state"] in ("FAILED", "BLOCKED"):
            existing = condition.get(node_id)
            if existing is None or PRECEDENCE.index(result["state"]) < PRECEDENCE.index(existing):
                condition[node_id] = result["state"]

    actions = [
        {
            "node_id": node_id,
            "repo_id": repo_of.get(node_id),
            "state": state,
            "action": RECOVERY[state],
        }
        for node_id, state in condition.items()
    ]
    actions.sort(key=lambda a: (
        PRECEDENCE.index(a["state"]),
        position.get(a["node_id"], len(position)),
        a["repo_id"] or "",
        a["node_id"],
    ))

    if actions:
        aggregate_state = actions[0]["state"]
    else:
        task_ids = [n["id"] for n in graph["nodes"] if n["kind"] == "repo-task"]
        observed = [n for n in task_ids
                    if results.get(n, {}).get("state") == "OBSERVED"]
        aggregate_state = ("ADVISORY_COMPLETE"
                          if task_ids and len(observed) == len(task_ids)
                          else "IN_PROGRESS")

    return {
        "aggregate": aggregate_state,
        "actions": actions,
        "next_action": actions[0] if actions else None,
    }


def verify_capability(provider):
    """Report the trusted-verification boundary without touching the aggregate.

    Returning a distinct operation result -- rather than a state inside the aggregate --
    is what keeps "not installed" from reading as "verified" or as a blocker on work
    that is already advisory-complete.
    """
    if provider is None:
        return {"result": "VERIFICATION_UNAVAILABLE",
                "reason": "no trusted verification provider is configured"}
    return {"result": "VERIFICATION_UNAVAILABLE",
            "reason": "V1 declares no trusted provider capability; %r is not honoured"
                      % provider}
