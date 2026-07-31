import subprocess
import tempfile
import unittest

from tests.py import factory


class TestFactory(unittest.TestCase):
    def test_make_repo_isolated_committed_and_cleaned(self):
        with factory.make_repo({"README.md": "hi\n"}) as fx:
            self.assertTrue((fx.path / ".git").is_dir())
            self.assertEqual((fx.path / "README.md").read_text(encoding="utf-8"), "hi\n")
            rc = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=str(fx.path), capture_output=True
            )
            self.assertEqual(rc.returncode, 0)
        self.assertFalse(fx.path.exists())  # deterministic cleanup

    def test_fixture_lives_under_tempdir_not_worktree(self):
        with factory.make_repo() as fx:
            self.assertTrue(str(fx.path).startswith(tempfile.gettempdir()))

    def test_make_consuming_repo_has_manifest(self):
        with factory.make_consuming_repo() as fx:
            self.assertTrue((fx.path / ".agent" / "project-manifest.md").is_file())

    def test_inject_missing_file(self):
        with factory.make_repo({"a.txt": "x\n"}) as fx:
            factory.inject_missing_file(fx, "a.txt")
            self.assertFalse((fx.path / "a.txt").exists())

    def test_inject_broken_git_makes_git_fail(self):
        with factory.make_repo() as fx:
            factory.inject_broken_git(fx)
            rc = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=str(fx.path), capture_output=True
            )
            self.assertNotEqual(rc.returncode, 0)


if __name__ == "__main__":
    unittest.main()
