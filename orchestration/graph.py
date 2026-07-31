"""Immutable execution Work Graph with a closed grammar (PRD FR-002).

The grammar is closed on purpose. A validator can only claim "this graph is complete"
if it knows every legal node and edge kind; with an open grammar an unknown edge is
indistinguishable from an edge the validator forgot to check, and the claim becomes
unfalsifiable.

Rebinding never mutates: it builds a new generation. Old proposals, requests and result
bytes stay byte-identical, which is what lets `STALE` be a new record rather than an
edit to an old one. Mixing generations inside one graph is refused, because a partially
rebound graph would dispatch some nodes against inputs the rest no longer agree with.
"""

import copy
import hashlib
import json
import weakref

from foundation import core as foundation_core
from foundation import errors as foundation_errors

from .errors import (
    INVALID_BINDING,
    MIXED_GENERATION,
    TOPOLOGY_CYCLE,
    UNKNOWN_GRAPH_KIND,
    OrchestrationError,
)
from .identity import required_bindings

NODE_KINDS = ("requirement", "repo-task", "artifact", "test")
EDGE_KINDS = ("requires", "depends-on", "binds", "verifies")

# from-kind -> to-kind, per edge kind. An edge between the wrong kinds is as invalid as
# an unknown kind: `verifies` from a requirement to an artifact would type-check as a
# string pair while meaning nothing.
EDGE_ENDPOINTS = {
    "requires": ("repo-task", "requirement"),
    "depends-on": ("repo-task", "repo-task"),
    "binds": ("repo-task", "artifact"),
    "verifies": ("test", "repo-task"),
}

class ValidatedBindings:
    """Opaque, Foundation-resolved bindings for graph construction only."""

    __slots__ = ("__by_repo", "__weakref__")

    def __init__(self, *args, **kwargs):
        raise TypeError("ValidatedBindings instances come from resolution only")

    def _for_repo(self, repo_id):
        return copy.deepcopy(self.__by_repo.get(repo_id, {}))


def _invalid_binding(message):
    raise OrchestrationError(INVALID_BINDING, message)


def _make_binding_boundary():
    issued_bindings = weakref.WeakKeyDictionary()

    def issue(by_repo):
        issued = object.__new__(ValidatedBindings)
        authoritative = copy.deepcopy(by_repo)
        object.__setattr__(
            issued,
            "_ValidatedBindings__by_repo",
            copy.deepcopy(authoritative),
        )
        issued_bindings[issued] = authoritative
        return issued

    def resolve(bindings, foundation_home):
        """Resolve every supplied binding through Foundation exactly once.

        Missing binding names remain absent so the graph can report a recoverable BLOCKED
        state. Supplied values, however, are accepted only after Foundation has verified
        their Artifact Ref authority and content.
        """
        if not isinstance(bindings, dict):
            _invalid_binding("bindings must be a dictionary")

        validated = {}
        for repo_id, supplied in bindings.items():
            if not isinstance(repo_id, str) or not isinstance(supplied, dict):
                _invalid_binding("bindings must map repo IDs to binding dictionaries")
            resolved_for_repo = {}
            for name, artifact_ref in supplied.items():
                if not isinstance(name, str):
                    _invalid_binding("binding names must be strings")
                try:
                    resolution = foundation_core.resolve(foundation_home, artifact_ref)
                    resolved_ref = dict(resolution["artifact_ref"])
                except (foundation_errors.FoundationError, foundation_errors.Unresolvable) as exc:
                    _invalid_binding(
                        "binding %s for %s is invalid: %s"
                        % (name, repo_id, exc)
                    )
                except (KeyError, TypeError, ValueError) as exc:
                    _invalid_binding(
                        "binding %s for %s is invalid: %s"
                        % (name, repo_id, exc)
                    )
                resolved_for_repo[name] = resolved_ref
            validated[repo_id] = resolved_for_repo
        return issue(validated)

    def require(bindings):
        if (
            type(bindings) is not ValidatedBindings
            or bindings not in issued_bindings
        ):
            _invalid_binding(
                "bindings must be resolved with resolve_and_validate_bindings"
            )
        return copy.deepcopy(issued_bindings[bindings])

    return resolve, require


resolve_and_validate_bindings, _require_validated_bindings = _make_binding_boundary()
del _make_binding_boundary


def _canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _digest(obj):
    return hashlib.sha256(_canonical(obj).encode("utf-8")).hexdigest()


def _binding_report_from_snapshot(proposals, bindings):
    entries = []
    for slice_proposal in proposals["slices"]:
        repo_id = slice_proposal["repo_id"]
        present = bindings.get(repo_id, {})
        needed = required_bindings(slice_proposal["workflow_profile"])
        missing = [name for name in needed if name not in present]
        entry = {
            "repo_id": repo_id,
            "required": list(needed),
            "present": sorted(present),
            "missing": missing,
            "state": "BLOCKED" if missing else "CURRENT",
            "recovery_action": (
                "publish committed %s Artifact Ref for %s"
                % (", ".join(missing), repo_id)
                if missing
                else None
            ),
        }
        entries.append(entry)
    return {"slices": entries,
            "dispatchable": all(e["state"] == "CURRENT" for e in entries)}


def binding_report(proposals, bindings):
    """Per-slice current / missing / invalid, each with exactly one recovery action.

    One action, not a menu: the PRD requires a unique recovery action so an operator is
    never asked to choose between repairs whose consequences differ.
    """
    return _binding_report_from_snapshot(
        proposals, _require_validated_bindings(bindings)
    )


def _ready_order(requirement_ids, edges):
    """Deterministic topological order over requirement nodes; ties break by ID."""
    incoming = {rid: 0 for rid in requirement_ids}
    outgoing = {rid: [] for rid in requirement_ids}
    for edge in edges:
        outgoing[edge["from"]].append(edge["to"])
        incoming[edge["to"]] += 1
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
            TOPOLOGY_CYCLE, "requirement topology contains a cycle")
    return order


def build_graph(proposals, bindings, generation):
    """Build one immutable graph generation from proposals plus published bindings.

    A graph is produced even when bindings are incomplete, with `dispatchable` false:
    a missing binding is a recoverable BLOCKED state (PRD FR-002), so it must not
    destroy the slice proposals by refusing to build at all.
    """
    bindings = _require_validated_bindings(bindings)
    nodes = []
    edges = []

    requirement_ids = []
    for slice_proposal in proposals["slices"]:
        requirement_ids.extend(slice_proposal["requirement_ids"])
    requirement_ids = sorted(set(requirement_ids))

    for requirement_id in requirement_ids:
        nodes.append({"id": requirement_id, "kind": "requirement",
                      "generation": generation})

    for slice_proposal in sorted(proposals["slices"], key=lambda s: s["repo_id"]):
        repo_id = slice_proposal["repo_id"]
        task_id = "task:%s" % repo_id
        nodes.append({"id": task_id, "kind": "repo-task", "repo_id": repo_id,
                      "generation": generation})
        for requirement_id in slice_proposal["requirement_ids"]:
            edges.append({"kind": "requires", "from": task_id, "to": requirement_id})
        present = bindings.get(repo_id, {})
        for name in sorted(present):
            ref = present[name]
            artifact_id = "artifact:%s:%s" % (repo_id, name)
            nodes.append({"id": artifact_id, "kind": "artifact", "repo_id": repo_id,
                          "binding": name, "artifact_ref": ref,
                          "generation": generation})
            edges.append({"kind": "binds", "from": task_id, "to": artifact_id})

    # Cross-slice requirement dependencies become task-level ordering.
    owner_of_requirement = {
        requirement_id: s["repo_id"]
        for s in proposals["slices"] for requirement_id in s["requirement_ids"]
    }
    for edge in proposals["topology"]:
        source_repo = owner_of_requirement[edge["from"]]
        target_repo = owner_of_requirement[edge["to"]]
        if source_repo != target_repo:
            edges.append({"kind": "depends-on",
                          "from": "task:%s" % target_repo,
                          "to": "task:%s" % source_repo})

    report = _binding_report_from_snapshot(proposals, bindings)
    graph = {
        "generation": generation,
        "nodes": sorted(nodes, key=lambda n: n["id"]),
        "edges": sorted(edges, key=_canonical),
        "ready_order": _ready_order(requirement_ids, proposals["topology"]),
        "binding_report": report,
        "dispatchable": report["dispatchable"],
    }
    graph["graph_digest"] = _digest(
        {k: graph[k] for k in ("generation", "nodes", "edges")}
    )
    validate_graph(graph)
    return graph


def validate_graph(graph):
    """Reject anything outside the closed grammar, or any generation mixing."""
    generations = {node.get("generation") for node in graph["nodes"]}
    if len(generations) > 1:
        raise OrchestrationError(
            MIXED_GENERATION,
            "graph mixes generations %s; rebind produces a new graph instead"
            % sorted(generations),
        )

    kind_of = {}
    for node in graph["nodes"]:
        if node["kind"] not in NODE_KINDS:
            raise OrchestrationError(
                UNKNOWN_GRAPH_KIND, "unknown node kind %r" % node["kind"])
        kind_of[node["id"]] = node["kind"]

    for edge in graph["edges"]:
        if edge["kind"] not in EDGE_KINDS:
            raise OrchestrationError(
                UNKNOWN_GRAPH_KIND, "unknown edge kind %r" % edge["kind"])
        for endpoint in (edge["from"], edge["to"]):
            if endpoint not in kind_of:
                raise OrchestrationError(
                    UNKNOWN_GRAPH_KIND,
                    "edge %s references unknown node %s" % (edge["kind"], endpoint),
                )
        expected_from, expected_to = EDGE_ENDPOINTS[edge["kind"]]
        if (kind_of[edge["from"]], kind_of[edge["to"]]) != (expected_from, expected_to):
            raise OrchestrationError(
                UNKNOWN_GRAPH_KIND,
                "edge %s must join %s -> %s" % (edge["kind"], expected_from, expected_to),
            )
    return graph
