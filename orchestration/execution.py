"""Advisory execution and deterministic resume (PRD FR-004).

Running a task is the easy half. The hard half is knowing what happened after a crash
without asking a human to remember, so every transition is written down BEFORE its side
effect: the attempt record is opened inside the repo lock and before dispatch, because a
record written afterwards cannot distinguish "never started" from "started, then we
died".

Three states only, and no `VERIFIED` (spec D-O4). A local operator controls the
workspace and the command output, so nothing observed here can be release evidence. A
future trusted milestone must add a versioned provider capability rather than
reinterpret these records.
"""

import hashlib
import json

from .errors import (
    ATTEMPT_IDENTITY_REQUIRED,
    FOREIGN_LOCK,
    GRAPH_NOT_DISPATCHABLE,
    INVALID_RETRY_POLICY,
    UNKNOWN_EVIDENCE_STATE,
    OrchestrationError,
)

EVIDENCE_STATES = ("OBSERVED", "FAILED", "BLOCKED")
OPEN_STATES = ("PREPARED", "DISPATCHED")
# Terminal but not evidence: the attempt was replaced by a reconciliation successor.
SUPERSEDED = "SUPERSEDED"
SELF = "this-coordinator"


def _canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _digest(obj):
    return hashlib.sha256(_canonical(obj).encode("utf-8")).hexdigest()


# Fields that identify an attempt for its whole life. `state`, `exit_code` and
# `superseded_by` are lifecycle and deliberately excluded: digesting them would change
# an attempt's identity every time it advanced, so a receipt could never be matched back
# to the attempt that produced it.
ATTEMPT_IDENTITY_FIELDS = (
    "node_id", "repo_id", "request_digest", "attempt_count", "supersedes",
)


def attempt_identity_digest(attempt):
    return _digest({field: attempt.get(field) for field in ATTEMPT_IDENTITY_FIELDS})


def new_journal():
    """Durable resume state. Plain data so it can be committed and replayed."""
    return {"attempts": [], "locks": {}, "results": {}}


def _node(graph, node_id):
    for node in graph["nodes"]:
        if node["id"] == node_id:
            return node
    raise OrchestrationError(
        UNKNOWN_EVIDENCE_STATE, "node %s is not in this graph" % node_id)


def _max_retries(policy):
    """Return the retry budget without accepting coercible policy values."""
    max_retries = policy.get("max_retries", 0)
    if type(max_retries) is not int or max_retries < 0:
        raise OrchestrationError(
            INVALID_RETRY_POLICY,
            "max_retries must be a non-negative int",
        )
    return max_retries


def execution_request(graph, node_id, policy):
    """An immutable request. Its digest covers graph bindings plus request-local fields.

    The split matters for recovery: a change to a graph-bound digest means the inputs
    moved and the work must be rebound, while a change to a request-local field alone
    can be retried against the same bindings.
    """
    node = _node(graph, node_id)
    max_retries = _max_retries(policy)
    request = {
        "node_id": node_id,
        "repo_id": node.get("repo_id"),
        "generation": graph["generation"],
        "graph_digest": graph["graph_digest"],
        "policy": {"max_retries": max_retries},
    }
    request["request_digest"] = _digest(request)
    return request


def _ready(graph, node_id, journal):
    """A node is ready when every depends-on prerequisite recorded OBSERVED."""
    for edge in graph["edges"]:
        if edge["kind"] == "depends-on" and edge["from"] == node_id:
            if journal["results"].get(edge["to"], {}).get("state") != "OBSERVED":
                return False
    return True


def _open_attempt(journal, node_id):
    """The NEWEST open attempt for a node.

    Newest, not first: reconciliation appends a successor, so returning the earliest
    open record would close a superseded attempt and leave the live one open forever.
    """
    for attempt in reversed(journal["attempts"]):
        if attempt["node_id"] == node_id and attempt["state"] in OPEN_STATES:
            return attempt
    return None


def _attributable_attempt(journal, repo_id):
    """An open attempt on this repo whose recorded digest still matches its identity.

    Digest-valid matters: a record whose digest no longer matches its own identity
    fields has been tampered with or truncated, and must not be used to justify waiting
    on work that may not exist.
    """
    for attempt in reversed(journal["attempts"]):
        if attempt["repo_id"] != repo_id or attempt["state"] not in OPEN_STATES:
            continue
        if attempt.get("attempt_digest") == attempt_identity_digest(attempt):
            return attempt
    return None


def dispatch(graph, node_id, policy, journal):
    """Acquire the repo lock, open the attempt record, then dispatch.

    Refuses rather than waits when another coordinator holds the lock: a deterministic
    BLOCKED is actionable, whereas a silent wait hides a second instance.
    """
    # This is a top-level execution gate.  It intentionally precedes all request,
    # node, lock, and policy work so a stale or partial graph cannot affect a journal.
    if graph.get("dispatchable") is not True:
        return {"state": "BLOCKED", "reason": GRAPH_NOT_DISPATCHABLE}

    _max_retries(policy)
    node = _node(graph, node_id)
    repo_id = node.get("repo_id")

    # The repo execution lock serializes a repo across initiatives, so a foreign holder
    # is not automatically an error -- it may be another initiative legitimately running
    # this repo. PRD FR-004 therefore distinguishes by ATTRIBUTION: a holder that maps to
    # a digest-valid open attempt means real work is in flight and the answer is to wait
    # for it; a holder that maps to nothing is an unattributable lock, which needs
    # releasing rather than waiting on a task that may not exist. Both dispatch nothing.
    holder = journal["locks"].get(repo_id)
    if holder is not None and holder != SELF:
        attributed = _attributable_attempt(journal, repo_id)
        if attributed is not None:
            return {"state": "WAIT_FOR_TASK_COMPLETION", "holder": holder,
                    "attempt_digest": attributed["attempt_digest"]}
        return {"state": "BLOCKED", "reason": FOREIGN_LOCK,
                "action": "WAIT_FOR_LOCK_RELEASE", "holder": holder}

    if not _ready(graph, node_id, journal):
        return {"state": "BLOCKED", "reason": "PREREQUISITE_NOT_OBSERVED"}

    existing = _open_attempt(journal, node_id)
    if existing is not None:
        # Already in flight. Redispatching here is the double-dispatch window.
        return {"state": "WAIT_FOR_TASK_COMPLETION",
                "attempt_digest": existing["attempt_digest"]}

    request = execution_request(graph, node_id, policy)
    prior = [a for a in journal["attempts"] if a["node_id"] == node_id]
    attempt = {
        "node_id": node_id,
        "repo_id": repo_id,
        "request_digest": request["request_digest"],
        "attempt_count": len(prior) + 1,
        "state": "PREPARED",
        "supersedes": None,
    }
    attempt["attempt_digest"] = attempt_identity_digest(attempt)
    # Lock first, then record, then dispatch: the record must exist before any effect.
    journal["locks"][repo_id] = SELF
    journal["attempts"].append(attempt)
    attempt["state"] = "DISPATCHED"
    return {"state": "DISPATCHED", "request": request,
            "attempt_digest": attempt["attempt_digest"]}


def record_result(journal, attempt_digest, state, exit_code=None):
    """Close the exact open attempt identified by its immutable digest."""
    attempt = next(
        (
            candidate
            for candidate in journal["attempts"]
            if candidate.get("attempt_digest") == attempt_digest
            and attempt_identity_digest(candidate) == attempt_digest
            and candidate.get("state") in OPEN_STATES
        ),
        None,
    )
    if attempt is None:
        raise OrchestrationError(
            ATTEMPT_IDENTITY_REQUIRED,
            "an exact open attempt digest is required",
        )
    if state not in EVIDENCE_STATES:
        raise OrchestrationError(
            UNKNOWN_EVIDENCE_STATE,
            "%r is not a V1 evidence state; allowed: %s" % (state, EVIDENCE_STATES),
        )
    attempt["state"] = state
    attempt["exit_code"] = exit_code
    node_id = attempt["node_id"]
    journal["results"][node_id] = {"state": state, "exit_code": exit_code,
                                   "attempt_digest": attempt["attempt_digest"]}
    journal["locks"].pop(attempt["repo_id"], None)
    return journal["results"][node_id]


def recovery_action(journal, node_id, policy):
    """One deterministic action per target.

    Retrying the same request is only correct while the graph bindings are unchanged and
    the retry budget allows it; otherwise the caller must rebind or reconcile rather than
    resend identical bytes.
    """
    max_retries = _max_retries(policy)
    attempts = [a for a in journal["attempts"] if a["node_id"] == node_id]
    result = journal["results"].get(node_id)
    if result is None:
        return {"action": "RECONCILE_INTERRUPTED_ATTEMPT", "node_id": node_id}
    if result["state"] == "OBSERVED":
        return {"action": None, "node_id": node_id}
    if result["state"] == "FAILED":
        if len(attempts) <= max_retries:
            return {"action": "RETRY_SAME_REQUEST", "node_id": node_id}
        return {"action": "REPORT_FAILED", "node_id": node_id}
    return {"action": "RESOLVE_BLOCKER", "node_id": node_id}


def resume(journal):
    """Rebuild what to do next from durable state alone.

    An attempt still holding its lock means a runner may be alive, so resume waits
    instead of redispatching. An open attempt whose lock is gone is the crash case: no
    terminal result was ever written, and only an operator can say what happened.
    """
    open_attempts = [a for a in journal["attempts"] if a["state"] in OPEN_STATES]
    live = [a for a in open_attempts if journal["locks"].get(a["repo_id"]) == SELF]
    orphaned = [a for a in open_attempts if a not in live]

    if live:
        return {"next_action": "WAIT_FOR_TASK_COMPLETION",
                "current_operations": [a["attempt_digest"] for a in live],
                "redispatch": []}
    if orphaned:
        return {"next_action": "RECONCILE_INTERRUPTED_ATTEMPT",
                "current_operations": [a["attempt_digest"] for a in orphaned],
                "redispatch": []}
    return {"next_action": None, "current_operations": [], "redispatch": []}


def reconcile(journal, node_id, operator_decision):
    """Close an interrupted attempt by superseding it, never by editing it.

    The old attempt bytes are immutable, so the audit trail keeps both the interrupted
    attempt and the operator's decision. Reconciliation creates exactly one new request.
    """
    attempt = _open_attempt(journal, node_id)
    if attempt is None:
        raise OrchestrationError(
            UNKNOWN_EVIDENCE_STATE, "no interrupted attempt for %s" % node_id)
    successor = {
        "node_id": node_id,
        "repo_id": attempt["repo_id"],
        "request_digest": attempt["request_digest"],
        "attempt_count": attempt["attempt_count"] + 1,
        "state": "PREPARED",
        "supersedes": attempt["attempt_digest"],
        "operator_decision": operator_decision,
    }
    successor["attempt_digest"] = attempt_identity_digest(successor)
    journal["attempts"].append(successor)
    # Close the interrupted attempt. Leaving it open made the journal diverge: every
    # reconciliation added a "current operation" that nothing could ever close, so
    # resume kept demanding reconciliation even after a terminal result existed.
    # Closing it is not editing its evidence -- it never had any; the operator's
    # decision and the supersedes link are recorded on the successor.
    attempt["state"] = SUPERSEDED
    attempt["superseded_by"] = successor["attempt_digest"]
    return {"action": "CREATE_NEW_REQUEST",
            "attempt_digest": successor["attempt_digest"],
            "superseded_attempt_digest": attempt["attempt_digest"]}
