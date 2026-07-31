"""Orchestration consumer integration on Foundation (program T04/T06).

What this covers is the consumer boundary, not the orchestration runtime: taking an
InitiativeScope from either source, binding its requirements to Foundation-resolvable
artifacts, and refusing anything it cannot verify. The execution engine (dispatch,
attempts, recovery) is a later phase and is not exercised here.

The point of the boundary is that orchestration owns no identity of its own. It does
not decide what an Artifact Ref is, nor whether one resolves -- Foundation answers
both, and a consumer that re-implemented either would drift from it silently.
"""

import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import core, home
from orchestration import consumer, errors
from productscope import contracts


def _make_repo(prefix):
    work = tempfile.mkdtemp(prefix=prefix)
    subprocess.run(["git", "init", "-q", work], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for key, value in (("user.name", "t"), ("user.email", "t@e")):
        subprocess.run(["git", "-C", work, "config", key, value], check=True)
    return work


def _commit_file(work, rel, content):
    import hashlib

    path = os.path.join(work, rel)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True)
    subprocess.run(["git", "-C", work, "commit", "-qm", "add"], check=True)
    oid = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"],
                         stdout=subprocess.PIPE, check=True).stdout.decode().strip()
    return oid, hashlib.sha256(content.encode("utf-8")).hexdigest()


class ConsumerBase(unittest.TestCase):
    def setUp(self):
        self.home_work = _make_repo("orch-home-")
        self.foundation = os.path.join(self.home_work, ".git")
        self.repo_work = _make_repo("orch-repo-")
        self.repo_git = os.path.join(self.repo_work, ".git")
        for path in (self.home_work, self.repo_work):
            self.addCleanup(shutil.rmtree, path, ignore_errors=True)
        core.register(self.foundation, "repoA", self.repo_git, home.read_head(self.foundation))

    def _publish(self, rel, content, kind="prd"):
        oid, digest = _commit_file(self.repo_work, rel, content)
        ref = {"repo_id": "repoA", "commit_oid": oid, "path": rel,
               "digest": digest, "artifact_kind": kind}
        core.publish(self.foundation, "repoA/home", ref, [], home.read_head(self.foundation))
        return ref

    def _unpublished(self, rel, content, kind="prd"):
        oid, digest = _commit_file(self.repo_work, rel, content)
        return {"repo_id": "repoA", "commit_oid": oid, "path": rel,
                "digest": digest, "artifact_kind": kind}

    def _scope(self, refs, source_kind="accepted-scope-delta", topology=None):
        return contracts.validate_initiative_scope({
            "initiative_scope_id": "is-1",
            "source_kind": source_kind,
            "product_id": "prod",
            "scope_revision": "c" * 40,
            "requirements": [
                {"requirement_id": "R%d" % i, "version": "1",
                 "content_artifact_ref": ref, "digest": ref["digest"]}
                for i, ref in enumerate(refs, start=1)
            ],
            "requirement_topology": topology or [],
            "scope_digest": "f" * 64,
        })


class AcceptsBothSourceKinds(ConsumerBase):
    def test_accepted_scope_delta_binds_every_requirement(self):
        scope = self._scope([self._publish("r1.md", "one"), self._publish("r2.md", "two")])
        bound = consumer.bind_initiative_scope(self.foundation, scope)
        self.assertEqual([b["requirement_id"] for b in bound["bindings"]], ["R1", "R2"])
        self.assertEqual(bound["source_kind"], "accepted-scope-delta")
        self.assertTrue(all(b["resolved"] for b in bound["bindings"]))

    def test_manual_initiative_scope_is_accepted_unchanged(self):
        scope = self._scope([self._publish("r1.md", "one")],
                            source_kind="manual-initiative-scope")
        bound = consumer.bind_initiative_scope(self.foundation, scope)
        self.assertEqual(bound["source_kind"], "manual-initiative-scope")
        self.assertEqual(len(bound["bindings"]), 1)

    def test_binding_is_deterministic_for_the_same_scope(self):
        scope = self._scope([self._publish("r1.md", "one"), self._publish("r2.md", "two")])
        first = consumer.bind_initiative_scope(self.foundation, scope)
        second = consumer.bind_initiative_scope(self.foundation, scope)
        self.assertEqual(first, second)


class RefusesWhatItCannotVerify(ConsumerBase):
    def test_unresolvable_requirement_fails_closed(self):
        scope = self._scope([self._unpublished("ghost.md", "nope")])
        with self.assertRaises(errors.OrchestrationError) as caught:
            consumer.bind_initiative_scope(self.foundation, scope)
        self.assertEqual(caught.exception.code, errors.UNBINDABLE_REQUIREMENT)

    def test_partial_resolvability_does_not_yield_a_partial_binding(self):
        good = self._publish("r1.md", "one")
        bad = self._unpublished("r2.md", "two")
        scope = self._scope([good, bad])
        with self.assertRaises(errors.OrchestrationError):
            consumer.bind_initiative_scope(self.foundation, scope)

    def test_topology_endpoint_outside_the_scope_is_rejected(self):
        scope = self._scope([self._publish("r1.md", "one")],
                            topology=[{"from": "R1", "to": "R404"}])
        with self.assertRaises(errors.OrchestrationError) as caught:
            consumer.bind_initiative_scope(self.foundation, scope)
        self.assertEqual(caught.exception.code, errors.UNKNOWN_TOPOLOGY_ENDPOINT)

    def test_topology_cycle_is_rejected(self):
        scope = self._scope(
            [self._publish("r1.md", "one"), self._publish("r2.md", "two")],
            topology=[{"from": "R1", "to": "R2"}, {"from": "R2", "to": "R1"}],
        )
        with self.assertRaises(errors.OrchestrationError) as caught:
            consumer.bind_initiative_scope(self.foundation, scope)
        self.assertEqual(caught.exception.code, errors.TOPOLOGY_CYCLE)


class OwnsNoIdentityOfItsOwn(ConsumerBase):
    def test_consumer_does_not_define_artifact_ref_shape(self):
        """A malformed ref must be refused by Foundation's validator, not a local copy."""
        scope_dict = {
            "initiative_scope_id": "is-1",
            "source_kind": "manual-initiative-scope",
            "product_id": "prod",
            "scope_revision": "c" * 40,
            "requirements": [{
                "requirement_id": "R1", "version": "1",
                "content_artifact_ref": {"repo_id": "repoA", "commit_oid": "zz",
                                         "path": "r.md", "digest": "b" * 64,
                                         "artifact_kind": "prd"},
                "digest": "b" * 64,
            }],
            "requirement_topology": [],
            "scope_digest": "f" * 64,
        }
        with self.assertRaises(Exception):
            contracts.validate_initiative_scope(scope_dict)

    def test_execution_order_follows_declared_topology(self):
        r1 = self._publish("r1.md", "one")
        r2 = self._publish("r2.md", "two")
        scope = self._scope([r1, r2], topology=[{"from": "R1", "to": "R2"}])
        bound = consumer.bind_initiative_scope(self.foundation, scope)
        self.assertEqual(bound["ready_order"], ["R1", "R2"])


if __name__ == "__main__":
    unittest.main()
