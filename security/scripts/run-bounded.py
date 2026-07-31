#!/usr/bin/env python3
"""Run one command with a portable timeout and normalized failure codes."""

from __future__ import annotations

import math
import os
import signal
import subprocess
import sys
import tempfile
import time


TIMEOUT_EXIT = 124
EXEC_ERROR_EXIT = 125
NOT_EXECUTABLE_EXIT = 126
NOT_FOUND_EXIT = 127
TERMINATION_GRACE_SECONDS = 0.25
HEALTH_SENTINEL = "run-bounded:v1"


class InputTimeout(Exception):
    """The explicit stdin channel did not reach EOF before the shared deadline."""


def parse_timeout(raw: str) -> float:
    try:
        value = float(raw)
    except ValueError as exc:
        raise ValueError(f"invalid timeout: {raw!r}") from exc
    if not math.isfinite(value) or value <= 0:
        raise ValueError(f"timeout must be a positive finite number: {raw!r}")
    return value


def terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return

    try:
        process.wait(timeout=TERMINATION_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        pass

    # The group may still contain descendants after the direct child exits. Always
    # close the grace period with SIGKILL; waiting only for the parent would leak any
    # descendant that ignored SIGTERM.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    if process.poll() is None:
        process.wait()


def terminate_remaining_process_group(process_group_id: int) -> None:
    """Close descendants left behind after the direct child has exited."""
    try:
        os.killpg(process_group_id, 0)
    except ProcessLookupError:
        return

    try:
        os.killpg(process_group_id, signal.SIGTERM)
    except ProcessLookupError:
        return

    deadline = time.monotonic() + TERMINATION_GRACE_SECONDS
    while time.monotonic() < deadline:
        try:
            os.killpg(process_group_id, 0)
        except ProcessLookupError:
            return
        time.sleep(0.01)

    try:
        os.killpg(process_group_id, signal.SIGKILL)
    except ProcessLookupError:
        pass


def normalized_returncode(returncode: int) -> int:
    if returncode >= 0:
        return returncode
    return min(255, 128 + abs(returncode))


def replay_output(source: object, destination: object) -> None:
    """Replay a regular-file snapshot without inheriting a caller pipe in children."""
    source.flush()
    source.seek(0)
    while True:
        chunk = source.read(64 * 1024)
        if not chunk:
            break
        destination.write(chunk)
    destination.flush()


def spool_stdin(destination: object, deadline: float) -> None:
    """Copy explicit stdin to a regular file under the same operation deadline."""
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise InputTimeout

    def raise_input_timeout(_signum: int, _frame: object) -> None:
        raise InputTimeout

    previous_handler = signal.signal(signal.SIGALRM, raise_input_timeout)
    signal.setitimer(signal.ITIMER_REAL, remaining)
    try:
        while True:
            chunk = sys.stdin.buffer.read(64 * 1024)
            if not chunk:
                break
            destination.write(chunk)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_handler)
    destination.flush()
    destination.seek(0)


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args == ["--health-check"]:
        print(HEALTH_SENTINEL)
        return 0
    if len(args) == 3 and args[0] == "--min-timeout":
        try:
            first = parse_timeout(args[1])
            second = parse_timeout(args[2])
        except ValueError as exc:
            print(f"run-bounded: {exc}", file=sys.stderr)
            return 2
        print(f"{min(first, second):g}")
        return 0
    if len(args) < 2:
        print(
            "usage: run-bounded.py <seconds> [--stdin] <command> [args...]",
            file=sys.stderr,
        )
        return 2

    try:
        timeout = parse_timeout(args[0])
    except ValueError as exc:
        print(f"run-bounded: {exc}", file=sys.stderr)
        return 2

    command = args[1:]
    consume_stdin = bool(command and command[0] == "--stdin")
    if consume_stdin:
        command = command[1:]
    if not command:
        print("run-bounded: command is required", file=sys.stderr)
        return 2

    deadline = time.monotonic() + timeout
    child_stdin = None
    try:
        if consume_stdin:
            child_stdin = tempfile.TemporaryFile()
            try:
                spool_stdin(child_stdin, deadline)
            except InputTimeout:
                print(
                    f"run-bounded: timeout after {timeout:g}s while reading stdin",
                    file=sys.stderr,
                )
                return TIMEOUT_EXIT

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            print(
                f"run-bounded: timeout after {timeout:g}s before command start",
                file=sys.stderr,
            )
            return TIMEOUT_EXIT

        # Child output never inherits the caller's pipe. A descendant may call setsid()
        # and escape our process group, but it can then hold only these unlinked regular
        # files -- never the command-substitution pipe whose lifetime defines the gate.
        with tempfile.TemporaryFile() as child_stdout, tempfile.TemporaryFile() as child_stderr:
            try:
                process = subprocess.Popen(
                    command,
                    stdin=child_stdin if child_stdin is not None else subprocess.DEVNULL,
                    stdout=child_stdout,
                    stderr=child_stderr,
                    start_new_session=True,
                )
            except FileNotFoundError:
                print(f"run-bounded: command not found: {command[0]}", file=sys.stderr)
                return NOT_FOUND_EXIT
            except PermissionError:
                print(f"run-bounded: command is not executable: {command[0]}", file=sys.stderr)
                return NOT_EXECUTABLE_EXIT
            except OSError as exc:
                print(f"run-bounded: cannot execute {command[0]}: {exc}", file=sys.stderr)
                return EXEC_ERROR_EXIT

            timed_out = False
            try:
                returncode = process.wait(timeout=remaining)
            except subprocess.TimeoutExpired:
                timed_out = True
                terminate_process_group(process)
                returncode = TIMEOUT_EXIT
            else:
                terminate_remaining_process_group(process.pid)

            replay_output(child_stdout, sys.stdout.buffer)
            replay_output(child_stderr, sys.stderr.buffer)
            if timed_out:
                print(
                    f"run-bounded: timeout after {timeout:g}s: {command[0]}",
                    file=sys.stderr,
                )
                return TIMEOUT_EXIT
            return normalized_returncode(returncode)
    except OSError as exc:
        print(f"run-bounded: cannot create bounded output channel: {exc}", file=sys.stderr)
        return EXEC_ERROR_EXIT
    finally:
        if child_stdin is not None:
            child_stdin.close()


if __name__ == "__main__":
    raise SystemExit(main())
