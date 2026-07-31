"""S7 — thin CLI (spec Files cli.py; AC-009 Foundation-side negatives).

CLI is a thin wrapper over core: closed JSON out, typed exit codes, no
aggregate parsing. AC-009 negatives are verified structurally: no activation
command exists, and the publish receipt schema carries no candidate/
parent-revision fields.
"""

import base64
import contextlib
import hashlib
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import cli, home


def _make_git(prefix):
    d = tempfile.mkdtemp(prefix=prefix)
    for args in (["init", "-q"], ["config", "user.email", "t@e"], ["config", "user.name", "t"]):
        subprocess.run(["git", "-C", d, *args], check=True, capture_output=True)
    return d, os.path.join(d, ".git")


def _commit(work, rel, content):
    with open(os.path.join(work, rel), "w", encoding="utf-8") as fh:
        fh.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True, capture_output=True)
    subprocess.run(["git", "-C", work, "commit", "-q", "-m", "x"], check=True, capture_output=True)
    oid = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
    return oid, hashlib.sha256(content.encode()).hexdigest()


def _run_cli(argv):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = cli.main(argv)
    out = buf.getvalue().strip()
    return rc, (json.loads(out) if out else None)


class CliTest(unittest.TestCase):
    def setUp(self):
        self.hw, self.home = _make_git("fdn-cli-home-")
        self.aw, self.a_git = _make_git("fdn-cli-repoA-")
        self.addCleanup(shutil.rmtree, self.hw, ignore_errors=True)
        self.addCleanup(shutil.rmtree, self.aw, ignore_errors=True)
        os.makedirs(os.path.join(self.hw, ".agent"), exist_ok=True)
        self.config = os.path.join(self.hw, ".agent", "artifact-home.json")
        with open(self.config, "w", encoding="utf-8") as fh:
            json.dump({"repo_id": "home", "path": ".git"}, fh)

    def test_unknown_command_typed_exit(self):
        rc, out = _run_cli(["bogus", "--home", self.home])
        self.assertEqual(rc, 2)
        self.assertEqual(out["error"], "SCHEMA_ERROR")

    def test_no_activation_command(self):
        # AC-009: Foundation has no activation/bind operation.
        for cmd in ("activate", "bind", "activation"):
            rc, out = _run_cli([cmd, "--home", self.home])
            self.assertEqual(rc, 2)
            self.assertIn("error", out)

    def test_roundtrip_and_receipt_shape(self):
        rc, _ = _run_cli([
            "register",
            "--home-config",
            self.config,
            "--repo-id",
            "repoA",
            "--locator",
            self.a_git,
        ])
        self.assertEqual(rc, 0)
        oid, dg = _commit(self.aw, "a.md", "hello\n")
        ref = json.dumps({"repo_id": "repoA", "commit_oid": oid, "path": "a.md", "digest": dg, "artifact_kind": "prd"})
        rev = home.read_head(self.home)
        rc, out = _run_cli([
            "publish",
            "--home-config",
            self.config,
            "--ref",
            ref,
            "--expected",
            rev,
        ])
        self.assertEqual(rc, 0)
        receipt = out["receipt"]
        # AC-009 negative: no consumer activation fields in the publish receipt.
        for banned in ("candidate", "parent_revision", "parent", "activation", "consumer_revision"):
            self.assertNotIn(banned, receipt)
        self.assertEqual(receipt["kind"], "publish")

        rc, out = _run_cli(["resolve", "--home-config", self.config, "--ref", ref])
        self.assertEqual(rc, 0)
        self.assertEqual(base64.b64decode(out["content_b64"]), b"hello\n")

    def test_home_config_resolution(self):
        # --home-config resolves the home via the {repo_id, path} locator (FR-001, #2).
        rc, out = _run_cli([
            "register",
            "--home-config",
            self.config,
            "--repo-id",
            "repoA",
            "--locator",
            self.a_git,
        ])
        self.assertEqual(rc, 0)
        self.assertTrue(out["ok"])
        # disabled home (no config file) fails closed
        rc, out = _run_cli(["register", "--home-config", os.path.join(self.hw, "none.json"),
                            "--repo-id", "repoA", "--locator", self.a_git])
        self.assertEqual(rc, 2)
        self.assertEqual(out["error"], "HOME_ERROR")

    def test_raw_home_and_caller_collection_are_not_public_cli_inputs(self):
        rc, out = _run_cli([
            "register",
            "--home",
            self.home,
            "--repo-id",
            "repoA",
            "--locator",
            self.a_git,
        ])
        self.assertEqual(rc, 2)
        self.assertEqual(out["error"], "SCHEMA_ERROR")

        rc, out = _run_cli([
            "register",
            "--home-config",
            self.config,
            "--collection",
            "caller/chosen",
            "--repo-id",
            "repoA",
            "--locator",
            self.a_git,
        ])
        self.assertEqual(rc, 2)
        self.assertEqual(out["error"], "SCHEMA_ERROR")

    def test_resolve_unpublished_typed_fact(self):
        _run_cli([
            "register",
            "--home-config",
            self.config,
            "--repo-id",
            "repoA",
            "--locator",
            self.a_git,
        ])
        oid, dg = _commit(self.aw, "a.md", "x\n")
        ref = json.dumps({"repo_id": "repoA", "commit_oid": oid, "path": "a.md", "digest": dg, "artifact_kind": "prd"})
        rc, out = _run_cli(["resolve", "--home-config", self.config, "--ref", ref])
        self.assertEqual(rc, 2)
        self.assertEqual(out["unresolvable"], "ref-unpublished")


if __name__ == "__main__":
    unittest.main()
