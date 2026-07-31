"""B1 — home locator resolution (spec AC-001/AC-003, ERR-005, CH-5, #2/D-011).

Home identity = stable repo_id + repo-relative path. The home resolves to
<anchor repo toplevel>/<path>, where the anchor is the git repo that contains the
locator file (deterministic — not cwd, not auto-search, not a hardcoded global path).
Absent config = disabled (AC-003). A global/absolute-path form, split-brain, path
escape, or unresolvable path fails closed with HOME_ERROR.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import errors, homelocator


def _make_git(prefix):
    d = tempfile.mkdtemp(prefix=prefix)
    subprocess.run(["git", "-C", d, "init", "-q"], check=True, capture_output=True)
    return d


class HomeLocatorTest(unittest.TestCase):
    def setUp(self):
        self.anchor = _make_git("fdn-loc-anchor-")
        self.addCleanup(shutil.rmtree, self.anchor, ignore_errors=True)
        os.makedirs(os.path.join(self.anchor, ".agent"), exist_ok=True)
        self.config = os.path.join(self.anchor, ".agent", "artifact-home.json")

    def _write(self, obj):
        with open(self.config, "w", encoding="utf-8") as fh:
            json.dump(obj, fh)

    def _raises_home_error(self):
        with self.assertRaises(errors.FoundationError) as ctx:
            homelocator.resolve_home(self.config)
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_absent_config_is_disabled(self):
        # AC-003: no locator => disabled, no error, no auto-create.
        self.assertIsNone(homelocator.resolve_home(self.config))

    def test_require_home_on_disabled_fails_closed(self):
        with self.assertRaises(errors.FoundationError) as ctx:
            homelocator.require_home(self.config)
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_repo_relative_identity_resolves(self):
        # {repo_id, path} with path=".git" -> the anchor repo's own git dir.
        self._write({"repo_id": "anchor-repo", "path": ".git"})
        resolved = homelocator.resolve_home(self.config)
        self.assertEqual(os.path.realpath(resolved),
                         os.path.realpath(os.path.join(self.anchor, ".git")))
        location = homelocator.resolve_home_location(self.config)
        self.assertEqual(location["collection_identity"], "anchor-repo/.git")
        self.assertEqual(os.path.realpath(location["git_dir"]), os.path.realpath(resolved))

    def test_global_absolute_path_form_rejected(self):
        # #2 / TC-B01: the old {home_git_dir: <absolute>} form is not a valid identity.
        self._write({"home_git_dir": os.path.join(self.anchor, ".git")})
        self._raises_home_error()

    def test_absolute_path_value_rejected(self):
        self._write({"repo_id": "r", "path": os.path.join(self.anchor, ".git")})
        self._raises_home_error()

    def test_parent_escape_path_rejected(self):
        self._write({"repo_id": "r", "path": "../escape/.git"})
        self._raises_home_error()

    def test_symlink_escape_path_rejected(self):
        outside = _make_git("fdn-loc-outside-")
        self.addCleanup(shutil.rmtree, outside, ignore_errors=True)
        os.symlink(outside, os.path.join(self.anchor, "escaped-home"))
        self._write({"repo_id": "r", "path": "escaped-home/.git"})
        self._raises_home_error()

    def test_unresolvable_repo_relative_path_fails_closed(self):
        self._write({"repo_id": "r", "path": "nope/.git"})
        self._raises_home_error()

    def test_split_brain_multiple_homes_fails_closed(self):
        self._write(["/home/a/.git", "/home/b/.git"])
        self._raises_home_error()

    def test_extra_keys_fail_closed(self):
        self._write({"repo_id": "r", "path": ".git", "second": "x"})
        self._raises_home_error()

    def test_duplicate_key_split_brain_fails_closed(self):
        with open(self.config, "w", encoding="utf-8") as fh:
            fh.write('{"repo_id": "a", "repo_id": "b", "path": ".git"}')
        self._raises_home_error()

    def test_locator_file_not_inside_repo_fails_closed(self):
        tmp = tempfile.mkdtemp(prefix="fdn-loc-norepo-")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        cfg = os.path.join(tmp, "artifact-home.json")
        with open(cfg, "w", encoding="utf-8") as fh:
            json.dump({"repo_id": "r", "path": ".git"}, fh)
        with self.assertRaises(errors.FoundationError) as ctx:
            homelocator.resolve_home(cfg)
        self.assertEqual(ctx.exception.code, errors.HOME_ERROR)

    def test_malformed_json_fails_closed(self):
        with open(self.config, "w", encoding="utf-8") as fh:
            fh.write("{not json")
        self._raises_home_error()


if __name__ == "__main__":
    unittest.main()
