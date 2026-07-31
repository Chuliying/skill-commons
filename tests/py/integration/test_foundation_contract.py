"""S8 — fail-closed / adversarial contract corpus (qa-plan v1.1.0 §3 + §5).

Binds every adversarial row ADV-01..24 and every boundary row TC-B01..B07 to an
executable assertion, with real temp git repos as the independent oracle (D-010).
Complements the frozen consumer-contract oracle (test_consumer_contract_checkpoint.py)
and the per-module unit/integration suites; here each ADV/TC id is explicit and mapped.

Structural rows (a cycle or a cross-home merge cannot be constructed through the
public API) are encoded as absence/structural assertions, per qa-plan §5 note.
"""

import contextlib
import hashlib
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

from foundation import cli, core, errors, graph, home, homelocator, schema


def _make_git(prefix, object_format=None):
    d = tempfile.mkdtemp(prefix=prefix)
    args = ["git", "-C", d, "init", "-q"]
    if object_format:
        args += ["--object-format", object_format]
    subprocess.run(args, capture_output=True)
    subprocess.run(["git", "-C", d, "config", "user.email", "t@e"], check=True, capture_output=True)
    subprocess.run(["git", "-C", d, "config", "user.name", "t"], check=True, capture_output=True)
    return d


def _commit(work, rel, content):
    with open(os.path.join(work, rel), "w", encoding="utf-8") as fh:
        fh.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True, capture_output=True)
    subprocess.run(["git", "-C", work, "commit", "-q", "-m", "x"], check=True, capture_output=True)
    oid = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"], check=True,
                         capture_output=True, text=True).stdout.strip()
    return oid, hashlib.sha256(content.encode()).hexdigest()


class _Base(unittest.TestCase):
    def setUp(self):
        self.hw = _make_git("fdn-ct-home-")
        self.home = os.path.join(self.hw, ".git")
        self.aw = _make_git("fdn-ct-repoA-")
        self.a_git = os.path.join(self.aw, ".git")
        for d in (self.hw, self.aw):
            self.addCleanup(shutil.rmtree, d, ignore_errors=True)
        core.register(self.home, "repoA", self.a_git, home.read_head(self.home))

    def _ref(self, oid, dg, path="a.md", kind="prd", repo="repoA"):
        return {"repo_id": repo, "commit_oid": oid, "path": path, "digest": dg, "artifact_kind": kind}

    def _publish(self, path, content, kind="prd", relations=None):
        oid, dg = _commit(self.aw, path, content)
        ref = self._ref(oid, dg, path=path, kind=kind)
        core.publish(self.home, "repoA/home", ref, relations or [], home.read_head(self.home))
        return ref

    def _head(self):
        return home.read_head(self.home)


class AdversarialCorpus(_Base):
    def _assert_zero_write(self, before, fn):
        with self.assertRaises((errors.FoundationError, errors.Unresolvable)):
            fn()
        self.assertEqual(self._head(), before)  # zero-write: head unchanged

    def test_adv01_object_missing(self):
        self._assert_zero_write(self._head(), lambda: core.publish(
            self.home, "repoA/home", self._ref("f" * 40, "d" * 64), [], self._head()))

    def test_adv02_digest_mismatch(self):
        oid, _dg = _commit(self.aw, "a.md", "x\n")
        self._assert_zero_write(self._head(), lambda: core.publish(
            self.home, "repoA/home", self._ref(oid, "0" * 64), [], self._head()))

    def test_adv03_path_escape(self):
        oid, dg = _commit(self.aw, "a.md", "x\n")
        for bad in ("../etc/passwd", "/abs", "a/../../b", ":(top)a"):
            with self.subTest(path=bad):
                with self.assertRaises((errors.FoundationError, errors.Unresolvable)):
                    core.publish(self.home, "repoA/home", self._ref(oid, dg, path=bad), [], self._head())

    def test_adv04_dirty_only_bytes(self):
        oid, _dg = _commit(self.aw, "a.md", "committed\n")
        with open(os.path.join(self.aw, "a.md"), "w", encoding="utf-8") as fh:
            fh.write("dirty\n")                                  # worktree-only, uncommitted
        dirty_dg = hashlib.sha256(b"dirty\n").hexdigest()
        self._assert_zero_write(self._head(), lambda: core.publish(
            self.home, "repoA/home", self._ref(oid, dirty_dg), [], self._head()))

    def test_adv05_unregistered_and_duplicate_identity(self):
        oid, dg = _commit(self.aw, "a.md", "x\n")
        with self.assertRaises(errors.FoundationError) as ctx:            # unregistered repo
            core.publish(self.home, "repoA/home", self._ref(oid, dg, repo="ghost"), [], self._head())
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)
        with self.assertRaises(errors.FoundationError) as ctx:            # duplicate identity, diff locator
            core.register(self.home, "repoA", "/other/loc", self._head())
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_adv06_relation_object_unpublished(self):
        oid, dg = _commit(self.aw, "a.md", "x\n")
        unpub = self._ref(*_commit(self.aw, "u.md", "u\n"), path="u.md")
        self._assert_zero_write(self._head(), lambda: core.publish(
            self.home, "repoA/home", self._ref(oid, dg),
            [{"kind": "derived-from", "object": unpub}], self._head()))

    def test_adv07_unknown_relation_kind(self):
        base = self._publish("base.md", "b\n")
        oid, dg = _commit(self.aw, "a.md", "x\n")
        self._assert_zero_write(self._head(), lambda: core.publish(
            self.home, "repoA/home", self._ref(oid, dg),
            [{"kind": "requires", "object": base}], self._head()))

    def test_adv08_cross_kind_supersedes(self):
        base = self._publish("base.md", "b\n", kind="prd")
        oid, dg = _commit(self.aw, "a.md", "x\n")
        self._assert_zero_write(self._head(), lambda: core.publish(
            self.home, "repoA/home", self._ref(oid, dg, kind="spec"),   # cross-kind
            [{"kind": "supersedes-artifact", "object": base}], self._head()))

    def test_adv09_cycle_and_self_edge_structural(self):
        # A cycle/self-edge cannot be built via the public API (relations point only to
        # already-published, immutable objects; the new subject is not yet an object).
        # The guard is graph.check_acyclic; assert it rejects a constructed cyclic set.
        a = self._ref("a" * 40, "b" * 64, path="a.md")
        self_env = {"artifact_ref": a, "relations": [{"kind": "derived-from", "object": a}]}
        with self.assertRaises(errors.FoundationError) as ctx:
            graph.check_acyclic([self_env])
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_adv10_home_cas_stale_parent(self):
        base = self._publish("base.md", "b\n")
        stale = self._head()
        self._publish("adv.md", "adv\n")                          # advance head past `stale`
        oid, dg = _commit(self.aw, "c.md", "c\n")
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(self.home, "repoA/home", self._ref(oid, dg, path="c.md"), [], stale)
        self.assertEqual(ctx.exception.code, errors.STALE_HOME_REVISION)

    def test_adv11_same_ref_different_relations(self):
        base = self._publish("base.md", "b\n")
        oid, dg = _commit(self.aw, "a.md", "x\n")
        ref = self._ref(oid, dg)
        core.publish(self.home, "repoA/home", ref, [], self._head())
        with self.assertRaises(errors.FoundationError) as ctx:            # same Ref, new relation set
            core.publish(self.home, "repoA/home", ref,
                         [{"kind": "derived-from", "object": base}], self._head())
        self.assertEqual(ctx.exception.code, errors.PUBLICATION_CONFLICT)

    def test_adv12_query_read_only_no_persisted_write(self):
        ref = self._publish("q.md", "q\n")
        before_head = self._head()
        before = home.read_state(self.home, before_head)
        before_refs = subprocess.run(
            ["git", "--git-dir", self.home, "show-ref"],
            check=True,
            capture_output=True,
        ).stdout
        before_tree = subprocess.run(
            ["git", "--git-dir", self.home, "rev-parse", f"{before_head}^{{tree}}"],
            check=True,
            capture_output=True,
        ).stdout
        core.query(self.home, ref, kind="derived-from")
        core.change_fact(self.home, ref)
        after_head = self._head()
        after_refs = subprocess.run(
            ["git", "--git-dir", self.home, "show-ref"],
            check=True,
            capture_output=True,
        ).stdout
        after_tree = subprocess.run(
            ["git", "--git-dir", self.home, "rev-parse", f"{after_head}^{{tree}}"],
            check=True,
            capture_output=True,
        ).stdout
        self.assertEqual((after_head, after_refs, after_tree), (before_head, before_refs, before_tree))
        self.assertEqual(home.read_state(self.home, after_head), before)
        self.assertEqual(core.query(self.home, ref)["home_revision"], self._head())

    def test_adv13_query_snapshot_then_head_advances(self):
        ref = self._publish("q.md", "q\n")
        captured = self._head()
        self._publish(
            "later.md",
            "l\n",
            relations=[{"kind": "supersedes-artifact", "object": ref}],
        )
        advanced = self._head()
        subprocess.run(
            ["git", "--git-dir", self.home, "update-ref", home.HOME_REF, captured, advanced],
            check=True,
            capture_output=True,
        )
        original_read_head = home.read_head
        calls = []

        def capture_then_advance(git_dir):
            calls.append(git_dir)
            if len(calls) == 1:
                subprocess.run(
                    ["git", "--git-dir", self.home, "update-ref", home.HOME_REF, advanced, captured],
                    check=True,
                    capture_output=True,
                )
                return captured
            return original_read_head(git_dir)

        with mock.patch("foundation.core.home.read_head", side_effect=capture_then_advance):
            snap = core.query(self.home, ref, kind="supersedes-artifact")
        self.assertEqual(len(calls), 1)
        self.assertEqual(snap["home_revision"], captured)
        self.assertEqual(snap["transitive"]["edges"], [])
        self.assertEqual(self._head(), advanced)
        next_result = core.query(self.home, ref, kind="supersedes-artifact")
        self.assertEqual(next_result["home_revision"], advanced)
        self.assertEqual(
            {edge["subject"]["path"] for edge in next_result["transitive"]["edges"]},
            {"later.md"},
        )

    def test_adv14_ref_unpublished_resolve(self):
        oid, dg = _commit(self.aw, "a.md", "x\n")                 # valid git Ref, never published
        with self.assertRaises(errors.Unresolvable) as ctx:
            core.resolve(self.home, self._ref(oid, dg))
        self.assertEqual(ctx.exception.reason, "ref-unpublished")

    def test_adv15_fork_clone_same_oid_distinct_ref(self):
        # same commit OID in two registered repos -> distinct Ref identity, no false replay.
        bw = _make_git("fdn-ct-repoB-")
        self.addCleanup(shutil.rmtree, bw, ignore_errors=True)
        core.register(self.home, "repoB", os.path.join(bw, ".git"), self._head())
        oid, dg = _commit(self.aw, "a.md", "same\n")
        # mirror the identical content+path into repoB so the same digest exists there
        oidb, dgb = _commit(bw, "a.md", "same\n")
        ra = self._ref(oid, dg, repo="repoA")
        rb = self._ref(oidb, dgb, repo="repoB")
        self.assertNotEqual(schema.canonical_json(schema.validate_artifact_ref(ra)),
                            schema.canonical_json(schema.validate_artifact_ref(rb)))
        core.publish(self.home, "repoA/home", ra, [], self._head())
        r = core.publish(self.home, "repoA/home", rb, [], self._head())
        self.assertFalse(r["replay"])                             # distinct Ref, not a replay

    def test_adv16_cross_home_relation_structural(self):
        # No public API merges two homes; a relation to an object not published in THIS
        # home fails closed (there is no cross-home resolution path).
        other = self._ref("c" * 40, "d" * 64, path="other.md")   # not published in self.home
        oid, dg = _commit(self.aw, "a.md", "x\n")
        self._assert_zero_write(self._head(), lambda: core.publish(
            self.home, "repoA/home", self._ref(oid, dg),
            [{"kind": "derived-from", "object": other}], self._head()))

    def test_adv17_home_force_push_rewrite(self):
        base = self._publish("base.md", "b\n")
        h1 = self._head()
        self._publish("adv.md", "adv\n")
        h2 = self._head()
        subprocess.run(["git", "--git-dir", self.home, "update-ref", home.HOME_REF, h1],
                       check=True, capture_output=True)            # force rewind
        oid, dg = _commit(self.aw, "c.md", "c\n")
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(self.home, "repoA/home", self._ref(oid, dg, path="c.md"), [], h2)
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_adv18_remote_url_locator_no_fetch(self):
        # A registry locator that is a remote URL must fail closed, never fetch.
        core.register(self.home, "remoteRepo", "https://example.invalid/x.git", self._head())
        oid, dg = _commit(self.aw, "a.md", "x\n")
        with self.assertRaises((errors.FoundationError, errors.Unresolvable)):
            core.publish(self.home, "repoA/home", self._ref(oid, dg, repo="remoteRepo"), [], self._head())

    def test_adv19_authority_leak_probe(self):
        base = self._publish("base.md", "b\n")
        self._publish("newer.md", "n\n", relations=[{"kind": "supersedes-artifact", "object": base}])
        fact = core.change_fact(self.home, base)
        q = core.query(self.home, base, kind="supersedes-artifact")
        forbidden = {"current", "stale", "impact", "approval", "gate", "SUPERSEDED", "superseded", "verdict"}
        self.assertTrue(forbidden.isdisjoint(fact.keys()))
        self.assertTrue(forbidden.isdisjoint(q.keys()))
        self.assertEqual(fact["resolvability"], "RESOLVABLE")
        self.assertIn(q["resolvability"], {"RESOLVABLE", *errors.UNRESOLVABLE_REASONS})
        # transitive is a full edge set, not just tips (heads = a currentness pick)
        self.assertEqual(len(q["transitive"]["edges"]), 1)

    def test_adv20_cas_toctou_interleave(self):
        # Validation reads head h1; a competing writer advances to h2 before the CAS.
        # update-ref old-value=h1 fails atomically -> STALE zero-write (precheck-only fails here).
        self._publish("base.md", "b\n")
        h1 = self._head()
        oid_x, dg_x = _commit(self.aw, "x.md", "x\n")
        tree = subprocess.run(
            ["git", "--git-dir", self.home, "rev-parse", f"{h1}^{{tree}}"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        competitor = subprocess.run(
            ["git", "--git-dir", self.home, "commit-tree", tree, "-p", h1, "-m", "competitor"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        candidate = self._ref(oid_x, dg_x, path="x.md")
        candidate_digest = schema.envelope_digest("repoA/home", candidate, [])
        original_run = home._run
        injected = False

        def interleaved_run(git_dir, args, input_bytes=None, env_extra=None):
            nonlocal injected
            if args and args[0] == "update-ref" and home.HOME_REF in args and not injected:
                injected = True
                winner = original_run(
                    git_dir,
                    ["update-ref", "--no-deref", home.HOME_REF, competitor, h1],
                )
                self.assertEqual(winner.returncode, 0)
            return original_run(git_dir, args, input_bytes=input_bytes, env_extra=env_extra)

        with mock.patch("foundation.home._run", side_effect=interleaved_run):
            with self.assertRaises(errors.FoundationError) as ctx:
                core.publish(self.home, "repoA/home", candidate, [], h1)
        self.assertEqual(ctx.exception.code, errors.STALE_HOME_REVISION)
        self.assertTrue(injected)
        self.assertEqual(self._head(), competitor)
        self.assertNotIn(
            f"envelope-{candidate_digest}.json",
            home.read_state(self.home, competitor),
        )

    def test_adv21_poisoned_home_entry_no_false_publish(self):
        # A stale derived-index artifact claims the candidate is already published,
        # while the authoritative envelope tree does not. Publish must ignore it.
        oid, dg = _commit(self.aw, "indexed.md", "authoritative\n")
        candidate = self._ref(oid, dg, path="indexed.md")
        digest = schema.envelope_digest("repoA/home", candidate, [])
        home.commit_entries(
            self.home,
            self._head(),
            {"derived-index.json": schema.canonical_json({"published": [digest]}).encode()},
        )
        result = core.publish(self.home, "repoA/home", candidate, [], self._head())
        self.assertFalse(result["replay"])
        self.assertIn(
            f"envelope-{digest}.json",
            home.read_state(self.home, result["resulting_home_revision"]),
        )

    def test_adv22_error_precedence_conflict_before_stale(self):
        # Same Ref + different relations (validation) AND stale parent (CAS) at once:
        # PUBLICATION_CONFLICT (validation stage) precedes STALE (CAS stage) — HD-S1.
        base = self._publish("base.md", "b\n")
        oid, dg = _commit(self.aw, "a.md", "x\n")
        ref = self._ref(oid, dg)
        core.publish(self.home, "repoA/home", ref, [], self._head())
        stale = base if False else self._head()  # capture a head, then advance it
        self._publish("advance.md", "adv\n")     # now `stale` is behind head
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(self.home, "repoA/home", ref,
                         [{"kind": "derived-from", "object": base}], stale)
        self.assertEqual(ctx.exception.code, errors.PUBLICATION_CONFLICT)

    def test_adv23_registration_idempotent_conflict_bootstrap(self):
        # empty-home bootstrap already happened in setUp (register repoA on empty home).
        # idempotent no-op returns current revision; identity conflict fails closed.
        h = self._head()
        self.assertEqual(core.register(self.home, "repoA", self.a_git, h), h)   # idempotent
        with self.assertRaises(errors.FoundationError):                          # locator already bound
            core.register(self.home, "repoZ", self.a_git, h)

    def test_adv24_dead_locator_no_auto_search(self):
        ref = self._publish("a.md", "content\n")                  # published via repoA (self.a_git)
        # a decoy repo with the same content exists elsewhere...
        decoy = _make_git("fdn-ct-decoy-")
        self.addCleanup(shutil.rmtree, decoy, ignore_errors=True)
        _commit(decoy, "a.md", "content\n")
        shutil.rmtree(self.aw, ignore_errors=True)                # ...but the REGISTERED locator dies
        with self.assertRaises(errors.Unresolvable):             # resolve uses the dead locator, never auto-searches
            core.resolve(self.home, ref)

    # --- ADV-25: corrupt authoritative home -> typed HOME_ERROR (6th class, re-verify).
    # Split into ISOLATED, non-masking cases: the earlier single cell planted a bad
    # envelope + bad registry together, so the envelope always failed first and shadowed
    # the registry leg, and it never exercised the CLI.

    def _assert_all_core_ops_home_error(self, good):
        newish = self._ref(*_commit(self.aw, "n.md", "n\n"), path="n.md")
        ops = {
            "query": lambda: core.query(self.home, good),
            "change_fact": lambda: core.change_fact(self.home, good),
            "resolve": lambda: core.resolve(self.home, good),
            "publish": lambda: core.publish(self.home, "repoA/home", newish, [], self._head()),
        }
        for name, op in ops.items():
            with self.subTest(op=name):
                with self.assertRaises(errors.FoundationError) as ctx:
                    op()
                self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_adv25a_corrupt_envelope_unknown_field(self):
        # ONLY an envelope corruption (unknown field — the tamper that recompute-through-
        # publication_envelope previously discarded). No registry corruption.
        good = self._publish("good.md", "g\n")
        tampered = dict(schema.publication_envelope("repoA/home", good, []))
        tampered["surprise"] = 1
        home.commit_entries(self.home, self._head(),
                            {"envelope-tampersib.json": schema.canonical_json(tampered).encode()})
        self._assert_all_core_ops_home_error(good)

    def test_adv25b_corrupt_registry_wrong_type(self):
        # ONLY a registry corruption (repo_id is not a string). Envelopes all valid, so the
        # registry leg is actually exercised (not shadowed).
        good = self._publish("good.md", "g\n")
        bad = {"repo_id": [], "locator": "/x", "kind": "registry"}
        home.commit_entries(self.home, self._head(),
                            {"registry-bad.json": schema.canonical_json(bad).encode()})
        self._assert_all_core_ops_home_error(good)

    def test_adv25c_registry_filename_impersonation(self):
        # ONLY a registry corruption: registry-zzz.json whose content claims repo_id=repoA
        # would shadow the real binding. filename<->repo_id binding rejects it.
        good = self._publish("good.md", "g\n")
        impostor = {"repo_id": "repoA", "locator": "/evil", "kind": "registry"}
        home.commit_entries(self.home, self._head(),
                            {"registry-zzz.json": schema.canonical_json(impostor).encode()})
        self._assert_all_core_ops_home_error(good)

    def test_adv25d_cli_corrupt_home_is_home_error(self):
        # The CLI must map a corrupt authoritative home to HOME_ERROR, never SCHEMA_ERROR.
        good = self._publish("good.md", "g\n")
        home.commit_entries(self.home, self._head(), {"envelope-x.json": b"\xff\xff"})
        os.makedirs(os.path.join(self.hw, ".agent"), exist_ok=True)
        cfg = os.path.join(self.hw, ".agent", "artifact-home.json")
        with open(cfg, "w", encoding="utf-8") as fh:
            json.dump({"repo_id": "home", "path": ".git"}, fh)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cli.main(["query", "--home-config", cfg, "--ref", json.dumps(good)])
        out = json.loads(buf.getvalue().strip())
        self.assertEqual(rc, 2)
        self.assertEqual(out["error"], errors.HOME_ERROR)

    def test_adv25e_symref_home_fails_closed(self):
        # A symref home ref (points at a user branch) must not be read as an authoritative
        # Home commit; read paths fail closed with HOME_ERROR.
        good = self._publish("good.md", "g\n")
        h = self._head()
        subprocess.run(["git", "--git-dir", self.home, "update-ref", "refs/heads/main", h],
                       check=True, capture_output=True)
        subprocess.run(["git", "--git-dir", self.home, "symbolic-ref", home.HOME_REF, "refs/heads/main"],
                       check=True, capture_output=True)
        for name, op in {
            "query": lambda: core.query(self.home, good),
            "change_fact": lambda: core.change_fact(self.home, good),
            "resolve": lambda: core.resolve(self.home, good),
        }.items():
            with self.subTest(op=name):
                with self.assertRaises(errors.FoundationError) as ctx:
                    op()
                self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_adv25f_deeply_nested_json_is_home_error(self):
        # Deeply-nested JSON raises RecursionError (a RuntimeError) inside json.loads; it
        # must map to typed HOME_ERROR, not escape untyped / crash the CLI (re-verify #1).
        good = self._publish("good.md", "g\n")
        home.commit_entries(self.home, self._head(),
                            {"envelope-nested.json": b"[" * 2000 + b"]" * 2000})
        self._assert_all_core_ops_home_error(good)
        os.makedirs(os.path.join(self.hw, ".agent"), exist_ok=True)
        cfg = os.path.join(self.hw, ".agent", "artifact-home.json")
        with open(cfg, "w", encoding="utf-8") as fh:
            json.dump({"repo_id": "home", "path": ".git"}, fh)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cli.main(["query", "--home-config", cfg, "--ref", json.dumps(good)])
        self.assertEqual(rc, 2)
        self.assertEqual(json.loads(buf.getvalue().strip())["error"], errors.HOME_ERROR)

    def test_adv25g_duplicate_envelope_for_one_ref(self):
        # Two self-consistent envelopes for the SAME artifact_ref (a write-time
        # PUBLICATION_CONFLICT) must fail closed at read, not silently merge (re-verify #2).
        base = self._publish("base.md", "b\n")
        good = self._publish("good.md", "g\n")
        rels = [{"kind": "derived-from", "object": base}]
        env2 = schema.publication_envelope("repoA/home", good, rels)
        d2 = schema.envelope_digest("repoA/home", good, rels)
        home.commit_entries(self.home, self._head(),
                            {f"envelope-{d2}.json": schema.canonical_json(env2).encode()})
        self._assert_all_core_ops_home_error(good)

    def test_adv25h_mixed_collection_identity(self):
        # One home <-> one collection identity; a foreign-identity envelope (split-brain,
        # CH-5) fails closed (re-verify #3).
        good = self._publish("good.md", "g\n")
        evil = self._ref(*_commit(self.aw, "evil.md", "e\n"), path="evil.md")
        env = schema.publication_envelope("evil/elsewhere", evil, [])
        d = schema.envelope_digest("evil/elsewhere", evil, [])
        home.commit_entries(self.home, self._head(),
                            {f"envelope-{d}.json": schema.canonical_json(env).encode()})
        self._assert_all_core_ops_home_error(good)

    def test_adv25i_register_fails_closed_on_corrupt_envelope(self):
        # NIT #4: register must fail closed on a corrupt home too (envelope corruption),
        # not only registry corruption.
        self._publish("good.md", "g\n")
        home.commit_entries(self.home, self._head(), {"envelope-x.json": b"\xff\xff"})
        with self.assertRaises(errors.FoundationError) as ctx:
            core.register(self.home, "repoNew", "/some/new/loc", self._head())
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_adv25j_unhashable_relation_kind(self):
        # A stored envelope whose relation `kind` is unhashable (list/dict) must not escape
        # as an untyped TypeError / mislabeled SCHEMA_ERROR (re-verify round 3, 8th class).
        base = self._publish("base.md", "b\n")
        good = self._publish("good.md", "g\n")
        bad_env = {"collection_identity": "repoA/home", "artifact_ref": good,
                   "relations": [{"kind": [], "object": base}]}
        home.commit_entries(self.home, self._head(),
                            {"envelope-unhashablekind.json": schema.canonical_json(bad_env).encode()})
        self._assert_all_core_ops_home_error(good)
        os.makedirs(os.path.join(self.hw, ".agent"), exist_ok=True)
        cfg = os.path.join(self.hw, ".agent", "artifact-home.json")
        with open(cfg, "w", encoding="utf-8") as fh:
            json.dump({"repo_id": "home", "path": ".git"}, fh)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cli.main(["query", "--home-config", cfg, "--ref", json.dumps(good)])
        self.assertEqual(rc, 2)
        self.assertEqual(json.loads(buf.getvalue().strip())["error"], errors.HOME_ERROR)

    def test_adv25k_registry_surrogate_locator(self):
        # A stored registry locator with a lone surrogate makes canonical_json(...).encode()
        # raise UnicodeEncodeError (a ValueError) in _registry — the shared home-state guard
        # must map it to HOME_ERROR from every op + CLI (re-verify round 4, 9th class).
        good = self._publish("good.md", "g\n")
        bad = json.dumps({"repo_id": "repoB", "locator": "\ud800", "kind": "registry"}).encode()
        home.commit_entries(self.home, self._head(), {"registry-repoB.json": bad})
        self._assert_all_core_ops_home_error(good)
        os.makedirs(os.path.join(self.hw, ".agent"), exist_ok=True)
        cfg = os.path.join(self.hw, ".agent", "artifact-home.json")
        with open(cfg, "w", encoding="utf-8") as fh:
            json.dump({"repo_id": "home", "path": ".git"}, fh)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cli.main(["query", "--home-config", cfg, "--ref", json.dumps(good)])
        self.assertEqual(rc, 2)
        self.assertEqual(json.loads(buf.getvalue().strip())["error"], errors.HOME_ERROR)

    def test_adv25l_register_rejects_surrogate_locator(self):
        # Caller-supplied non-UTF-8 locator -> SCHEMA_ERROR at the boundary (never untyped),
        # and never written into the home.
        with self.assertRaises(errors.FoundationError) as ctx:
            core.register(self.home, "repoX", "\ud800", self._head())
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_adv25m_guard_maps_any_exception_type_to_home_error(self):
        # Legal-Home condition 5 (spec "Legal Home (V1)"): ANY exception raised while
        # parsing/validating UNTRUSTED stored state -> HOME_ERROR, not merely an enumerated
        # tuple. This is the STRUCTURAL end of the per-type whack-a-mole (UnicodeDecodeError
        # -> RecursionError -> TypeError -> UnicodeEncodeError were each caught one at a time).
        # Inject a type OUTSIDE that history (AttributeError) into the stored-state parser --
        # `_parse` is called ONLY by the two guarded parsers, so this isolates stored-state
        # validation from caller/write paths -- and assert the SHARED guard still fails closed
        # from every core op + register (the _registry sibling) + the CLI.
        good = self._publish("good.md", "g\n")
        with mock.patch.object(core, "_parse",
                               side_effect=AttributeError("injected parse failure over stored state")):
            self._assert_all_core_ops_home_error(good)          # query/change_fact/resolve/publish
            with self.assertRaises(errors.FoundationError) as ctx:
                core.register(self.home, "repoZ", self.a_git, self._head())   # _registry sibling
            self.assertEqual(ctx.exception.code, errors.HOME_ERROR)
            os.makedirs(os.path.join(self.hw, ".agent"), exist_ok=True)
            cfg = os.path.join(self.hw, ".agent", "artifact-home.json")
            with open(cfg, "w", encoding="utf-8") as fh:
                json.dump({"repo_id": "home", "path": ".git"}, fh)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = cli.main(["query", "--home-config", cfg, "--ref", json.dumps(good)])
            self.assertEqual(rc, 2)
            self.assertEqual(json.loads(buf.getvalue().strip())["error"], errors.HOME_ERROR)


class BoundaryCorpus(_Base):
    def test_tcb01_locator_global_path_rejected(self):
        anchor = _make_git("fdn-ct-anchor-")
        self.addCleanup(shutil.rmtree, anchor, ignore_errors=True)
        os.makedirs(os.path.join(anchor, ".agent"), exist_ok=True)
        cfg = os.path.join(anchor, ".agent", "artifact-home.json")
        import json
        with open(cfg, "w", encoding="utf-8") as fh:
            json.dump({"home_git_dir": self.home}, fh)           # hardcoded global path form
        with self.assertRaises(errors.FoundationError) as ctx:
            homelocator.resolve_home(cfg)
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_tcb02_fork_clone_distinct_ref(self):
        # same as ADV-15 at the boundary: repo_id is part of identity.
        a = self._ref("a" * 40, "b" * 64, repo="repoA")
        b = self._ref("a" * 40, "b" * 64, repo="repoB")
        self.assertNotEqual(schema.canonical_json(schema.validate_artifact_ref(a)),
                            schema.canonical_json(schema.validate_artifact_ref(b)))

    def test_tcb03_ack_loss_replay_one_step(self):
        oid, dg = _commit(self.aw, "a.md", "x\n")
        ref = self._ref(oid, dg)
        first = core.publish(self.home, "repoA/home", ref, [], self._head())
        head_after = self._head()
        replay = core.publish(self.home, "repoA/home", ref, [], first["resulting_home_revision"])
        self.assertTrue(replay["replay"])
        self.assertEqual(replay["resulting_home_revision"], first["resulting_home_revision"])
        self.assertEqual(self._head(), head_after)               # no second commit

    def test_tcb04_head_advance_before_query(self):
        ref = self._publish("a.md", "x\n")
        self._publish("b.md", "y\n")                             # advance head
        self.assertEqual(core.query(self.home, ref)["home_revision"], self._head())

    def test_tcb05_home_history_rewrite_fails_closed(self):
        self._publish("base.md", "b\n")
        h1 = self._head()
        self._publish("adv.md", "a\n")
        h2 = self._head()
        subprocess.run(["git", "--git-dir", self.home, "update-ref", home.HOME_REF, h1],
                       check=True, capture_output=True)
        oid, dg = _commit(self.aw, "c.md", "c\n")
        with self.assertRaises(errors.FoundationError) as ctx:
            core.publish(self.home, "repoA/home", self._ref(oid, dg, path="c.md"), [], h2)
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_tcb06_branch_successor_transitive(self):
        x = self._publish("x.md", "x\n")
        y = self._publish("y.md", "y\n", relations=[{"kind": "supersedes-artifact", "object": x}])
        self._publish("z.md", "z\n", relations=[{"kind": "supersedes-artifact", "object": x}])
        self._publish("w.md", "w\n", relations=[{"kind": "supersedes-artifact", "object": y}])
        trans = core.query(self.home, x, kind="supersedes-artifact")["transitive"]["edges"]
        self.assertEqual({e["subject"]["path"] for e in trans}, {"y.md", "z.md", "w.md"})
        from_y = core.query(self.home, y, kind="supersedes-artifact")["transitive"]["edges"]
        self.assertEqual({e["subject"]["path"] for e in from_y}, {"w.md"})

    def test_tcb07_resolve_reads_git_object_not_worktree(self):
        ref = self._publish("a.md", "committed\n")
        with open(os.path.join(self.aw, "a.md"), "w", encoding="utf-8") as fh:
            fh.write("WORKTREE\n")
        self.assertEqual(core.resolve(self.home, ref)["bytes"], b"committed\n")


if __name__ == "__main__":
    unittest.main()
