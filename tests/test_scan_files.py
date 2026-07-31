#!/usr/bin/env python3
"""Property-style evals for the scan-files byte/search result contract."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import random
import re
import sys
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
SCAN_FILES_PATH = REPO / "security" / "scripts" / "scan-files.py"
SPEC = importlib.util.spec_from_file_location("scan_files", SCAN_FILES_PATH)
assert SPEC is not None and SPEC.loader is not None
SCAN_FILES = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = SCAN_FILES
SPEC.loader.exec_module(SCAN_FILES)

SEARCH_HEADER = re.compile(r"^scan-files-search:v2:(\d+):(\d+):(\d+)$")
FIXED_BYTES = (0x00, 0x0A, 0x0D, 0x7F, 0x80, 0x9F, 0xE9, 0xFF)
SEEDED_BYTES = tuple(random.Random(0x5EC2).sample(range(256), 24))
BYTE_CORPUS = tuple(dict.fromkeys((*FIXED_BYTES, *SEEDED_BYTES)))


def run_search(mode: str, root: Path) -> tuple[int, str, str]:
    stdout = io.StringIO()
    stderr = io.StringIO()
    args = ["--extensions", "py", mode, str(root)] if mode == "worktree" else [mode, str(root)]
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        rc = SCAN_FILES.main(args)
    return rc, stdout.getvalue(), stderr.getvalue()


def parse_result(rc: int, stdout: str, stderr: str) -> tuple[str | None, tuple[int, int, int] | None, list[str]]:
    if rc != 0:
        return f"rc={rc} stderr={stderr.strip()!r}", None, []
    lines = stdout.splitlines()
    if not lines:
        return "missing search envelope", None, []
    header = SEARCH_HEADER.fullmatch(lines[0])
    if header is None:
        return f"malformed search envelope: {lines[0]!r}", None, lines[1:]
    counts = tuple(int(value) for value in header.groups())
    enumerated, scanned, matches = counts
    records = lines[1:]
    if enumerated != 1 or scanned != enumerated or matches != len(records):
        return f"non-conserving envelope={counts} records={len(records)}", counts, records
    try:
        stdout.encode("ascii")
    except UnicodeEncodeError as exc:
        return f"evidence is not ASCII-safe: {exc}", counts, records
    return None, counts, records


class ScanFilesByteParityTest(unittest.TestCase):
    def evaluate_corpus(self, payload_for_byte, expected_matches: int) -> list[str]:
        failures: list[str] = []
        with tempfile.TemporaryDirectory(prefix="scan-files-bytes-") as temporary:
            root = Path(temporary)
            artifact = root / "artifact.py"
            for value in BYTE_CORPUS:
                artifact.write_bytes(payload_for_byte(value))
                outcomes = {}
                for mode in ("worktree", "staged"):
                    rc, stdout, stderr = run_search(mode, root)
                    error, counts, records = parse_result(rc, stdout, stderr)
                    if error is not None:
                        failures.append(f"byte=0x{value:02x} mode={mode}: {error}")
                        continue
                    outcomes[mode] = (counts, records)
                    if counts is None or counts[2] != expected_matches:
                        failures.append(
                            f"byte=0x{value:02x} mode={mode}: expected matches={expected_matches}, got {counts}"
                        )
                if len(outcomes) == 2 and outcomes["worktree"] != outcomes["staged"]:
                    failures.append(f"byte=0x{value:02x}: worktree/staged outcomes diverged")
        return failures

    def test_secret_candidate_parity_across_arbitrary_bytes(self) -> None:
        failures = self.evaluate_corpus(
            lambda value: b"pass" + b'word = "real' + b'Secret123456"' + bytes([value]) + b"\n",
            expected_matches=1,
        )
        self.assertEqual([], failures, "\n".join(failures[:12]))

    def test_clean_candidate_parity_across_arbitrary_bytes(self) -> None:
        failures = self.evaluate_corpus(
            lambda value: b"x = 1  # caf" + bytes([value]) + b"\n",
            expected_matches=0,
        )
        self.assertEqual([], failures, "\n".join(failures[:12]))


if __name__ == "__main__":
    unittest.main()
