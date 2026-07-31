"""Program T06 runtime convergence: both Track 4 consumers over one Foundation.

The contract convergence check (tests/test_protocol_registry.sh) proves the two PRDs
name the same integration contract. This proves the code does: Product Scope activates
a delta and projects an InitiativeScope, Orchestration consumes exactly that object and
binds it, and neither reaches into the other's state.

What makes this worth running rather than asserting on paper: the two packages were
written against the same words but never against each other. A shape agreement on a
page survives a field rename; this does not.
"""

import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import core, home
from orchestration import consumer, errors as orch_errors
from productscope import activation, contracts


def _make_repo(prefix):
    work = tempfile.mkdtemp(prefix=prefix)
    subprocess.run(["git", "init", "-q", work], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for key, value in (("user.name", "t"), ("user.email", "t@e")):
        subprocess.run(["git", "-C", work, "config", key, value], check=True)
    return work


def _commit_file(work, rel, content):
    import hashlib

    with open(os.path.join(work, rel), "w", encoding="utf-8") as handle:
        handle.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True)
    subprocess.run(["git", "-C", work, "commit", "-qm", "add"], check=True)
    oid = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"],
                         stdout=subprocess.PIPE, check=True).stdout.decode().strip()
    return oid, hashlib.sha256(content.encode("utf-8")).hexdigest()


class ConsumerConvergence(unittest.TestCase):
    def setUp(self):
        self.home_work = _make_repo("cv-home-")
        self.foundation = os.path.join(self.home_work, ".git")
        self.repo_work = _make_repo("cv-repo-")
        self.repo_git = os.path.join(self.repo_work, ".git")
        self.scope_work = _make_repo("cv-scope-")
        self.scope_git = os.path.join(self.scope_work, ".git")
        for path in (self.home_work, self.repo_work, self.scope_work):
            self.addCleanup(shutil.rmtree, path, ignore_errors=True)
        core.register(self.foundation, "repoA", self.repo_git, home.read_head(self.foundation))

    def _publish(self, rel, content, kind="prd"):
        oid, digest = _commit_file(self.repo_work, rel, content)
        ref = {"repo_id": "repoA", "commit_oid": oid, "path": rel,
               "digest": digest, "artifact_kind": kind}
        core.publish(self.foundation, "repoA/home", ref, [], home.read_head(self.foundation))
        return ref

    def _project(self, revision, requirement_refs, topology=None):
        """Product Scope's owner-explicit projection (ADR-004, PRD FR-007)."""
        return contracts.validate_initiative_scope({
            "initiative_scope_id": "is-conv-1",
            "source_kind": "accepted-scope-delta",
            "product_id": "prod",
            "scope_revision": revision,
            "requirements": [
                {"requirement_id": rid, "version": "1",
                 "content_artifact_ref": ref, "digest": ref["digest"]}
                for rid, ref in requirement_refs
            ],
            "requirement_topology": topology or [],
            "scope_digest": "f" * 64,
        })

    def test_projection_from_an_activated_delta_is_consumable_end_to_end(self):
        # Product Scope: publish a delta candidate, then activate it into a revision.
        delta_ref = self._publish("delta-1.json", '{"delta":1}', "accepted-scope-delta")
        activated = activation.activate(self.scope_git, self.foundation, delta_ref, None)
        revision = activated["scope_revision"]

        # Product Scope: owner projects a bounded InitiativeScope from that revision.
        r1 = self._publish("req-1.md", "requirement one")
        r2 = self._publish("req-2.md", "requirement two")
        scope = self._project(revision, [("R1", r1), ("R2", r2)],
                              topology=[{"from": "R1", "to": "R2"}])

        # Orchestration: consume exactly that object.
        bound = consumer.bind_initiative_scope(self.foundation, scope)

        self.assertEqual(bound["source_kind"], "accepted-scope-delta")
        self.assertEqual(bound["ready_order"], ["R1", "R2"])
        self.assertTrue(all(b["resolved"] for b in bound["bindings"]))
        # The projection carries the revision it came from, so a consumed scope is
        # traceable back to the product state that produced it.
        self.assertEqual(scope["scope_revision"], revision)

    def test_manual_scope_needs_no_product_scope_state(self):
        """Compatibility path: cross-repo runs without Product Scope installed."""
        r1 = self._publish("req-1.md", "requirement one")
        scope = contracts.validate_initiative_scope({
            "initiative_scope_id": "is-manual-1",
            "source_kind": "manual-initiative-scope",
            "product_id": "prod",
            "scope_revision": "c" * 40,
            "requirements": [{"requirement_id": "R1", "version": "1",
                              "content_artifact_ref": r1, "digest": r1["digest"]}],
            "requirement_topology": [],
            "scope_digest": "f" * 64,
        })
        bound = consumer.bind_initiative_scope(self.foundation, scope)
        self.assertEqual(bound["source_kind"], "manual-initiative-scope")
        # No Product Scope revision was created for this path.
        self.assertIsNone(activation.head(self.scope_git))

    def test_orchestration_refuses_a_projection_referencing_unpublished_work(self):
        """The consumer boundary holds even when the producer hands it something bad."""
        oid, digest = _commit_file(self.repo_work, "ghost.md", "never published")
        ghost = {"repo_id": "repoA", "commit_oid": oid, "path": "ghost.md",
                 "digest": digest, "artifact_kind": "prd"}
        scope = self._project("c" * 40, [("R1", ghost)])
        with self.assertRaises(orch_errors.OrchestrationError) as caught:
            consumer.bind_initiative_scope(self.foundation, scope)
        self.assertEqual(caught.exception.code, orch_errors.UNBINDABLE_REQUIREMENT)

    def test_neither_consumer_writes_into_the_other(self):
        delta_ref = self._publish("delta-1.json", '{"delta":1}', "accepted-scope-delta")
        activation.activate(self.scope_git, self.foundation, delta_ref, None)
        scope_head_before = activation.head(self.scope_git)

        r1 = self._publish("req-1.md", "requirement one")
        scope = self._project(scope_head_before, [("R1", r1)])
        consumer.bind_initiative_scope(self.foundation, scope)

        # Orchestration consuming a scope must not advance Product Scope's revision.
        self.assertEqual(activation.head(self.scope_git), scope_head_before)


if __name__ == "__main__":
    unittest.main()
