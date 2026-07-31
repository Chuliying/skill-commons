"""Orchestration Slice C: advisory execution and deterministic resume (FR-004).

Covers qa-plan TC-007/008/010/018/019/021/023/024/025/026.

The hard part is not running a task, it is knowing what happened after a crash without
asking a human to remember. So the state machine is deliberately small and every
transition is written down before the side effect, not after: an attempt record is
opened inside the lock BEFORE dispatch, because a record written afterwards cannot
distinguish "never started" from "started and we crashed".
"""

import unittest

from orchestration import errors, execution


def _graph():
    return {
        "generation": 1,
        "graph_digest": "g" * 64,
        "nodes": [
            {"id": "task:repoA", "kind": "repo-task", "repo_id": "repoA", "generation": 1},
            {"id": "task:repoB", "kind": "repo-task", "repo_id": "repoB", "generation": 1},
        ],
        "edges": [{"kind": "depends-on", "from": "task:repoB", "to": "task:repoA"}],
        "dispatchable": True,
    }


class RequestIdentity(unittest.TestCase):
    def test_request_binds_graph_and_policy_digests(self):
        request = execution.execution_request(_graph(), "task:repoA", {"max_retries": 1})
        self.assertEqual(request["graph_digest"], "g" * 64)
        self.assertEqual(request["generation"], 1)
        self.assertEqual(request["policy"]["max_retries"], 1)
        self.assertIn("request_digest", request)

    def test_request_is_deterministic(self):
        first = execution.execution_request(_graph(), "task:repoA", {"max_retries": 1})
        second = execution.execution_request(_graph(), "task:repoA", {"max_retries": 1})
        self.assertEqual(first, second)

    def test_tc018_unready_node_is_blocked_without_execution(self):
        # repoB depends on repoA, which has produced no evidence yet.
        journal = execution.new_journal()
        result = execution.dispatch(_graph(), "task:repoB", {"max_retries": 1}, journal)
        self.assertEqual(result["state"], "BLOCKED")
        self.assertEqual(journal["attempts"], [])

    def test_unknown_node_is_refused(self):
        with self.assertRaises(errors.OrchestrationError):
            execution.execution_request(_graph(), "task:nope", {"max_retries": 1})


class LockAndDispatch(unittest.TestCase):
    def setUp(self):
        self.graph = _graph()
        self.journal = execution.new_journal()

    def test_tc024_interrupted_dispatch_never_double_starts_the_command(self):
        """PRD AC-024: inject a fault at each dispatch boundary, resume, and assert the
        command can never be started twice.

        The previous test only checked that an attempt exists after a SUCCESSFUL
        dispatch, which says nothing about the interrupted cases the AC is about. Each
        boundary is reconstructed as the durable state a crash there would leave.
        """
        # THREE durable states, not four. The PRD names four injection points, but V1's
        # journal has no RUNNING state, so "runner spawned" and "acknowledgement lost"
        # leave byte-identical durable state and cannot be distinguished by resume. An
        # earlier version of this test carried a four-key dict of `None` placeholders to
        # look like four cases; that was decoration around the real assertions, so it is
        # gone. What is asserted below is the property itself, at every state the model
        # can actually represent.

        # State 1: lock taken, nothing recorded -- the command never ran, so dispatch
        # legitimately starts it exactly once.
        journal = execution.new_journal()
        journal["locks"]["repoA"] = execution.SELF
        first = execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, journal)
        self.assertEqual(first["state"], "DISPATCHED")
        self.assertEqual(len(journal["attempts"]), 1)

        # States 2-3: an open attempt exists with the lock held (PREPARED = pre-command,
        # DISPATCHED = command may be live). Resume must wait, and a redispatch must not
        # create a second attempt or a second request.
        for state in ("PREPARED", "DISPATCHED"):
            journal = execution.new_journal()
            execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, journal)
            journal["attempts"][0]["state"] = state
            original_request = journal["attempts"][0]["request_digest"]

            plan = execution.resume(journal)
            self.assertEqual(plan["next_action"], "WAIT_FOR_TASK_COMPLETION", state)
            self.assertEqual(plan["redispatch"], [], state)

            again = execution.dispatch(self.graph, "task:repoA", {"max_retries": 1},
                                       journal)
            self.assertEqual(again["state"], "WAIT_FOR_TASK_COMPLETION", state)
            self.assertEqual(len(journal["attempts"]), 1, state)
            # Resuming a pre-command PREPARED attempt reuses the SAME request.
            self.assertEqual(journal["attempts"][0]["request_digest"],
                             original_request, state)

    def test_tc024_attempt_is_opened_before_dispatch(self):
        result = execution.dispatch(self.graph, "task:repoA", {"max_retries": 1},
                                    self.journal)
        self.assertEqual(result["state"], "DISPATCHED")
        # The record exists and is PREPARED-then-DISPATCHED, never dispatched-only.
        attempt = self.journal["attempts"][0]
        self.assertEqual(attempt["node_id"], "task:repoA")
        self.assertIn(attempt["state"], ("PREPARED", "DISPATCHED"))
        self.assertEqual(attempt["attempt_count"], 1)

    def test_tc025_unattributable_foreign_lock_yields_wait_for_lock_release(self):
        """PRD FR-004: a holder that maps to no valid attempt needs the LOCK released,
        not a task waited on -- the task may not exist."""
        journal = execution.new_journal()
        journal["locks"]["repoA"] = "another-coordinator"
        result = execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, journal)
        self.assertEqual(result["state"], "BLOCKED")
        self.assertEqual(result["reason"], errors.FOREIGN_LOCK)
        self.assertEqual(result["action"], "WAIT_FOR_LOCK_RELEASE")
        self.assertEqual(journal["attempts"], [])

    def test_tc025_attributable_foreign_lock_yields_wait_for_task_completion(self):
        """A foreign holder backed by a digest-valid open attempt is another initiative
        legitimately running this repo, so the answer is to wait for that task."""
        journal = execution.new_journal()
        execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, journal)
        journal["locks"]["repoA"] = "another-coordinator"   # ownership handed over
        result = execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, journal)
        self.assertEqual(result["state"], "WAIT_FOR_TASK_COMPLETION")
        self.assertEqual(result["holder"], "another-coordinator")
        self.assertEqual(len(journal["attempts"]), 1)       # zero dispatch

    def test_a_tampered_attempt_digest_is_not_attributable(self):
        journal = execution.new_journal()
        execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, journal)
        journal["attempts"][0]["attempt_digest"] = "0" * 64   # forged
        journal["locks"]["repoA"] = "another-coordinator"
        result = execution.dispatch(self.graph, "task:repoB", {"max_retries": 1}, journal)
        # repoB is blocked by its prerequisite, but the point is repoA is unattributable.
        self.assertIsNone(execution._attributable_attempt(journal, "repoA"))

    def test_tc019_second_coordinator_instance_is_refused_while_lock_is_held(self):
        execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, self.journal)
        again = execution.dispatch(self.graph, "task:repoA", {"max_retries": 1},
                                   self.journal)
        self.assertEqual(again["state"], "WAIT_FOR_TASK_COMPLETION")
        # No second attempt record: that would be a double dispatch.
        self.assertEqual(len(self.journal["attempts"]), 1)


class EvidenceAndRecovery(unittest.TestCase):
    def setUp(self):
        self.graph = _graph()
        self.journal = execution.new_journal()
        dispatched = execution.dispatch(
            self.graph, "task:repoA", {"max_retries": 1}, self.journal
        )
        self.attempt_digest = dispatched["attempt_digest"]

    def test_tc007_observed_result_closes_the_attempt_and_releases_the_lock(self):
        execution.record_result(
            self.journal, self.attempt_digest, "OBSERVED", exit_code=0
        )
        attempt = self.journal["attempts"][0]
        self.assertEqual(attempt["state"], "OBSERVED")
        self.assertNotIn("repoA", self.journal["locks"])
        # V1 has no VERIFIED state at all.
        self.assertNotIn("VERIFIED", execution.EVIDENCE_STATES)

    def test_tc008_failure_within_retry_budget_retries_the_same_request(self):
        execution.record_result(
            self.journal, self.attempt_digest, "FAILED", exit_code=1
        )
        action = execution.recovery_action(self.journal, "task:repoA",
                                          {"max_retries": 1})
        self.assertEqual(action["action"], "RETRY_SAME_REQUEST")

    def test_failure_beyond_retry_budget_stops_retrying(self):
        execution.record_result(
            self.journal, self.attempt_digest, "FAILED", exit_code=1
        )
        action = execution.recovery_action(self.journal, "task:repoA",
                                          {"max_retries": 0})
        self.assertNotEqual(action["action"], "RETRY_SAME_REQUEST")

    def test_tc011_a_forged_trusted_field_cannot_escalate_evidence(self):
        with self.assertRaises(errors.OrchestrationError) as caught:
            execution.record_result(
                self.journal, self.attempt_digest, "VERIFIED", exit_code=0
            )
        self.assertEqual(caught.exception.code, errors.UNKNOWN_EVIDENCE_STATE)


class CrashResume(unittest.TestCase):
    def setUp(self):
        self.graph = _graph()
        self.journal = execution.new_journal()

    def _record_latest(self, state, exit_code):
        execution.record_result(
            self.journal,
            self.journal["attempts"][-1]["attempt_digest"],
            state,
            exit_code=exit_code,
        )

    def test_tc021_resume_does_not_redispatch_a_live_runner(self):
        execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, self.journal)
        plan = execution.resume(self.journal)
        self.assertEqual(plan["next_action"], "WAIT_FOR_TASK_COMPLETION")
        self.assertEqual(plan["redispatch"], [])

    def test_tc010_resume_keeps_exactly_one_current_operation(self):
        execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, self.journal)
        plan = execution.resume(self.journal)
        self.assertEqual(len(plan["current_operations"]), 1)

    def test_tc023_interrupted_runner_without_result_requires_reconciliation(self):
        execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, self.journal)
        # The lock is gone (process died) but no terminal result was ever written.
        del self.journal["locks"]["repoA"]
        plan = execution.resume(self.journal)
        self.assertEqual(plan["next_action"], "RECONCILE_INTERRUPTED_ATTEMPT")

    def test_tc026_reconciliation_creates_only_a_new_request(self):
        execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, self.journal)
        del self.journal["locks"]["repoA"]
        before = dict(self.journal["attempts"][0])
        outcome = execution.reconcile(self.journal, "task:repoA",
                                      operator_decision="abandon")
        # Identity is immutable; lifecycle state is not, and must not be. An attempt is
        # a state-machine record -- record_result already advances it. What may never
        # change is what the attempt IS, so the digest covers identity only and the
        # earlier `assertEqual(whole_dict)` was asserting more than the contract.
        after = self.journal["attempts"][0]
        for field in execution.ATTEMPT_IDENTITY_FIELDS:
            self.assertEqual(after[field], before[field], field)
        self.assertEqual(after["attempt_digest"], before["attempt_digest"])
        self.assertEqual(execution.attempt_identity_digest(after),
                         after["attempt_digest"])
        self.assertEqual(outcome["action"], "CREATE_NEW_REQUEST")
        self.assertEqual(len(self.journal["attempts"]), 2)
        self.assertEqual(self.journal["attempts"][1]["supersedes"],
                         before["attempt_digest"])

    def test_reconcile_converges_and_does_not_accumulate_operations(self):
        """Regression: reconcile used to leave the interrupted attempt open forever.

        Each reconciliation then added a 'current operation' nothing could close, so
        resume demanded reconciliation even after a terminal result existed.
        """
        execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, self.journal)
        del self.journal["locks"]["repoA"]
        for _ in range(3):
            execution.reconcile(self.journal, "task:repoA", operator_decision="abandon")
            self.assertEqual(len(execution.resume(self.journal)["current_operations"]), 1)
        # A terminal result closes the newest attempt and the journal converges.
        self._record_latest("OBSERVED", 0)
        plan = execution.resume(self.journal)
        self.assertIsNone(plan["next_action"])
        self.assertEqual(plan["current_operations"], [])

    def test_superseded_attempts_are_closed_and_linked(self):
        execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, self.journal)
        del self.journal["locks"]["repoA"]
        outcome = execution.reconcile(self.journal, "task:repoA",
                                      operator_decision="abandon")
        old = self.journal["attempts"][0]
        self.assertEqual(old["state"], execution.SUPERSEDED)
        self.assertEqual(old["superseded_by"], outcome["attempt_digest"])
        # The evidence contract is untouched: a superseded attempt never had a result.
        self.assertNotIn("task:repoA", self.journal["results"])

    def test_resume_of_a_finished_journal_has_nothing_to_do(self):
        execution.dispatch(self.graph, "task:repoA", {"max_retries": 1}, self.journal)
        self._record_latest("OBSERVED", 0)
        plan = execution.resume(self.journal)
        self.assertIsNone(plan["next_action"])
        self.assertEqual(plan["current_operations"], [])


if __name__ == "__main__":
    unittest.main()
