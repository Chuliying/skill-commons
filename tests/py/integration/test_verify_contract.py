"""verify.sh runner contract via a scoped sandbox roster.

The tests stay bounded: they inject tiny Bash/Python fixtures instead of running
the repository roster.  They cover rc capture, retained diagnostics and retry
commands, no mid-abort, missing-entry ERROR, re-entrancy, explicit scope
selection, Python ERROR-vs-FAILURE, empty-layer / empty-roster /
no-trailing-newline / stdin-consuming fail-closed behavior.
"""
import atexit
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest
import uuid

REPO = pathlib.Path(__file__).resolve().parents[3]
VERIFY = REPO / "tests" / "verify.sh"


def _run_scoped(roster_text, extra_env=None, args=None):
    env = dict(os.environ)
    env.pop("VERIFY_ACTIVE", None)
    if extra_env:
        env.update(extra_env)
    fd, rf = tempfile.mkstemp(suffix=".roster")
    with os.fdopen(fd, "w") as f:
        f.write(roster_text)
    env["VERIFY_ROSTER_FILE"] = rf
    try:
        result = subprocess.run(
            ["bash", str(VERIFY), *(args or [])], cwd=str(REPO), capture_output=True, text=True, env=env
        )
        # Failed runs intentionally retain their diagnostics.  Keep them alive
        # for assertions, then clean them at interpreter exit so contract tests
        # do not accumulate /tmp state across repeated focused runs.
        match = re.search(r"^DIAGNOSTICS dir=(.+)$", result.stdout, re.MULTILINE)
        if match:
            atexit.register(shutil.rmtree, match.group(1).strip(), ignore_errors=True)
        return result
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

    def test_failed_bash_suite_replays_complete_diagnostics(self):
        with tempfile.TemporaryDirectory() as d:
            body = (
                "printf 'verify-diagnostic-first\\n'\n"
                "i=0; while [ $i -lt 30 ]; do printf 'noise-%s\\n' \"$i\"; i=$((i + 1)); done\n"
                "printf 'verify-diagnostic-last\\n'\n"
            )
            _fake_suite(d, "diagnostic.sh", 1, body=body)
            r = _run_scoped(f"suite {d}/diagnostic.sh\n")
            output = r.stdout + r.stderr
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("verify-diagnostic-first", output)
            self.assertIn("verify-diagnostic-last", output)

    def test_successful_bash_suite_chatter_stays_suppressed(self):
        with tempfile.TemporaryDirectory() as d:
            _fake_suite(d, "quiet-success.sh", 0, body="printf 'success-chatter\\n'\n")
            r = _run_scoped(f"suite {d}/quiet-success.sh\n")
            self.assertEqual(r.returncode, 0)
            self.assertNotIn("success-chatter", r.stdout + r.stderr)

    def test_release_mode_forces_payload_cache_bypass(self):
        with tempfile.TemporaryDirectory() as d:
            _fake_suite(
                d,
                "release-env.sh",
                0,
                body='[ "${SKILL_COMMONS_VERIFY_NO_CACHE:-0}" = "1" ] || exit 9\n',
            )
            r = _run_scoped(
                f"suite {d}/release-env.sh\n",
                extra_env={"SKILL_COMMONS_VERIFY_NO_CACHE": "0"},
                args=["--release"],
            )
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_local_mode_ignores_ambient_release_cache_bypass(self):
        with tempfile.TemporaryDirectory() as d:
            _fake_suite(
                d,
                "local-env.sh",
                0,
                body='[ "${SKILL_COMMONS_VERIFY_NO_CACHE:-0}" = "0" ] || exit 9\n',
            )
            r = _run_scoped(
                f"suite {d}/local-env.sh\n",
                extra_env={"SKILL_COMMONS_VERIFY_NO_CACHE": "1"},
            )
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_unknown_mode_fails_before_running_roster(self):
        with tempfile.TemporaryDirectory() as d:
            marker = pathlib.Path(d) / "ran"
            _fake_suite(d, "must-not-run.sh", 0, body=f"touch '{marker}'\n")
            r = _run_scoped(
                f"suite {d}/must-not-run.sh\n",
                args=["--unknown-mode"],
            )
            self.assertEqual(r.returncode, 2)
            self.assertFalse(marker.exists())
            self.assertIn("unknown option", r.stderr)

    def test_failed_bash_keeps_stdout_stderr_and_retry_command(self):
        with tempfile.TemporaryDirectory() as d:
            marker = pathlib.Path(d) / "second-run"
            _fake_suite(
                d,
                "diagnostic.sh",
                7,
                body=(
                    "printf 'bash-stdout\\n'\n"
                    "printf 'bash-stderr\\n' >&2\n"
                    f"if [ -e '{marker}' ]; then exit 0; else touch '{marker}'; exit 7; fi\n"
                ),
            )
            r = _run_scoped(f"suite {d}/diagnostic.sh\n")
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("DIAGNOSTICS dir=", r.stdout)
            self.assertIn("RETRY:", r.stdout)
            retry_line = next(line for line in r.stdout.splitlines() if line.startswith("RETRY_ENTRY: "))
            log_dir = pathlib.Path(re.search(r"^DIAGNOSTICS dir=(.+)$", r.stdout, re.MULTILINE).group(1))
            stdout_logs = list(log_dir.glob("*.stdout.log"))
            stderr_logs = list(log_dir.glob("*.stderr.log"))
            self.assertTrue(stdout_logs)
            self.assertTrue(stderr_logs)
            self.assertIn("bash-stdout", "\n".join(p.read_text() for p in stdout_logs))
            self.assertIn("bash-stderr", "\n".join(p.read_text() for p in stderr_logs))
            retry = subprocess.run(
                ["bash", "-c", retry_line.split("RETRY_ENTRY: ", 1)[1]],
                cwd=str(REPO), capture_output=True, text=True,
            )
            self.assertEqual(retry.returncode, 0, retry.stderr)
            self.assertIn("SUMMARY entries=1 errors=0 failures=0 scope=source", retry.stdout)

    def test_failed_python_keeps_stdout_and_stderr(self):
        with _SandboxLayer() as sbx:
            sbx.write_test(
                "import sys, unittest\n"
                "class T(unittest.TestCase):\n"
                "    def test_x(self):\n"
                "        print('python-stdout')\n"
                "        print('python-stderr', file=sys.stderr)\n"
                "        self.assertTrue(False)\n"
            )
            r = _run_scoped(sbx.roster_line())
            self.assertNotEqual(r.returncode, 0)
            log_dir = pathlib.Path(re.search(r"^DIAGNOSTICS dir=(.+)$", r.stdout, re.MULTILINE).group(1))
            self.assertIn("python-stdout", "\n".join(p.read_text() for p in log_dir.glob("*.stdout.log")))
            self.assertIn("python-stderr", "\n".join(p.read_text() for p in log_dir.glob("*.stderr.log")))

    def test_invalid_scope_and_roster_selection_fail_closed(self):
        with tempfile.TemporaryDirectory() as d:
            _fake_suite(d, "quick.sh", 0)
            roster = pathlib.Path(d) / "roster"
            roster.write_text(f"suite {d}/quick.sh\n")
            env = dict(os.environ)
            env.pop("VERIFY_ACTIVE", None)
            env["VERIFY_ROSTER_FILE"] = str(roster)
            # The tiny scoped roster keeps this negative CLI probe bounded on
            # the pre-fix runner, whose parser ignored unknown arguments.
            invalid_scope = subprocess.run(
                ["bash", str(VERIFY), "--scope", "sideways"],
                cwd=str(REPO), capture_output=True, text=True, env=env,
            )
            self.assertNotEqual(invalid_scope.returncode, 0)
            r = _run_scoped("bogus-kind ignored\n")
            self.assertNotEqual(r.returncode, 0)
            public_custom = _run_scoped("suite %s\n" % (d + "/quick.sh"), {"VERIFY_SCOPE": "public"})
            self.assertNotEqual(public_custom.returncode, 0)

    def test_retained_log_directories_are_unique(self):
        with tempfile.TemporaryDirectory() as d:
            _fake_suite(d, "bad.sh", 1)
            first = _run_scoped(f"suite {d}/bad.sh\n")
            second = _run_scoped(f"suite {d}/bad.sh\n")
            first_dir = re.search(r"^DIAGNOSTICS dir=(.+)$", first.stdout, re.MULTILINE).group(1)
            second_dir = re.search(r"^DIAGNOSTICS dir=(.+)$", second.stdout, re.MULTILINE).group(1)
            self.assertNotEqual(first_dir, second_dir)

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

    def test_failed_python_layer_replays_diagnostics(self):
        with _SandboxLayer() as sbx:
            sbx.write_test(
                "import unittest\n"
                "class T(unittest.TestCase):\n"
                "    def test_x(self):\n"
                "        raise RuntimeError('layer-diagnostic-marker')\n"
            )
            r = _run_scoped(sbx.roster_line())
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("layer-diagnostic-marker", r.stdout + r.stderr)

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
