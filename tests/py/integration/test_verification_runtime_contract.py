"""Behavioural contracts for the test watchdog and run-bounded pipe isolation."""

import os
import pathlib
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest


REPO = pathlib.Path(__file__).resolve().parents[3]
TEST_WATCHDOG = REPO / "tests" / "bootstrap" / "lib" / "test-watchdog.py"
RUN_BOUNDED = REPO / "security" / "scripts" / "run-bounded.py"
DIRECT_PIPE_WATCHDOG_SECONDS = 30

ESCAPED_CHILD = r"""
import os
import time
from pathlib import Path

Path(os.environ["ESCAPED_PID"]).write_text(str(os.getpid()), encoding="utf-8")
Path(os.environ["ESCAPED_READY"]).write_text("ready", encoding="utf-8")
release = Path(os.environ["ESCAPED_RELEASE"])
while not release.exists():
    time.sleep(0.01)
"""

DIRECT_PARENT = r"""
import os
import subprocess
import sys
import time
from pathlib import Path

subprocess.Popen(
    [sys.executable, "-c", os.environ["ESCAPED_CHILD"]],
    start_new_session=True,
)
ready = Path(os.environ["ESCAPED_READY"])
while not ready.exists():
    time.sleep(0.01)
"""

NON_ISOLATING_RUNNER = r"""
import subprocess
import sys

args = sys.argv[2:]
if args and args[0] == "--stdin":
    args = args[1:]
raise SystemExit(subprocess.run(args).returncode)
"""

PIPE_PRODUCER = r"""
import os
import sys
from pathlib import Path

sys.stdout.buffer.write(b"x" * (2 * 1024 * 1024))
sys.stdout.buffer.flush()
Path(os.environ["PRODUCER_DONE"]).write_text("done", encoding="utf-8")
"""


class TestVerificationRuntimeContract(unittest.TestCase):
    @staticmethod
    def _wait_until(predicate, label):
        deadline = time.monotonic() + DIRECT_PIPE_WATCHDOG_SECONDS
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.01)
        raise AssertionError(f"test watchdog expired while waiting for {label}")

    @staticmethod
    def _stop_process(process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

    @staticmethod
    def _release_escaped_child(release, pid_file):
        release.touch()
        if not pid_file.exists():
            return
        try:
            pid = int(pid_file.read_text(encoding="utf-8"))
        except ValueError:
            return
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            time.sleep(0.01)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    @staticmethod
    def _write_mutant_runner(directory):
        mutant = directory / "non-isolating-runner.py"
        mutant.write_text(NON_ISOLATING_RUNNER, encoding="utf-8")
        return mutant

    def _escaped_environment(self, directory):
        directory.mkdir()
        ready = directory / "ready"
        release = directory / "release"
        pid_file = directory / "pid"
        environment = dict(os.environ)
        environment.update(
            {
                "ESCAPED_CHILD": ESCAPED_CHILD,
                "ESCAPED_READY": str(ready),
                "ESCAPED_RELEASE": str(release),
                "ESCAPED_PID": str(pid_file),
            }
        )
        return environment, ready, release, pid_file

    def _output_pipe_reaches_eof(self, runner, directory):
        environment, ready, release, pid_file = self._escaped_environment(directory)
        process = subprocess.Popen(
            [
                sys.executable,
                str(runner),
                "20",
                sys.executable,
                "-c",
                DIRECT_PARENT,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        try:
            self._wait_until(ready.exists, "escaped output child readiness")
            self._wait_until(
                lambda: process.poll() is not None,
                "the direct output runner process",
            )
            readable, _, _ = select.select([process.stdout], [], [], 0)
            self.last_runner_returncode = process.returncode
            return bool(readable) and os.read(process.stdout.fileno(), 1) == b""
        finally:
            self._release_escaped_child(release, pid_file)
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                self._stop_process(process)

    def _producer_finishes_before_escaped_input_child(self, runner, directory):
        environment, ready, release, pid_file = self._escaped_environment(directory)
        producer_done = directory / "producer-done"
        producer_environment = dict(os.environ)
        producer_environment["PRODUCER_DONE"] = str(producer_done)
        producer = subprocess.Popen(
            [sys.executable, "-c", PIPE_PRODUCER],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=producer_environment,
        )
        process = subprocess.Popen(
            [
                sys.executable,
                str(runner),
                "20",
                "--stdin",
                sys.executable,
                "-c",
                DIRECT_PARENT,
            ],
            stdin=producer.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        producer.stdout.close()
        try:
            self._wait_until(ready.exists, "escaped input child readiness")
            return producer_done.exists()
        finally:
            self._release_escaped_child(release, pid_file)
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                self._stop_process(process)
            self.last_runner_returncode = process.returncode
            self._stop_process(producer)

    def test_timeout_fixtures_use_an_independent_test_watchdog(self):
        self.assertTrue(
            TEST_WATCHDOG.is_file(),
            "timeout fixtures need a test-only watchdog independent from run-bounded.py",
        )
        watchdog_source = TEST_WATCHDOG.read_text()
        self.assertNotIn("run-bounded.py", watchdog_source)
        timed = subprocess.run(
            [
                sys.executable,
                str(TEST_WATCHDOG),
                "0.1",
                sys.executable,
                "-c",
                "import time; time.sleep(5)",
            ],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        self.assertEqual(124, timed.returncode)
        self.assertIn("test-watchdog: timeout", timed.stderr)
        completed = subprocess.run(
            [
                sys.executable,
                str(TEST_WATCHDOG),
                "5",
                sys.executable,
                "-c",
                "import sys; print('watchdog-marker'); sys.exit(7)",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        self.assertEqual(7, completed.returncode)
        self.assertIn("watchdog-marker", completed.stdout)

    def test_direct_output_pipe_is_not_retained_by_escaped_descendant(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = pathlib.Path(raw_directory)
            mutant = self._write_mutant_runner(directory)
            self.assertTrue(
                self._output_pipe_reaches_eof(RUN_BOUNDED, directory / "real-output")
            )
            self.assertEqual(0, self.last_runner_returncode)
            self.assertFalse(
                self._output_pipe_reaches_eof(mutant, directory / "mutant-output")
            )

    def test_direct_input_pipe_is_not_retained_by_escaped_descendant(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = pathlib.Path(raw_directory)
            mutant = self._write_mutant_runner(directory)
            self.assertTrue(
                self._producer_finishes_before_escaped_input_child(
                    RUN_BOUNDED,
                    directory / "real-input",
                )
            )
            self.assertEqual(0, self.last_runner_returncode)
            self.assertFalse(
                self._producer_finishes_before_escaped_input_child(
                    mutant,
                    directory / "mutant-input",
                )
            )


if __name__ == "__main__":
    unittest.main()
