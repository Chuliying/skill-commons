#!/usr/bin/env python3
"""Test-only subprocess watchdog independent from the production bounded runner."""

from __future__ import annotations

import math
import os
import signal
import subprocess
import sys
import tempfile


TIMEOUT_EXIT = 124
TERMINATION_GRACE_SECONDS = 0.25


def parse_timeout(raw: str) -> float:
    try:
        value = float(raw)
    except ValueError as exc:
        raise ValueError(f"invalid timeout: {raw!r}") from exc
    if not math.isfinite(value) or value <= 0:
        raise ValueError(f"timeout must be a positive finite number: {raw!r}")
    return value


def stop_process_group(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=TERMINATION_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    if process.poll() is None:
        process.wait()


def replay(source: object, destination: object) -> None:
    source.flush()
    source.seek(0)
    while True:
        chunk = source.read(64 * 1024)
        if not chunk:
            break
        destination.write(chunk)
    destination.flush()


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: test-watchdog.py <seconds> <command> [args...]", file=sys.stderr)
        return 2
    try:
        timeout = parse_timeout(sys.argv[1])
    except ValueError as exc:
        print(f"test-watchdog: {exc}", file=sys.stderr)
        return 2

    command = sys.argv[2:]
    with tempfile.TemporaryFile() as child_stdout, tempfile.TemporaryFile() as child_stderr:
        try:
            process = subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=child_stdout,
                stderr=child_stderr,
                start_new_session=True,
            )
        except OSError as exc:
            print(f"test-watchdog: cannot execute {command[0]}: {exc}", file=sys.stderr)
            return 125

        timed_out = False
        try:
            returncode = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            stop_process_group(process)
            returncode = TIMEOUT_EXIT

        replay(child_stdout, sys.stdout.buffer)
        replay(child_stderr, sys.stderr.buffer)
        if timed_out:
            print(
                f"test-watchdog: timeout after {timeout:g}s: {command[0]}",
                file=sys.stderr,
            )
            return TIMEOUT_EXIT
        if returncode < 0:
            return min(255, 128 + abs(returncode))
        return returncode


if __name__ == "__main__":
    raise SystemExit(main())
