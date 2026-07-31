"""AC-007 / ERR-001/002 + fail-closed pins: verify.sh runner contract via a scoped
sandbox roster (seconds, no real full run -- spec I05 / F1/F4; qa-plan ADV rows).
Covers rc capture, wrapped-suite FAIL propagation, no mid-abort, missing-entry ERROR,
re-entrancy, python ERROR-vs-FAILURE, empty-layer / empty-roster / no-trailing-newline
/ stdin-consuming fail-closed (the false-green paths a runner must not have)."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest
import uuid

REPO = pathlib.Path(__file__).resolve().parents[3]
VERIFY = REPO / "tests" / "verify.sh"


def _run_scoped(roster_text, extra_env=None):
    env = dict(os.environ)
    env.pop("VERIFY_ACTIVE", None)
    if extra_env:
        env.update(extra_env)
    fd, rf = tempfile.mkstemp(suffix=".roster")
    with os.fdopen(fd, "w") as f:
        f.write(roster_text)
    env["VERIFY_ROSTER_FILE"] = rf
    try:
        return subprocess.run(
            ["bash", str(VERIFY)], cwd=str(REPO), capture_output=True, text=True, env=env
        )
    finally:
        os.unlink(rf)


def _fake_suite(dirpath, name, exit_code, body=""):
    p = pathlib.Path(dirpath) / name
    p.write_text(f"#!/usr/bin/env bash\n{body}exit {exit_code}\n")
    p.chmod(0o755)
    return p


class _SandboxLayer:
    """A unique temp python layer under tests/py (so `discover -t .` sees it),
    cleaned up deterministically; unique name avoids parallel-run races."""

    def __init__(self):
        self.name = f"_sbx_{uuid.uuid4().hex[:8]}"
        self.path = REPO / "tests" / "py" / self.name

    def __enter__(self):
        shutil.rmtree(self.path, ignore_errors=True)
        self.path.mkdir()
        (self.path / "__init__.py").write_text("")
        return self

    def write_test(self, body):
        (self.path / "test_case.py").write_text(body)

    def roster_line(self):
        return f"layer {self.name} tests/py/{self.name}\n"

    def __exit__(self, *exc):
        shutil.rmtree(self.path, ignore_errors=True)


class TestVerifyContract(unittest.TestCase):
    def test_bash_rc_captured_and_failure_propagates(self):
        with tempfile.TemporaryDirectory() as d:
            _fake_suite(d, "ok.sh", 0)
            _fake_suite(d, "bad.sh", 1)
            r = _run_scoped(f"suite {d}/ok.sh\nsuite {d}/bad.sh\n")
            self.assertNotEqual(r.returncode, 0)
            self.assertIn(f"SUITE suite:{d}/ok.sh rc=0", r.stdout)
            self.assertIn(f"SUITE suite:{d}/bad.sh rc=1", r.stdout)

    def test_all_entries_reported_no_mid_abort(self):
        with tempfile.TemporaryDirectory() as d:
            _fake_suite(d, "a.sh", 0)
            _fake_suite(d, "b.sh", 1)
            _fake_suite(d, "c.sh", 0)
            r = _run_scoped(f"suite {d}/a.sh\nsuite {d}/b.sh\nsuite {d}/c.sh\n")
            for n in ("a.sh", "b.sh", "c.sh"):
                self.assertIn(f"/{n} rc=", r.stdout)

    def test_missing_roster_entry_is_fail_closed_error(self):
        r = _run_scoped("suite /nonexistent/nope.sh\n")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("ERROR(missing-roster-entry", r.stdout)

    def test_reentrancy_guard_blocks_nested_unscoped(self):
        env = dict(os.environ)
        env["VERIFY_ACTIVE"] = "1"
        env.pop("VERIFY_ROSTER_FILE", None)
        r = subprocess.run(
            ["bash", str(VERIFY)], cwd=str(REPO), capture_output=True, text=True, env=env
        )
        self.assertEqual(r.returncode, 3)
        self.assertIn("re-entrancy", r.stderr)

    def test_python_layer_error_vs_failure_classified(self):
        with _SandboxLayer() as sbx:
            sbx.write_test(
                "import unittest\n"
                "class T(unittest.TestCase):\n"
                "    def test_x(self):\n"
                "        self.assertTrue(False)\n"
            )
            r = _run_scoped(sbx.roster_line())
            self.assertIn(f"layer:{sbx.name}", r.stdout)
            self.assertIn("FAILURE", r.stdout)
            sbx.write_test(
                "import unittest\n"
                "class T(unittest.TestCase):\n"
                "    def setUp(self):\n"
                "        raise RuntimeError('boom')\n"
                "    def test_x(self):\n"
                "        pass\n"
            )
            r2 = _run_scoped(sbx.roster_line())
            self.assertIn(f"layer:{sbx.name} rc=", r2.stdout)
            self.assertIn("ERROR", r2.stdout)

    def test_empty_layer_is_fail_closed(self):
        with _SandboxLayer() as sbx:  # no test_*.py -> empty layer
            r = _run_scoped(sbx.roster_line())
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("empty-layer", r.stdout)

    def test_empty_scoped_roster_is_fail_closed(self):
        r = _run_scoped("")  # 0 entries
        self.assertNotEqual(r.returncode, 0)

    def test_final_line_without_trailing_newline_is_processed(self):
        with tempfile.TemporaryDirectory() as d:
            _fake_suite(d, "bad.sh", 1)
            r = _run_scoped(f"suite {d}/bad.sh")  # no trailing newline
            self.assertIn("/bad.sh rc=1", r.stdout)
            self.assertNotEqual(r.returncode, 0)

    def test_stdin_consuming_suite_does_not_eat_roster(self):
        with tempfile.TemporaryDirectory() as d:
            _fake_suite(d, "greedy.sh", 0, body="cat >/dev/null\n")
            _fake_suite(d, "after.sh", 1)
            r = _run_scoped(f"suite {d}/greedy.sh\nsuite {d}/after.sh\n")
            self.assertIn("/after.sh rc=1", r.stdout)  # after.sh still ran
            self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
