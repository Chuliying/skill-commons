#!/usr/bin/env python3
"""Validate the canonical Spec Selected Seam and an optional QA reference."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


SPEC_FIELDS = (
    "Seam ID",
    "Selected boundary",
    "Repository evidence",
    "Lower-seam rationale",
    "Residual lower-level checks",
    "Reliability and execution cost",
)
QA_FIELDS = ("Spec seam ID", "Spec reference")
SEAM_ID_RE = re.compile(r"^SEAM-[A-Z0-9][A-Z0-9-]*$", re.IGNORECASE)


def read(path: Path) -> str:
    if not path.is_file():
        raise ValueError(f"file not found: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def selected_seam(text: str) -> str:
    match = re.search(r"^## Selected Seam\s*$", text, flags=re.MULTILINE)
    if not match:
        raise ValueError("missing ## Selected Seam")
    tail = text[match.end() :]
    end = re.search(r"^## ", tail, flags=re.MULTILINE)
    return tail[: end.start()] if end else tail


def table_fields(section: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in section.splitlines():
        if not line.strip().startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 2 or cells[0] in {"Field", "---"} or set(cells[0]) == {"-"}:
            continue
        fields[cells[0]] = cells[1]
    return fields


def complete(fields: dict[str, str], required: tuple[str, ...]) -> list[str]:
    errors: list[str] = []
    for name in required:
        value = fields.get(name, "").strip()
        if not value:
            errors.append(f"missing Selected Seam field: {name}")
        elif "[" in value or "]" in value or value.upper() in {"TBD", "TODO"}:
            errors.append(f"placeholder Selected Seam field: {name}")
    return errors


def validate_spec_reference(reference: str, qa_plan: Path, spec: Path) -> list[str]:
    path_text, separator, anchor = reference.partition("#")
    if separator != "#" or anchor.lower() != "selected-seam":
        return ["QA Spec reference must use the #selected-seam anchor"]
    relative = Path(path_text)
    if relative.is_absolute() or ".." in relative.parts:
        return ["QA Spec reference must be a work-item-relative path"]
    if (qa_plan.parent / relative).resolve() != spec.resolve():
        return ["QA Spec reference does not resolve to the supplied Spec"]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, required=True)
    parser.add_argument("--qa-plan", type=Path)
    args = parser.parse_args()

    try:
        spec_fields = table_fields(selected_seam(read(args.spec)))
        errors = complete(spec_fields, SPEC_FIELDS)
        seam_id = spec_fields.get("Seam ID", "")
        if seam_id and not SEAM_ID_RE.fullmatch(seam_id):
            errors.append("invalid Seam ID; expected SEAM-<stable-id>")
        if args.qa_plan:
            qa_fields = table_fields(selected_seam(read(args.qa_plan)))
            errors.extend(complete(qa_fields, QA_FIELDS))
            if qa_fields.get("Spec seam ID") != seam_id:
                errors.append("QA Spec seam ID does not match Spec Seam ID")
            reference = qa_fields.get("Spec reference", "")
            if reference and "[" not in reference and "]" not in reference:
                errors.extend(validate_spec_reference(reference, args.qa_plan, args.spec))
    except (OSError, ValueError) as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2

    if errors:
        for error in errors:
            print(f"FAIL {error}", file=sys.stderr)
        return 1
    print(f"PASS Selected Seam complete: {seam_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
