"""Exact invalidation and change propagation (PRD FR-005).

Exactness has two directions and the second is the one that gets skipped. Missing a
downstream node means shipping a result computed from inputs that moved. Invalidating
too much is invisible in a pass/fail sense -- it just makes unrelated repos redo work,
and then people stop believing the tool. The DAG corpus asserts both.

`STALE` is always a NEW record. Editing an old result to say "actually this is stale"
would destroy the distinction between "this result expired" and "this result was
rewritten", which is the only thing making old evidence worth keeping.
"""


def _dependents(edges):
    """node -> nodes that declare a depends-on edge pointing at it."""
    mapping = {}
    for edge in edges:
        if edge["kind"] == "depends-on":
            mapping.setdefault(edge["to"], []).append(edge["from"])
    return mapping


def impact_closure(old_graph, new_graph, changed_node_ids):
    """Nodes whose results can no longer be trusted, and nothing more.

    Closure follows declared depends-on edges only. An undeclared relationship is not a
    dependency, so widening the closure by guessing would be exactly the over-
    invalidation this is meant to avoid.
    """
    dependents = _dependents(new_graph["edges"])
    stale = set()
    stack = list(changed_node_ids)
    while stack:
        current = stack.pop()
        if current in stale:
            continue
        stale.add(current)
        for dependent in dependents.get(current, []):
            if dependent not in stale:
                stack.append(dependent)

    return {
        "generation": new_graph["generation"],
        "graph_digest": new_graph["graph_digest"],
        "changed_node_ids": sorted(set(changed_node_ids)),
        "stale_node_ids": sorted(stale),
        "unaffected_node_ids": sorted(
            {n["id"] for n in new_graph["nodes"]} - stale),
    }


def stale_records(graph, results, stale_node_ids):
    """Emit one immutable STALE record per affected node, editing nothing."""
    records = []
    for node_id in sorted(set(stale_node_ids)):
        prior = results.get(node_id)
        records.append({
            "kind": "STALE",
            "node_id": node_id,
            "generation": graph["generation"],
            "graph_digest": graph["graph_digest"],
            # Points AT the superseded result instead of modifying it.
            "supersedes_state": None if prior is None else prior.get("state"),
        })
    return records
