#!/usr/bin/env python3
"""Deterministic PRD shape gate.

Validates that a prd.md conforms to the canonical PRD shape (prd-template.md).
One contract, two roles: the producer's postcondition (to-prd / prd-interview run
it before handoff) and the consumer's precondition (spec runs it on its input PRD).

Structural drift fails (exit 1). Vague-word hits are advisory warnings, not
failures, because they legitimately appear in prose describing a current problem.
The required-heading lists are kept in sync with prd-template.md by
tests/test_gate_automation.sh; the placeholder set is derived from the template
at runtime so the two can never drift.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


# Required section headings by tier. Compared number-agnostically: a leading
# "N. " / "N) " prefix is stripped before matching (prd-field-guide: match by
# name, not number). REQUIRED_* must stay a subset of prd-template.md headings;
# the sync test enforces that.
REQUIRED_CORE = [
    "Follow-ups",
    "Context",
    "Scope",
    "Functional Requirements (FR)",
    "Error Scenarios (ERR)",
    "Acceptance Criteria (AC)",
]
REQUIRED_TEAM = REQUIRED_CORE + [
    "Non-functional Requirements (NFR)",
    "Dependencies & Constraints",
]

# Words Gate 1 already names as unquantified. Advisory only (WARN, never FAIL).
VAGUE_WORDS = ["快速", "適當", "容易", "友善"]

HEADING_RE = re.compile(r"^#{1,6}\s+(.*?)\s*$")
NUM_PREFIX_RE = re.compile(r"^\d+[.)]\s*")
FR_RE = re.compile(r"^#{2,6}\s*FR-\d+", re.MULTILINE)
ERR_RE = re.compile(r"^#{2,6}\s*ERR-\d+", re.MULTILINE)
AC_RE = re.compile(r"^#{2,6}\s*AC-\d+", re.MULTILINE)


def read(path: Path) -> str:
    if not path.is_file():
        raise ValueError(f"file not found: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def headings(text: str) -> list[str]:
    names: list[str] = []
    for line in text.splitlines():
        match = HEADING_RE.match(line)
        if match:
            names.append(NUM_PREFIX_RE.sub("", match.group(1)).strip())
    return names


def gherkin_blocks(text: str) -> list[str]:
    blocks: list[str] = []
    inside = False
    buffer: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not inside and stripped.startswith("```gherkin"):
            inside, buffer = True, []
            continue
        if inside and stripped.startswith("```"):
            blocks.append("\n".join(buffer))
            inside = False
            continue
        if inside:
            buffer.append(line)
    return blocks


def is_given_when_then(block: str) -> bool:
    return all(
        re.search(rf"(?im)^\s*{keyword}\b", block)
        for keyword in ("given", "when", "then")
    )


def bracket_tokens(text: str) -> set[str]:
    """Square-bracket tokens that look like fill-in placeholders, excluding
    markdown checkboxes (`[x]`/`[ ]`), mermaid node labels (`id[Label]`), and
    markdown link labels (`[text](url)`). Applied symmetrically to the template
    (to derive the forbidden set) and to the PRD (to scan), so a mermaid label or
    link in the PRD is never mistaken for an unfilled placeholder."""
    tokens: set[str] = set()
    for match in re.finditer(r"\[([^\]\n]+)\]", text):
        inner = match.group(1).strip()
        if inner in ("", "x", "X"):  # markdown checkbox
            continue
        start, end = match.start(), match.end()
        if start > 0 and text[start - 1].isalnum():  # mermaid node label: id[Label]
            continue
        if end < len(text) and text[end] == "(":  # markdown link label: [text](url)
            continue
        tokens.add(match.group(0))
    return tokens


def template_placeholders(script_dir: Path) -> set[str]:
    """Forbidden placeholder tokens, derived from the canonical template so the
    validator and template never drift. Empty set if the template is absent
    (the sync test runs where it is present, so real enforcement is guaranteed)."""
    template = script_dir.parent / "prd-template.md"
    if not template.is_file():
        return set()
    return bracket_tokens(template.read_text(encoding="utf-8", errors="replace"))


def check(prd_text: str, tier: str, placeholders: set[str]) -> tuple[list[str], list[str]]:
    fails: list[str] = []
    warns: list[str] = []

    present = set(headings(prd_text))
    required = REQUIRED_TEAM if tier == "team" else REQUIRED_CORE
    for name in required:
        if name not in present:
            fails.append(f"missing required section: {name}")

    if not FR_RE.search(prd_text):
        fails.append("no Functional Requirement (expected an 'FR-<n>' heading)")
    if not ERR_RE.search(prd_text):
        fails.append("no Error Scenario (expected an 'ERR-<n>' heading)")

    ac_count = len(AC_RE.findall(prd_text))
    if ac_count == 0:
        fails.append("no Acceptance Criterion (expected an 'AC-<n>' heading)")
    else:
        valid = [block for block in gherkin_blocks(prd_text) if is_given_when_then(block)]
        if len(valid) < ac_count:
            fails.append(
                f"{ac_count} AC heading(s) but {len(valid)} valid Given-When-Then block(s)"
            )

    for token in sorted(placeholders & bracket_tokens(prd_text)):
        fails.append(f"unfilled template placeholder: {token}")

    if tier == "team":
        if not re.search(r"(?im)^\|?\s*Story ID\b", prd_text):
            fails.append("team PRD missing metadata table (no 'Story ID' row)")
        if not re.search(r"(?i)has_ui", prd_text):
            fails.append("team PRD missing has_ui field")

    for line_number, line in enumerate(prd_text.splitlines(), 1):
        for word in VAGUE_WORDS:
            if word in line:
                warns.append(f"line {line_number}: vague word '{word}' (quantify or justify)")

    return fails, warns


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prd", type=Path, required=True)
    parser.add_argument("--tier", choices=("core", "team"), default="team")
    args = parser.parse_args()

    try:
        prd_text = read(args.prd)
    except (OSError, ValueError) as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2

    placeholders = template_placeholders(Path(__file__).resolve().parent)
    fails, warns = check(prd_text, args.tier, placeholders)

    for warning in warns:
        print(f"WARN {warning}")
    print(f"PRD shape: tier={args.tier} sections={len(headings(prd_text))} fails={len(fails)}")
    if fails:
        for failure in fails:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1
    print("PASS PRD shape conforms")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
