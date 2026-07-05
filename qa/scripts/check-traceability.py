#!/usr/bin/env python3
"""Verify that every PRD acceptance criterion maps to a QA test case."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


AC_RE = re.compile(r"\b(?:[A-Z][A-Z0-9]*-)*AC-\d+(?:[-.]\d+)*\b", re.IGNORECASE)
TC_RE = re.compile(r"\bTC-[A-Z0-9]+(?:[-.]\d+)*\b", re.IGNORECASE)


def read(path: Path) -> str:
    if not path.is_file():
        raise ValueError(f"file not found: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def ids(pattern: re.Pattern[str], text: str) -> set[str]:
    return {match.group(0).upper() for match in pattern.finditer(text)}


def mapped_acs(qa_plan: str) -> set[str]:
    mapped: set[str] = set()
    for line in qa_plan.splitlines():
        if not line.lstrip().startswith("|"):
            continue
        if TC_RE.search(line):
            mapped.update(ids(AC_RE, line))
    return mapped


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prd", type=Path, required=True)
    parser.add_argument("--qa-plan", type=Path, required=True)
    args = parser.parse_args()

    try:
        prd_acs = ids(AC_RE, read(args.prd))
        qa_text = read(args.qa_plan)
    except (OSError, ValueError) as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2

    if not prd_acs:
        print("FAIL PRD contains no machine-readable AC IDs", file=sys.stderr)
        return 1

    mapped = mapped_acs(qa_text)
    missing = sorted(prd_acs - mapped)
    extra = sorted(mapped - prd_acs)
    print(f"AC total={len(prd_acs)} mapped={len(prd_acs) - len(missing)}")
    if extra:
        print(f"WARN QA mappings absent from PRD: {', '.join(extra)}")
    if missing:
        print(f"FAIL unmapped AC: {', '.join(missing)}", file=sys.stderr)
        return 1
    print("PASS AC traceability complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
