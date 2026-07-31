"""S3 — Git-backed Collection Home + CAS (spec D-004/D-011, FR-001/003, ERR-002/005).

home revision = commit OID at refs/foundation/home; writes are plumbing-only
(hash-object/mktree/commit-tree/update-ref) so they never touch a worktree or
branch. CAS via `git update-ref <ref> <new> <old>`: a stale expected head is a
zero-write STALE_HOME_REVISION. Real temp git repo = independent oracle.
"""

import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import errors, home


def _make_home():
    d = tempfile.mkdtemp(prefix="fdn-home-")
    subprocess.run(["git", "-C", d, "init", "-q"], check=True, capture_output=True)
    return d, os.path.join(d, ".git")


class TestHome(unittest.TestCase):
    def setUp(self):
        self.work, self.git_dir = _make_home()
        self.addCleanup(shutil.rmtree, self.work, ignore_errors=True)

    def test_empty_home_head_is_none(self):
        self.assertIsNone(home.read_head(self.git_dir))

    def test_malformed_home_ref_fails_closed(self):
        ref_path = os.path.join(self.git_dir, home.HOME_REF)
        os.makedirs(os.path.dirname(ref_path), exist_ok=True)
        with open(ref_path, "w", encoding="utf-8") as handle:
            handle.write("not-an-oid\n")
        with self.assertRaises(errors.FoundationError) as ctx:
            home.read_head(self.git_dir)
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_dangling_home_ref_fails_closed(self):
        oid = "a" * 40
        ref_path = os.path.join(self.git_dir, home.HOME_REF)
        os.makedirs(os.path.dirname(ref_path), exist_ok=True)
        with open(ref_path, "w", encoding="utf-8") as handle:
            handle.write(f"{oid}\n")
        with self.assertRaises(errors.FoundationError) as ctx:
            home.read_head(self.git_dir)
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_non_commit_home_ref_fails_closed(self):
        blob = subprocess.run(
            ["git", "--git-dir", self.git_dir, "hash-object", "-w", "--stdin"],
            input=b"not a commit",
            check=True,
            capture_output=True,
        ).stdout.decode().strip()
        subprocess.run(
            ["git", "--git-dir", self.git_dir, "update-ref", home.HOME_REF, blob],
            check=True,
            capture_output=True,
        )
        with self.assertRaises(errors.FoundationError) as ctx:
            home.read_head(self.git_dir)
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_bootstrap_then_read(self):
        h1 = home.commit_entries(self.git_dir, None, {"registry-repoA.json": b"{}"})
        self.assertEqual(home.read_head(self.git_dir), h1)
        self.assertEqual(home.get_entry(self.git_dir, h1, "registry-repoA.json"), b"{}")

    def test_get_entry_absent_is_none(self):
        h1 = home.commit_entries(self.git_dir, None, {"a.json": b"1"})
        self.assertIsNone(home.get_entry(self.git_dir, h1, "missing.json"))

    def test_sequential_commits_accumulate(self):
        h1 = home.commit_entries(self.git_dir, None, {"a.json": b"1"})
        h2 = home.commit_entries(self.git_dir, h1, {"b.json": b"2"})
        self.assertNotEqual(h1, h2)
        self.assertEqual(home.get_entry(self.git_dir, h2, "a.json"), b"1")
        self.assertEqual(home.get_entry(self.git_dir, h2, "b.json"), b"2")

    def test_cas_stale_parent_zero_write(self):
        h1 = home.commit_entries(self.git_dir, None, {"a.json": b"1"})
        h2 = home.commit_entries(self.git_dir, h1, {"b.json": b"2"})
        # Second writer still thinks head is h1 (stale) -> STALE, zero-write.
        with self.assertRaises(errors.FoundationError) as ctx:
            home.commit_entries(self.git_dir, h1, {"c.json": b"3"})
        self.assertEqual(ctx.exception.code, errors.STALE_HOME_REVISION)
        # git-side oracle: head is still h2; loser entry c.json absent from head.
        self.assertEqual(home.read_head(self.git_dir), h2)
        self.assertIsNone(home.get_entry(self.git_dir, h2, "c.json"))

    def test_bootstrap_cas_rejects_existing(self):
        home.commit_entries(self.git_dir, None, {"a.json": b"1"})
        # Another "first" writer with expected None must not clobber an existing home.
        with self.assertRaises(errors.FoundationError) as ctx:
            home.commit_entries(self.git_dir, None, {"a.json": b"2"})
        self.assertEqual(ctx.exception.code, errors.STALE_HOME_REVISION)

    def test_append_only_lineage(self):
        h1 = home.commit_entries(self.git_dir, None, {"a.json": b"1"})
        h2 = home.commit_entries(self.git_dir, h1, {"b.json": b"2"})
        self.assertTrue(home.is_ancestor(self.git_dir, h1, h2))
        self.assertFalse(home.is_ancestor(self.git_dir, h2, h1))

    def test_rewound_home_fails_closed(self):
        # Enforced append-only (B2/M8): externally rewind the ref (force-push),
        # then a writer with the pre-rewind head must get HOME_ERROR, not STALE.
        h1 = home.commit_entries(self.git_dir, None, {"a.json": b"1"})
        h2 = home.commit_entries(self.git_dir, h1, {"b.json": b"2"})
        subprocess.run(
            ["git", "--git-dir", self.git_dir, "update-ref", home.HOME_REF, h1],
            check=True, capture_output=True,
        )
        with self.assertRaises(errors.FoundationError) as ctx:
            home.commit_entries(self.git_dir, h2, {"c.json": b"3"})
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_sha256_home_bootstrap(self):
        # #10a: bootstrap CAS zero-OID must match the repo object format (sha256=64).
        d = tempfile.mkdtemp(prefix="fdn-home-sha256-")
        init = subprocess.run(["git", "-C", d, "init", "-q", "--object-format=sha256"], capture_output=True)
        if init.returncode != 0:
            shutil.rmtree(d, ignore_errors=True)
            self.skipTest("git lacks sha256 object-format support")
        self.addCleanup(shutil.rmtree, d, ignore_errors=True)
        gd = os.path.join(d, ".git")
        h1 = home.commit_entries(gd, None, {"a.json": b"1"})
        self.assertEqual(home.read_head(gd), h1)
        self.assertEqual(len(h1), 64)

    def test_deleted_home_ref_fails_closed(self):
        # A vanished home ref is a lineage violation (HOME_ERROR), not STALE:
        # retrying STALE would re-bootstrap a new root and orphan all history.
        h1 = home.commit_entries(self.git_dir, None, {"a.json": b"1"})
        subprocess.run(
            ["git", "--git-dir", self.git_dir, "update-ref", "-d", home.HOME_REF],
            check=True, capture_output=True,
        )
        with self.assertRaises(errors.FoundationError) as ctx:
            home.commit_entries(self.git_dir, h1, {"b.json": b"2"})
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_read_state_all_entries(self):
        h1 = home.commit_entries(self.git_dir, None, {"a.json": b"1"})
        h2 = home.commit_entries(self.git_dir, h1, {"b.json": b"2"})
        state = home.read_state(self.git_dir, h2)
        self.assertEqual(state, {"a.json": b"1", "b.json": b"2"})

    def test_overwrite_entry_same_name(self):
        h1 = home.commit_entries(self.git_dir, None, {"a.json": b"1"})
        h2 = home.commit_entries(self.git_dir, h1, {"a.json": b"9"})
        self.assertEqual(home.get_entry(self.git_dir, h2, "a.json"), b"9")

    def test_symref_home_write_does_not_move_branch(self):
        # M8/#3: even if refs/foundation/home is a (hostile/misconfigured) symref to a
        # branch, a write targets the home ref directly (--no-deref) and never moves the
        # branch. Without --no-deref this would move refs/heads/main.
        h0 = home.commit_entries(self.git_dir, None, {"a.json": b"1"})
        subprocess.run(["git", "--git-dir", self.git_dir, "update-ref", "refs/heads/main", h0],
                       check=True, capture_output=True)
        subprocess.run(["git", "--git-dir", self.git_dir, "symbolic-ref", home.HOME_REF, "refs/heads/main"],
                       check=True, capture_output=True)
        before = subprocess.run(["git", "--git-dir", self.git_dir, "rev-parse", "refs/heads/main"],
                                capture_output=True, text=True).stdout.strip()
        try:
            home.commit_entries(self.git_dir, home.read_head(self.git_dir), {"b.json": b"2"})
        except errors.FoundationError:
            pass  # may fail closed; the invariant asserted is that the branch is untouched
        after = subprocess.run(["git", "--git-dir", self.git_dir, "rev-parse", "refs/heads/main"],
                               capture_output=True, text=True).stdout.strip()
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
