"""S2 — Git object access (spec D-007, FR-005, ERR-004).

Reads bytes from a specific Git OID's tree (never the worktree/HEAD),
re-verifies sha256, validates repo-relative paths before touching git.
Uses real temp git repos as the independent oracle.
"""

import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import errors, gitobj


def _make_git_repo():
    work = tempfile.mkdtemp(prefix="fdn-git-")

    def run(*args):
        return subprocess.run(
            ["git", "-C", work, *args], check=True, capture_output=True, text=True
        )

    run("init", "-q")
    run("config", "user.email", "t@example.com")
    run("config", "user.name", "t")
    return work, run


def _commit_file(work, run, rel, content):
    abspath = os.path.join(work, rel)
    os.makedirs(os.path.dirname(abspath), exist_ok=True) if os.path.dirname(rel) else None
    with open(abspath, "w", encoding="utf-8") as fh:
        fh.write(content)
    run("add", rel)
    run("commit", "-q", "-m", "add " + rel)
    oid = run("rev-parse", "HEAD").stdout.strip()
    return oid


class TestGitObj(unittest.TestCase):
    def setUp(self):
        self.work, self.run = _make_git_repo()
        self.git_dir = os.path.join(self.work, ".git")
        self.addCleanup(shutil.rmtree, self.work, ignore_errors=True)

    def test_read_blob_from_oid(self):
        oid = _commit_file(self.work, self.run, "src/app.py", "print('hi')\n")
        data = gitobj.read_blob(self.git_dir, oid, "src/app.py")
        self.assertEqual(data, b"print('hi')\n")

    def test_digest_is_sha256_of_blob_bytes(self):
        content = "secret = 1\n"
        oid = _commit_file(self.work, self.run, "a.py", content)
        data = gitobj.read_blob(self.git_dir, oid, "a.py")
        self.assertEqual(
            gitobj.blob_sha256(data), hashlib.sha256(content.encode()).hexdigest()
        )

    def test_resolve_verified_ok(self):
        content = "x=1\n"
        oid = _commit_file(self.work, self.run, "a.py", content)
        digest = hashlib.sha256(content.encode()).hexdigest()
        data = gitobj.resolve_verified(self.git_dir, oid, "a.py", digest)
        self.assertEqual(data, content.encode())

    def test_resolve_verified_digest_mismatch_fails_closed(self):
        oid = _commit_file(self.work, self.run, "a.py", "x=1\n")
        with self.assertRaises(errors.Unresolvable) as ctx:
            gitobj.resolve_verified(self.git_dir, oid, "a.py", "0" * 64)
        self.assertEqual(ctx.exception.reason, "digest-unverifiable")

    def test_object_missing_fails_closed(self):
        _commit_file(self.work, self.run, "a.py", "x=1\n")
        with self.assertRaises(errors.Unresolvable) as ctx:
            gitobj.read_blob(self.git_dir, "b" * 40, "a.py")
        self.assertEqual(ctx.exception.reason, "object-missing")

    def test_trailing_newline_oid_rejected(self):
        # A trailing-newline alias must not be a distinct valid OID (fullmatch,
        # not match): rejected before any git call.
        oid = _commit_file(self.work, self.run, "a.py", "x=1\n")
        with self.assertRaises(errors.Unresolvable) as ctx:
            gitobj.read_blob(self.git_dir, oid + "\n", "a.py")
        self.assertEqual(ctx.exception.reason, "object-missing")

    def test_annotated_tag_oid_rejected(self):
        # #10b: commit_oid must name a commit; an annotated-tag OID (different OID,
        # same snapshot) is not a valid commit identity.
        oid = _commit_file(self.work, self.run, "a.py", "x=1\n")
        self.run("tag", "-a", "v1", "-m", "t")
        tagoid = self.run("rev-parse", "v1").stdout.strip()
        self.assertNotEqual(tagoid, oid)
        with self.assertRaises(errors.Unresolvable) as ctx:
            gitobj.read_blob(self.git_dir, tagoid, "a.py")
        self.assertEqual(ctx.exception.reason, "object-missing")

    def test_missing_path_in_tree_fails_closed(self):
        oid = _commit_file(self.work, self.run, "a.py", "x=1\n")
        with self.assertRaises(errors.Unresolvable) as ctx:
            gitobj.read_blob(self.git_dir, oid, "nope.py")
        self.assertEqual(ctx.exception.reason, "object-missing")

    def test_path_escape_rejected_before_git(self):
        oid = _commit_file(self.work, self.run, "a.py", "x=1\n")
        for bad in ("../etc/passwd", "/etc/passwd", "a/../../b", ":(top)a"):
            with self.subTest(path=bad):
                with self.assertRaises(errors.Unresolvable) as ctx:
                    gitobj.read_blob(self.git_dir, oid, bad)
                self.assertEqual(ctx.exception.reason, "path-escape")

    def test_reads_committed_bytes_not_worktree(self):
        content = "committed\n"
        oid = _commit_file(self.work, self.run, "a.py", content)
        # Mutate the worktree after commit; resolve must still return committed bytes.
        with open(os.path.join(self.work, "a.py"), "w", encoding="utf-8") as fh:
            fh.write("TAMPERED\n")
        data = gitobj.read_blob(self.git_dir, oid, "a.py")
        self.assertEqual(data, content.encode())


if __name__ == "__main__":
    unittest.main()
