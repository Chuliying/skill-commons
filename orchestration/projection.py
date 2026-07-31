"""Repo-owned projection and recoverable apply (PRD FR-003).

The ownership rule is the whole point: the coordinator may compute what a repo should
do and may never write it. `project` is pure and returns an inert proposal; `apply`
models what the repo-local plan-sync command does, guarded by a compare-and-swap on the
plan digest.

There is deliberately no cross-repo atomicity (spec D-O3). Multi-repo apply cannot be
atomic, so pretending otherwise would produce unexplainable half-states on partial
failure. Instead apply is per repo and resumable, and dependents stay BLOCKED while
their prerequisites are unapplied or applied under a different generation.
"""

import hashlib
import json

from .errors import CAS_CONFLICT, MISSING_BINDING, OrchestrationError

EXTERNAL_BLOCK_HEADER = "<!-- generated: cross-repo external dependencies -->"


def _canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _digest(obj):
    return hashlib.sha256(_canonical(obj).encode("utf-8")).hexdigest()


def _tasks_for_repo(graph, repo_id):
    return [n for n in graph["nodes"]
            if n["kind"] == "repo-task" and n.get("repo_id") == repo_id]


def _external_dependencies(graph, repo_id):
    """Task-level prerequisites owned by other repos, as declared in the graph."""
    own = {n["id"] for n in _tasks_for_repo(graph, repo_id)}
    external = []
    for edge in graph["edges"]:
        if edge["kind"] == "depends-on" and edge["from"] in own and edge["to"] not in own:
            external.append(edge["to"])
    return sorted(set(external))


def project(graph, repo_id, expected_plan_digest):
    """Produce an inert, read-only projection proposal for one repo.

    Refuses a non-dispatchable graph: projecting an incomplete graph would invite a repo
    to apply work whose inputs are still missing, and the recoverable BLOCKED state
    belongs upstream in the binding report rather than inside a plan.
    """
    if not graph.get("dispatchable", False):
        raise OrchestrationError(
            MISSING_BINDING,
            "graph is not dispatchable; resolve the binding report before projecting",
        )
    tasks = _tasks_for_repo(graph, repo_id)
    if not tasks:
        raise OrchestrationError(
            MISSING_BINDING, "no repo-task node for repo %s in this graph" % repo_id)

    proposal = {
        "repo_id": repo_id,
        "generation": graph["generation"],
        "graph_digest": graph["graph_digest"],
        "expected_plan_digest": expected_plan_digest,
        "node_ids": sorted(node["id"] for node in tasks),
        "external_dependencies": _external_dependencies(graph, repo_id),
    }
    proposal["proposal_digest"] = _digest(proposal)
    return proposal


def _external_block(proposal):
    lines = [EXTERNAL_BLOCK_HEADER,
             "generation: %s" % proposal["generation"],
             "graph: %s" % proposal["graph_digest"]]
    for dependency in proposal["external_dependencies"]:
        lines.append("depends-on: %s" % dependency)
    return "\n".join(lines)


def _receipt(proposal):
    receipt = {
        "repo_id": proposal["repo_id"],
        "generation": proposal["generation"],
        "graph_digest": proposal["graph_digest"],
        "proposal_digest": proposal["proposal_digest"],
        "applied_node_ids": proposal["node_ids"],
    }
    receipt["receipt_digest"] = _digest(receipt)
    return receipt


def apply(proposal, plan):
    """Repo-local apply: CAS on the plan digest, then update only the generated block.

    Returns BLOCKED with zero writes when the plan moved. That is not a failure to
    retry blindly -- the local plan changed under the proposal, so the owner must
    re-project and review before applying.
    """
    receipt = _receipt(proposal)
    if plan.get("applied_receipt_digest") == receipt["receipt_digest"]:
        # Already applied by this exact proposal; recognise it instead of writing again.
        return {"state": "APPLIED", "plan": plan, "receipt": receipt}

    if plan["digest"] != proposal["expected_plan_digest"]:
        return {"state": "BLOCKED", "reason": CAS_CONFLICT,
                "expected": proposal["expected_plan_digest"],
                "actual": plan["digest"]}

    # Only the generated external block and the applied receipt change. Everything the
    # repo owns -- task list, statuses, notes -- is carried through untouched.
    updated = dict(plan)
    updated["external_block"] = _external_block(proposal)
    updated["applied_receipt_digest"] = receipt["receipt_digest"]
    return {"state": "APPLIED", "plan": updated, "receipt": receipt}


def apply_status(graph, receipts):
    """Which repos still need to apply, and which nodes that leaves blocked.

    A receipt only counts for this graph if it carries the same generation AND graph
    digest. A receipt from another generation is not a weaker form of applied -- it
    describes different inputs, so treating it as satisfied is how a mixed-generation
    dispatch happens.
    """
    applied_repos = set()
    for repo_id, receipt in receipts.items():
        if (receipt.get("generation") == graph["generation"]
                and receipt.get("graph_digest") == graph["graph_digest"]):
            applied_repos.add(repo_id)

    task_nodes = [n for n in graph["nodes"] if n["kind"] == "repo-task"]
    pending = sorted({n["repo_id"] for n in task_nodes
                      if n.get("repo_id") not in applied_repos})

    prerequisites = {}
    for edge in graph["edges"]:
        if edge["kind"] == "depends-on":
            prerequisites.setdefault(edge["from"], []).append(edge["to"])

    node_repo = {n["id"]: n.get("repo_id") for n in task_nodes}
    blocked, ready = [], []
    # Three outcomes, not two. A node is READY only when its own repo has applied THIS
    # generation and its prerequisites have too. Reporting an unapplied node as ready is
    # how a dispatch happens against a plan that never received the projection -- the
    # mixed-generation dispatch AC-006 exists to prevent.
    awaiting_apply = []
    for node in task_nodes:
        unmet = [target for target in prerequisites.get(node["id"], [])
                 if node_repo.get(target) not in applied_repos]
        if unmet:
            blocked.append(node["id"])
        elif node_repo.get(node["id"]) in applied_repos:
            ready.append(node["id"])
        else:
            awaiting_apply.append(node["id"])
    return {
        "pending_repo_ids": pending,
        "blocked_node_ids": sorted(blocked),
        "awaiting_apply_node_ids": sorted(awaiting_apply),
        "ready_node_ids": sorted(set(ready) - set(blocked)),
        "applied_repo_ids": sorted(applied_repos),
    }
