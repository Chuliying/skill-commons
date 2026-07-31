"""S5+S6 — core register/publish/resolve/query (spec FR-002..007, AC-002..011).

The TCB tying home + schema + gitobj + graph together. Real temp git repos are
the independent oracle. Covers registration contract, publish fail-closed +
Home CAS + envelope idempotency + PUBLICATION_CONFLICT, digest-verified resolve
+ typed unresolvable, and edge/status-only query (authority isolation).
"""

import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import core, errors, home, schema


def _make_git(prefix):
    d = tempfile.mkdtemp(prefix=prefix)
    subprocess.run(["git", "-C", d, "init", "-q"], check=True, capture_output=True)
    subprocess.run(["git", "-C", d, "config", "user.email", "t@e"], check=True, capture_output=True)
    subprocess.run(["git", "-C", d, "config", "user.name", "t"], check=True, capture_output=True)
    return d, os.path.join(d, ".git")


def _commit(work, rel, content):
    path = os.path.join(work, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True) if os.path.dirname(rel) else None
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True, capture_output=True)
    subprocess.run(["git", "-C", work, "commit", "-q", "-m", "x"], check=True, capture_output=True)
    oid = subprocess.run(
        ["git", "-C", work, "rev-parse", "HEAD"], check=True, capture_output=True, text=True
    ).stdout.strip()
    return oid, hashlib.sha256(content.encode()).hexdigest()


CID = "home/collection"


class CoreTest(unittest.TestCase):
    def setUp(self):
        self.hw, self.home = _make_git("fdn-core-home-")
        self.aw, self.a_git = _make_git("fdn-core-repoA-")
        self.addCleanup(shutil.rmtree, self.hw, ignore_errors=True)
        self.addCleanup(shutil.rmtree, self.aw, ignore_errors=True)

    def _ref(self, oid, digest, path="a.md", kind="prd", repo="repoA"):
        return {"repo_id": repo, "commit_oid": oid, "path": path, "digest": digest, "artifact_kind": kind}

    def _register_a(self):
        return core.register(self.home, "repoA", self.a_git, home.read_head(self.home))

    # ---- registration ----
    def test_register_then_publish(self):
        self._register_a()
        oid, dg = _commit(self.aw, "a.md", "prd body\n")
        rev = home.read_head(self.home)
        res = core.publish(self.home, CID, self._ref(oid, dg), [], rev)
        self.assertFalse(res["replay"])
        self.assertEqual(home.read_head(self.home), res["resulting_home_revision"])

    def test_register_idempotent_noop(self):
        h1 = self._register_a()
        h2 = core.register(self.home, "repoA", self.a_git, home.read_head(self.home))
        self.assertEqual(h1, h2)  # no new commit

    def test_register_conflict_diff_locator(self):
        self._register_a()
        with self.assertRaises(errors.FoundationError) as ctx:
            core.register(self.home, "repoA", "/other/git", home.read_head(self.home))
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_register_trailing_newline_repo_id_schema_error(self):
        # A trailing-newline repo_id must fail closed at validation (SCHEMA_ERROR,
        # fullmatch not match) — not leak past into a git-parser HOME_ERROR.
        with self.assertRaises(errors.FoundationError) as ctx:
            core.register(self.home, "repoA\n", self.a_git, home.read_head(self.home))
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_register_idempotent_returns_current_revision(self):
        # #9: idempotent no-op must return the CURRENT home revision, not the caller's
        # stale expected one.
        h1 = self._register_a()
        core.register(self.home, "repoB", "/other/loc.git", h1)   # advance home
        h2 = home.read_head(self.home)
        self.assertNotEqual(h1, h2)
        self.assertEqual(core.register(self.home, "repoA", self.a_git, h1), h2)

    def test_resolve_unresolvable_carries_offending_ref(self):
        # #10c: a typed unresolvable fact must carry the offending Ref, even when the
        # failure originates in gitobj (e.g. the source repo/locator disappears).
        self._register_a()
        oid, dg = _commit(self.aw, "a.md", "x\n")
        ref = self._ref(oid, dg)
        core.publish(self.home, CID, ref, [], home.read_head(self.home))
        shutil.rmtree(self.aw, ignore_errors=True)                # locator disappears
        with self.assertRaises(errors.Unresolvable) as ctx:
            core.resolve(self.home, ref)
        self.assertIsNotNone(ctx.exception.artifact_ref)
        self.assertEqual(ctx.exception.artifact_ref["path"], "a.md")

    # ---- publish validation ----
    def test_publish_rejects_arbitrary_collection_identity(self):
        self._register_a()
        oid, dg = _commit(self.aw, "a.md", "x\n")
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(
                self.home,
                "caller-chosen",
                self._ref(oid, dg),
                [],
                home.read_head(self.home),
            )
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_publish_canonical_poison_is_not_a_valid_replay(self):
        ghost = self._ref("a" * 40, "b" * 64, repo="ghost")
        envelope = schema.publication_envelope(CID, ghost, [])
        digest = schema.envelope_digest(CID, ghost, [])
        home.commit_entries(
            self.home,
            home.read_head(self.home),
            {f"envelope-{digest}.json": schema.canonical_json(envelope).encode()},
        )
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(self.home, CID, ghost, [], home.read_head(self.home))
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_publish_unregistered_repo_fails(self):
        oid, dg = _commit(self.aw, "a.md", "x\n")
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(self.home, CID, self._ref(oid, dg), [], home.read_head(self.home))
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_publish_object_missing_in_git(self):
        self._register_a()
        with self.assertRaises(errors.Unresolvable) as ctx:
            core.publish(self.home, CID, self._ref("f" * 40, "d" * 64), [], home.read_head(self.home))
        self.assertEqual(ctx.exception.reason, "object-missing")

    def test_publish_digest_mismatch(self):
        self._register_a()
        oid, _dg = _commit(self.aw, "a.md", "x\n")
        with self.assertRaises(errors.Unresolvable) as ctx:
            core.publish(self.home, CID, self._ref(oid, "0" * 64), [], home.read_head(self.home))
        self.assertEqual(ctx.exception.reason, "digest-unverifiable")

    # ---- Home CAS + idempotency ----
    def test_publish_stale_home_revision(self):
        self._register_a()
        oid, dg = _commit(self.aw, "a.md", "x\n")
        stale = home.read_head(self.home)
        oid2, dg2 = _commit(self.aw, "b.md", "y\n")
        core.publish(self.home, CID, self._ref(oid, dg), [], stale)  # advances head
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(self.home, CID, self._ref(oid2, dg2, path="b.md"), [], stale)
        self.assertEqual(ctx.exception.code, errors.STALE_HOME_REVISION)

    def test_publish_idempotent_replay_same_revision(self):
        self._register_a()
        oid, dg = _commit(self.aw, "a.md", "x\n")
        first = core.publish(self.home, CID, self._ref(oid, dg), [], home.read_head(self.home))
        head_after_first = home.read_head(self.home)
        replay = core.publish(self.home, CID, self._ref(oid, dg), [], home.read_head(self.home))
        self.assertTrue(replay["replay"])
        self.assertEqual(replay["resulting_home_revision"], first["resulting_home_revision"])
        self.assertEqual(home.read_head(self.home), head_after_first)  # no new commit

    def test_publish_replay_ack_loss_stale_expected(self):
        # D-005 ack-loss: publish commits (head advances), ack is lost, client
        # retries with the STALE expected -> one-step replay-hit, not STALE.
        self._register_a()
        oid, dg = _commit(self.aw, "a.md", "x\n")
        stale = home.read_head(self.home)
        first = core.publish(self.home, CID, self._ref(oid, dg), [], stale)  # head -> H1
        replay = core.publish(self.home, CID, self._ref(oid, dg), [], stale)  # stale expected
        self.assertTrue(replay["replay"])
        self.assertEqual(replay["resulting_home_revision"], first["resulting_home_revision"])

    def test_publish_conflict_same_ref_diff_relations(self):
        self._register_a()
        o_obj, d_obj = _commit(self.aw, "obj.md", "obj\n")
        core.publish(self.home, CID, self._ref(o_obj, d_obj, path="obj.md"), [], home.read_head(self.home))
        o_sub, d_sub = _commit(self.aw, "a.md", "x\n")
        subj = self._ref(o_sub, d_sub)
        rel = [{"kind": "derived-from", "object": self._ref(o_obj, d_obj, path="obj.md")}]
        core.publish(self.home, CID, subj, [], home.read_head(self.home))  # no relations
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(self.home, CID, subj, rel, home.read_head(self.home))  # same ref, diff rel
        self.assertEqual(ctx.exception.code, errors.PUBLICATION_CONFLICT)

    def test_publish_relation_object_must_be_published(self):
        self._register_a()
        o_obj, d_obj = _commit(self.aw, "obj.md", "obj\n")
        o_sub, d_sub = _commit(self.aw, "a.md", "x\n")
        rel = [{"kind": "derived-from", "object": self._ref(o_obj, d_obj, path="obj.md")}]
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(self.home, CID, self._ref(o_sub, d_sub), rel, home.read_head(self.home))
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_publish_cross_kind_supersedes_fails(self):
        self._register_a()
        o_obj, d_obj = _commit(self.aw, "obj.md", "old\n")
        core.publish(self.home, CID, self._ref(o_obj, d_obj, path="obj.md", kind="prd"), [], home.read_head(self.home))
        o_sub, d_sub = _commit(self.aw, "a.md", "new\n")
        rel = [{"kind": "supersedes-artifact", "object": self._ref(o_obj, d_obj, path="obj.md", kind="prd")}]
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(self.home, CID, self._ref(o_sub, d_sub, kind="spec"), rel, home.read_head(self.home))
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    # ---- resolve ----
    def test_resolve_verified_bytes(self):
        self._register_a()
        oid, dg = _commit(self.aw, "a.md", "hello\n")
        core.publish(self.home, CID, self._ref(oid, dg), [], home.read_head(self.home))
        out = core.resolve(self.home, self._ref(oid, dg))
        self.assertEqual(out["bytes"], b"hello\n")
        self.assertNotIn("edges", out)  # resolve returns no provenance edges

    def test_resolve_unpublished_fails(self):
        self._register_a()
        oid, dg = _commit(self.aw, "a.md", "hello\n")  # committed but never published
        with self.assertRaises(errors.Unresolvable) as ctx:
            core.resolve(self.home, self._ref(oid, dg))
        self.assertEqual(ctx.exception.reason, "ref-unpublished")

    # ---- query / change-fact (authority isolation) ----
    def test_change_fact_reports_supersedes_no_verdict(self):
        self._register_a()
        o_old, d_old = _commit(self.aw, "old.md", "old\n")
        old_ref = self._ref(o_old, d_old, path="old.md", kind="prd")
        core.publish(self.home, CID, old_ref, [], home.read_head(self.home))
        o_new, d_new = _commit(self.aw, "new.md", "new\n")
        rel = [{"kind": "supersedes-artifact", "object": old_ref}]
        core.publish(self.home, CID, self._ref(o_new, d_new, path="new.md", kind="prd"), rel, home.read_head(self.home))
        fact = core.change_fact(self.home, old_ref)
        self.assertEqual(fact["resolvability"], "RESOLVABLE")
        self.assertEqual(len(fact["supersedes_in_edges"]), 1)
        self.assertNotIn("verdict", fact)
        self.assertNotIn("current", fact)
        self.assertNotIn("stale", fact)

    def test_change_fact_unresolvable_has_status_and_typed_reason(self):
        self._register_a()
        ref = self._ref("a" * 40, "b" * 64)
        fact = core.change_fact(self.home, ref)
        self.assertEqual(
            fact["resolvability"],
            {"status": "UNRESOLVABLE", "reason": "ref-unpublished"},
        )
        self.assertEqual(set(fact), {"resolvability", "supersedes_in_edges"})

    def test_change_fact_captures_home_head_once(self):
        self._register_a()
        oid, dg = _commit(self.aw, "a.md", "x\n")
        ref = self._ref(oid, dg)
        original = home.read_head
        calls = []

        def counted(git_dir):
            calls.append(git_dir)
            return original(git_dir)

        from unittest import mock
        with mock.patch("foundation.core.home.read_head", side_effect=counted):
            core.change_fact(self.home, ref)
        self.assertEqual(len(calls), 1)

    def test_query_edges_only_no_authority_fields(self):
        self._register_a()
        o_obj, d_obj = _commit(self.aw, "obj.md", "o\n")
        obj_ref = self._ref(o_obj, d_obj, path="obj.md")
        core.publish(self.home, CID, obj_ref, [], home.read_head(self.home))
        o_sub, d_sub = _commit(self.aw, "a.md", "s\n")
        rel = [{"kind": "derived-from", "object": obj_ref}]
        core.publish(self.home, CID, self._ref(o_sub, d_sub), rel, home.read_head(self.home))
        q = core.query(self.home, self._ref(o_sub, d_sub), kind="derived-from")
        self.assertEqual(set(q), {"direct_edges", "transitive", "resolvability", "home_revision"})
        self.assertEqual(len(q["direct_edges"]["out"]), 1)
        self.assertEqual(q["home_revision"], home.read_head(self.home))


if __name__ == "__main__":
    unittest.main()
