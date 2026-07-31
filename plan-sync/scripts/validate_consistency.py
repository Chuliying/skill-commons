#!/usr/bin/env python3
"""Validate canonical-v2 Plan Sync artifacts."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple
from urllib.parse import urlsplit

sys.dont_write_bytecode = True

from planning_lib import (
    ALLOWED_TASK_STATUSES,
    canonical_concurrency_limit,
    parse_unified_plan,
    plan_dir_from_args,
    read_text,
    render_json,
    section_body,
)


BRACE_PLACEHOLDER_RE = re.compile(r"\{[a-z][a-z0-9-]*\}")
ANGLE_PLACEHOLDER_RE = re.compile(r"<[a-z][a-z0-9]*(?:[ _-][a-z0-9]+)*>")
TYPE_ATOM = r"[A-Za-z_$][A-Za-z0-9_.$]*(?:\[\])?"
GENERIC_TYPE_RE = re.compile(
    rf"\b[A-Za-z_$][A-Za-z0-9_.$]*<\s*{TYPE_ATOM}"
    rf"(?:\s*(?:,|\||&)\s*{TYPE_ATOM})*\s*>"
)
JSX_TAG_RE = re.compile(
    r"</?[A-Za-z][A-Za-z0-9:._-]*(?:\s+[^<>\n]*?)?\s*/?>"
)
INLINE_CODE_RE = re.compile(r"`([^`\n]*)`")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})\s*([A-Za-z0-9_+.-]*)")
ANGLE_CODE_FENCE_LANGUAGES = {
    "html", "javascript", "js", "jsx", "svelte", "tsx", "typescript", "ts", "vue", "xml"
}
ELLIPSIS_PLACEHOLDER_RE = re.compile(r"(?:^|:\s)(?:\.\.\.|…)$")
SOURCE_LINE_RE = re.compile(r"^- (local|user|external|repo): (\S(?:.*\S)?)$")
OPAQUE_SOURCE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/#@+\-]*$")
REPO_SOURCE_RE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._+\-]*)@(\S+)$")
STABLE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:\-]*$")
WINDOWS_ABSOLUTE_RE = re.compile(r"^[A-Za-z]:[\\/]")
ID_BOUNDARY_CLASS = r"A-Za-z0-9_\-"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan-dir", required=True)
    return parser.parse_args()


def mask_valid_code_angle_syntax(text: str, *, allow_jsx: bool) -> str:
    """Mask unambiguous language syntax before checking placeholder tokens."""
    masked = GENERIC_TYPE_RE.sub("", text)
    if allow_jsx:
        masked = JSX_TAG_RE.sub("", masked)
    return masked


def mask_inline_code_syntax(line: str) -> str:
    def replace(match: re.Match[str]) -> str:
        # A language fence is strong enough context for arbitrary JSX/HTML tag names.
        # Inline code still masks generic types, but placeholder-shaped command tokens
        # must remain visible to the release gate.
        content = mask_valid_code_angle_syntax(match.group(1), allow_jsx=False)
        return f"`{content}`"

    return INLINE_CODE_RE.sub(replace, line)


def placeholder_errors(path: Path, text: str) -> list[str]:
    errors = []
    fence_marker: str | None = None
    fence_language = ""
    for line_number, line in enumerate(text.splitlines(), 1):
        fence_match = FENCE_RE.match(line)
        if fence_match:
            marker = fence_match.group(1)
            if fence_marker is None:
                fence_marker = marker
                fence_language = fence_match.group(2).lower()
            elif marker[0] == fence_marker[0]:
                fence_marker = None
                fence_language = ""
            continue

        stripped = line.strip().removeprefix("- ").strip()
        reasons = []
        if BRACE_PLACEHOLDER_RE.search(line):
            reasons.append("template variable")
        angle_candidate = line
        if fence_marker is not None and fence_language in ANGLE_CODE_FENCE_LANGUAGES:
            angle_candidate = mask_valid_code_angle_syntax(line, allow_jsx=True)
        elif fence_marker is None:
            angle_candidate = mask_inline_code_syntax(line)
        if ANGLE_PLACEHOLDER_RE.search(angle_candidate):
            reasons.append("angle-bracket value")
        if ELLIPSIS_PLACEHOLDER_RE.search(stripped):
            reasons.append("ellipsis value")
        if "Replace this placeholder" in line:
            reasons.append("replacement instruction")
        if re.search(r"\b(?:TBD|TODO)\b", line):
            reasons.append("unfinished marker")
        if reasons:
            preview = line.strip()[:120]
            errors.append(
                f"{path.name}:{line_number}: placeholder ({', '.join(reasons)}): {preview}"
            )
    return errors


def git_workspace_root(path: Path) -> Path | None:
    for candidate in (path, *path.parents):
        marker = candidate / ".git"
        if marker.exists() or marker.is_symlink():
            return candidate.resolve()
    return None


def git_toplevel(path: Path) -> tuple[Path | None, bool, str]:
    """Ask Git for the canonical top-level of the working tree holding `path`.

    Returns `(top_level, git_ran, detail)`. A `.git` marker can be produced with
    `mkdir`, so repo identity is never inferred from the filesystem: only Git can
    confirm it, and every failure mode is reported instead of assumed benign.
    """
    try:
        proc = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        return None, False, str(exc)
    if proc.returncode != 0:
        detail = next(
            (line.strip() for line in reversed(proc.stderr.splitlines()) if line.strip()),
            f"git rev-parse exited {proc.returncode}",
        )
        return None, True, detail
    output = proc.stdout.strip()
    if not output:
        return None, True, "git rev-parse reported no working tree"
    return Path(output).resolve(), True, ""


def path_is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def literal_id_exists(text: str, stable_id: str) -> bool:
    pattern = re.compile(
        rf"(?<![{ID_BOUNDARY_CLASS}]){re.escape(stable_id)}(?![{ID_BOUNDARY_CLASS}])"
    )
    return pattern.search(text) is not None


class Participant(NamedTuple):
    """A repo declared in Sources that this repo's work depends on."""

    identifier: str
    lexical_root: Path
    resolved_root: Path


def resolve_repo_source(
    plan_dir: Path, value: str
) -> tuple[Participant | None, list[str]]:
    """Parse `id@path` into a participant, or explain why it is not one.

    Reasons carry no location prefix so the same resolution can be reported both
    per plan line and per declared participant.
    """
    match = REPO_SOURCE_RE.fullmatch(value)
    if not match:
        return None, [
            "must be an identifier, `@`, then a path relative to the workspace root"
        ]

    identifier, path_text = match.groups()
    if Path(path_text).is_absolute() or WINDOWS_ABSOLUTE_RE.match(path_text):
        return None, [
            f"`{identifier}` must be relative to the workspace root so the plan "
            "stays readable in another checkout"
        ]

    workspace_root = git_workspace_root(plan_dir)
    if workspace_root is None:
        return None, ["cannot be checked because no Git workspace was found"]

    lexical_root = Path(os.path.abspath(workspace_root / path_text))
    if path_is_within(lexical_root, workspace_root):
        return None, [
            f"`{identifier}` resolves inside this repo; reference it with "
            "`- local: ...` instead"
        ]
    if not lexical_root.exists():
        return None, [f"`{identifier}` does not exist: {path_text}"]
    if not lexical_root.is_dir():
        return None, [f"`{identifier}` is not a directory: {path_text}"]

    # The boundary is only real if it survives symlink resolution, and only means
    # something if the target carries a separate repo's identity.
    resolved_root = lexical_root.resolve()
    if path_is_within(resolved_root, workspace_root):
        return None, [
            f"`{identifier}` resolves back inside this repo through a symlink: "
            f"{path_text}; reference it with `- local: ...` instead"
        ]
    # Identity is what Git reports, not what the filesystem suggests: `mkdir .git`
    # must not be able to forge a participant repo.
    participant_root, git_ran, detail = git_toplevel(resolved_root)
    if participant_root is None and not git_ran:
        return None, [
            f"`{identifier}` cannot be verified because Git could not be run: "
            f"{detail}"
        ]
    if participant_root is None:
        return None, [
            f"`{identifier}` is not a Git working tree: {path_text}; "
            f"a participant must be a separate repo checkout ({detail})"
        ]
    # This repo keeps its marker-anchored workspace root — `local:` containment
    # owns that rule — and Git's own top-level is used when Git can confirm one.
    current_root, _, _ = git_toplevel(workspace_root)
    if (current_root or workspace_root) == participant_root:
        return None, [
            f"`{identifier}` belongs to this repo's Git working tree: "
            f"{path_text}; reference it with `- local: ...` instead"
        ]

    return Participant(identifier, lexical_root, resolved_root), []


def validate_repo_source(
    plan_dir: Path, value: str, line_number: int
) -> tuple[Participant | None, list[str]]:
    """Resolve one `repo:` Source line, reported at its location in plan.md."""
    participant, reasons = resolve_repo_source(plan_dir, value)
    return participant, [
        f"plan.md:{line_number}: repo source {reason}" for reason in reasons
    ]


def repo_source_values(sources: list[str]) -> list[str]:
    """The raw `identifier@path` value of every `repo:` Source line.

    One definition, so readers of a plan never grow a second Sources parser.
    """
    values: list[str] = []
    for entry in sources:
        source_type, separator, value = entry.partition(":")
        if separator and source_type.strip() == "repo":
            values.append(value.strip())
    return values


def declared_participant_ids(sources: list[str]) -> list[str]:
    """Participant identifiers declared in a plan's Sources, sorted and unique."""
    identifiers: set[str] = set()
    for value in repo_source_values(sources):
        match = REPO_SOURCE_RE.fullmatch(value)
        if match:
            identifiers.add(match.group(1))
    return sorted(identifiers)


def declared_participant_errors(plan_dir: Path, sources: list[str]) -> list[str]:
    """Why any declared participant cannot be resolved, sorted and unique.

    Independent of whole-plan validity: a declared participant is part of the work
    item's identity, so a reader must be told that one is unreachable rather than
    seeing it silently disappear from the declaration.
    """
    errors: set[str] = set()
    for value in repo_source_values(sources):
        participant, reasons = resolve_repo_source(plan_dir, value)
        if participant is None:
            errors.update(f"declared participant {reason}" for reason in reasons)
    return sorted(errors)


def validate_local_source(
    plan_dir: Path,
    value: str,
    line_number: int,
    participants: list[Participant],
    *,
    evidence_context: str | None = None,
) -> list[str]:
    """Check one `local:` path. `evidence_context` names the claim being recorded,
    which has no participants to widen it: declaring a repo cannot make foreign
    evidence legal, so the escape message must not suggest it."""
    prefix = f"plan.md:{line_number}: local source"
    errors: list[str] = []
    if value.count("#") > 1:
        return [f"{prefix} has more than one anchor delimiter"]

    path_text, separator, anchor = value.partition("#")
    if not path_text:
        return [f"{prefix} is missing its relative path"]
    if separator and (not anchor or not STABLE_ID_RE.fullmatch(anchor)):
        return [f"{prefix} has invalid literal stable ID anchor `{anchor}`"]
    if Path(path_text).is_absolute() or WINDOWS_ABSOLUTE_RE.match(path_text):
        return [f"{prefix} must be relative to plan.md"]

    workspace_root = git_workspace_root(plan_dir)
    if workspace_root is None:
        return [f"{prefix} cannot be checked because no Git workspace was found"]

    lexical_path = Path(os.path.abspath(plan_dir / path_text))
    resolved_path = (plan_dir / path_text).resolve(strict=False)
    if path_is_within(lexical_path, workspace_root):
        if not path_is_within(resolved_path, workspace_root):
            if evidence_context is not None:
                return [
                    f"{evidence_context} escapes Git workspace through a symlink: "
                    f"{path_text}; verification evidence must stay inside the repo "
                    "making the claim, so declaring the other repo as a participant "
                    "does not unlock it"
                ]
            return [f"{prefix} escapes Git workspace through a symlink: {path_text}"]
    else:
        owner = next(
            (
                participant
                for participant in participants
                if path_is_within(lexical_path, participant.lexical_root)
            ),
            None,
        )
        if owner is None:
            if evidence_context is not None:
                return [
                    f"{evidence_context} escapes Git workspace: {path_text}; "
                    "verification evidence must stay inside the repo making the "
                    "claim, so declaring the other repo as a participant does "
                    "not unlock it"
                ]
            return [
                f"{prefix} escapes Git workspace with no declared participant repo: "
                f"{path_text}; declare the other repo in Sources as "
                "`- repo: identifier@path`"
            ]
        if not path_is_within(resolved_path, owner.resolved_root):
            return [
                f"{prefix} escapes participant `{owner.identifier}` through a "
                f"symlink: {path_text}"
            ]
    if not resolved_path.exists():
        return [f"{prefix} does not exist: {path_text}"]
    if resolved_path.is_dir():
        if separator:
            errors.append(f"{prefix} directory source cannot use an anchor")
        return errors
    if separator:
        try:
            source_text = resolved_path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            return [f"{prefix} cannot read anchor target {path_text}: {exc}"]
        if not literal_id_exists(source_text, anchor):
            errors.append(f"{prefix} anchor `{anchor}` was not found with an exact boundary")
    return errors


def valid_external_source(value: str) -> bool:
    if any(character.isspace() for character in value):
        return False
    parsed = urlsplit(value)
    if parsed.scheme in {"http", "https"} and parsed.netloc:
        return True
    return OPAQUE_SOURCE_RE.fullmatch(value) is not None


def validate_sources(plan_dir: Path, text: str) -> list[str]:
    body = section_body(text, "Sources")
    if not body:
        return []

    heading_line = text[: text.index(body)].count("\n") + 1
    errors: list[str] = []
    typed: list[tuple[str, str, int]] = []
    for offset, line in enumerate(body.splitlines(), 1):
        line_number = heading_line + offset
        if not line.strip():
            continue
        match = SOURCE_LINE_RE.fullmatch(line)
        if not match or "`" in line:
            errors.append(
                f"plan.md:{line_number}: expected typed source exactly as "
                "`- local: ...`, `- user: ...`, `- external: ...`, or `- repo: ...`"
            )
            continue
        source_type, value = match.groups()
        typed.append((source_type, value, line_number))

    # Participants are resolved first: a local reference may only leave this repo
    # into a repo the plan has already declared.
    participants: list[Participant] = []
    seen_identifiers: set[str] = set()
    for source_type, value, line_number in typed:
        if source_type != "repo":
            continue
        participant, participant_errors = validate_repo_source(
            plan_dir, value, line_number
        )
        errors.extend(participant_errors)
        if participant is None:
            continue
        if participant.identifier in seen_identifiers:
            errors.append(
                f"plan.md:{line_number}: repo source `{participant.identifier}` is "
                "declared more than once"
            )
            continue
        seen_identifiers.add(participant.identifier)
        participants.append(participant)

    for source_type, value, line_number in typed:
        if source_type == "repo":
            continue
        if source_type == "local":
            errors.extend(
                validate_local_source(plan_dir, value, line_number, participants)
            )
        elif source_type == "user":
            if not OPAQUE_SOURCE_RE.fullmatch(value):
                errors.append(
                    f"plan.md:{line_number}: user source must be one durable opaque reference"
                )
        elif not valid_external_source(value):
            errors.append(
                f"plan.md:{line_number}: external source must be a URL or durable opaque ID"
            )
    return errors


def typed_reference_errors(
    plan_dir: Path,
    reference: str,
    context: str,
    *,
    allow_user: bool,
    is_evidence: bool = False,
) -> list[str]:
    if ":" not in reference:
        return [f"{context} must use a typed local, user, or external reference"]
    reference_type, value = reference.split(":", 1)
    if reference_type == "local":
        # Deliberately no participants: a Source may point into another repo, but
        # verification evidence must still live in the repo making the claim.
        return validate_local_source(
            plan_dir,
            value,
            0,
            [],
            evidence_context=context if is_evidence else None,
        )
    if reference_type == "user":
        if not allow_user:
            return [f"{context} cannot use a user reference as execution evidence"]
        if not OPAQUE_SOURCE_RE.fullmatch(value):
            return [f"{context} user reference must be one durable opaque ID"]
        return []
    if reference_type == "external":
        if not valid_external_source(value):
            return [f"{context} external reference must be a URL or durable opaque ID"]
        return []
    return [f"{context} must use a typed local, user, or external reference"]


def blocker_errors(plan_dir: Path, task: object) -> list[str]:
    task_id = str(task.task_id)
    status = str(task.status)
    reason = str(getattr(task, "blocker_reason", ""))
    blocker_ref = str(getattr(task, "blocker_ref", ""))
    unblocked_ref = str(getattr(task, "unblocked_ref", ""))
    errors: list[str] = []

    if status == "blocked":
        if not reason:
            errors.append(f"{task_id} blocked status requires Blocker Reason")
        if not blocker_ref:
            errors.append(f"{task_id} blocked status requires Blocker Ref")
        if unblocked_ref:
            errors.append(f"{task_id} is still blocked and cannot have Unblocked Ref")
    elif reason or blocker_ref:
        if not reason:
            errors.append(f"{task_id} blocker history requires Blocker Reason")
        if not blocker_ref:
            errors.append(f"{task_id} blocker history requires Blocker Ref")
        if not unblocked_ref:
            errors.append(
                f"{task_id} cleared blocker history requires structured Unblocked Ref"
            )
    elif unblocked_ref:
        errors.append(f"{task_id} Unblocked Ref requires retained blocker history")

    if blocker_ref:
        errors.extend(
            typed_reference_errors(
                plan_dir,
                blocker_ref,
                f"{task_id} Blocker Ref",
                allow_user=True,
            )
        )
    if unblocked_ref:
        errors.extend(
            typed_reference_errors(
                plan_dir,
                unblocked_ref,
                f"{task_id} Unblocked Ref",
                allow_user=True,
            )
        )
    return errors


def verification_evidence_errors(plan_dir: Path, task: object) -> list[str]:
    task_id = str(task.task_id)
    verification = list(getattr(task, "verification", []))
    evidence_items = list(getattr(task, "verification_evidence", []))
    errors: list[str] = []
    records: dict[str, str] = {}

    for item in evidence_items:
        parts = [part.strip() for part in item.split(" | ", 2)]
        if len(parts) != 3:
            errors.append(
                f"{task_id} has malformed Verification Evidence; expected "
                "RESULT | REFERENCE | COMMAND"
            )
            continue
        result, reference, command = parts
        if result not in {"PASS", "FAIL"}:
            errors.append(f"{task_id} Verification Evidence uses invalid result `{result}`")
        errors.extend(
            typed_reference_errors(
                plan_dir,
                reference,
                f"{task_id} Verification Evidence reference",
                allow_user=False,
                is_evidence=True,
            )
        )
        if command not in verification:
            errors.append(
                f"{task_id} Verification Evidence command does not match Verification: {command}"
            )
            continue
        if command in records:
            errors.append(f"{task_id} has duplicate Verification Evidence for: {command}")
            continue
        records[command] = result

    if str(task.status) == "done":
        if not evidence_items:
            errors.append(f"{task_id} done status requires Verification Evidence")
        for command in verification:
            if records.get(command) != "PASS":
                errors.append(
                    f"{task_id} done status requires PASS evidence for Verification: {command}"
                )
    return errors


def canonical_execution_errors(plan_dir: Path, plan: object) -> list[str]:
    errors: list[str] = []
    concurrency = str(plan.concurrency)
    if not re.fullmatch(r"[1-9][0-9]*", concurrency):
        errors.append("plan.md Plan section `Concurrency` must be a positive integer")
    concurrency_limit = canonical_concurrency_limit(plan)
    in_progress = [task.task_id for task in plan.tasks if task.status == "in_progress"]
    if len(in_progress) > concurrency_limit:
        errors.append(
            "in_progress tasks exceed Concurrency "
            f"{concurrency_limit}: {', '.join(in_progress)}"
        )

    task_by_id = {task.task_id: task for task in plan.tasks}
    for task in plan.tasks:
        unmet = [
            dependency
            for dependency in task.depends_on
            if dependency not in task_by_id or task_by_id[dependency].status != "done"
        ]
        if task.status in {"in_progress", "done"} and unmet:
            errors.append(
                f"{task.task_id} status `{task.status}` has unmet dependencies: "
                f"{', '.join(unmet)}"
            )
        errors.extend(blocker_errors(plan_dir, task))
        errors.extend(verification_evidence_errors(plan_dir, task))
    return errors


def meta_plan_stage_lines(text: str) -> list[str]:
    plan_lines: list[str] = []
    in_stages = False
    for line in text.splitlines():
        if line == "stages:":
            in_stages = True
            continue
        if not in_stages:
            continue
        if line and not line[0].isspace():
            in_stages = False
            continue
        if re.match(r"^\s+plan\s*:", line):
            plan_lines.append(line)
    return plan_lines


def parse_inline_mapping(line: str) -> dict[str, str] | None:
    match = re.fullmatch(r"\s+plan:\s*\{([^{}]*)\}\s*", line)
    if not match:
        return None
    fields: dict[str, str] = {}
    for item in match.group(1).split(","):
        if ":" not in item:
            return None
        key, value = item.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not key or not value or key in fields:
            return None
        fields[key] = value
    return fields


def validate_canonical_meta(plan_dir: Path) -> list[str]:
    meta_path = plan_dir.parent / "meta.yml"
    if not meta_path.is_file():
        return [f"canonical-v2 requires sibling meta.yml: {meta_path}"]

    text = read_text(meta_path)
    plan_lines = meta_plan_stage_lines(text)
    if len(plan_lines) != 1:
        return [f"meta.yml must contain exactly one plan stage; found {len(plan_lines)}"]

    fields = parse_inline_mapping(plan_lines[0])
    if fields is None:
        return ["meta.yml plan stage must use one inline mapping"]

    errors: list[str] = []
    if fields.get("skill") != "plan-sync":
        errors.append("meta.yml plan stage must use skill `plan-sync`")

    file_value = fields.get("file")
    if not file_value:
        errors.append("meta.yml plan stage is missing file")
    elif Path(file_value).is_absolute() or WINDOWS_ABSOLUTE_RE.match(file_value):
        errors.append("meta.yml plan stage file must be relative to meta.yml")
    else:
        declared_path = (meta_path.parent / file_value).resolve(strict=False)
        current_path = (plan_dir / "plan.md").resolve()
        if declared_path != current_path:
            errors.append("meta.yml plan stage file must resolve to the current plan.md")
    return errors


def dependency_errors(tasks: list[object]) -> list[str]:
    errors: list[str] = []
    task_ids = [task.task_id for task in tasks]
    known = set(task_ids)
    if len(known) != len(task_ids):
        duplicates = sorted({task_id for task_id in task_ids if task_ids.count(task_id) > 1})
        errors.append(f"duplicate tasks: {', '.join(duplicates)}")

    graph: dict[str, list[str]] = {}
    for task in tasks:
        dependencies = list(getattr(task, "depends_on", []))
        graph[task.task_id] = [item for item in dependencies if item in known]
        for dependency in dependencies:
            if dependency not in known:
                errors.append(f"{task.task_id} references unknown dependency `{dependency}`")

    state: dict[str, int] = {}
    stack: list[str] = []
    reported_cycles: set[tuple[str, ...]] = set()

    def visit(task_id: str) -> None:
        current_state = state.get(task_id, 0)
        if current_state == 2:
            return
        if current_state == 1:
            start = stack.index(task_id)
            cycle = tuple(stack[start:] + [task_id])
            if cycle not in reported_cycles:
                reported_cycles.add(cycle)
                errors.append(f"dependency cycle: {' -> '.join(cycle)}")
            return

        state[task_id] = 1
        stack.append(task_id)
        for dependency in graph.get(task_id, []):
            visit(dependency)
        stack.pop()
        state[task_id] = 2

    for task_id in task_ids:
        visit(task_id)
    return errors


def validate_journal(plan_dir: Path) -> tuple[list[str], int]:
    journal_path = plan_dir / "journal.md"
    if not journal_path.is_file():
        return [], 0
    text = read_text(journal_path)
    errors = placeholder_errors(journal_path, text)
    journal_titles = re.findall(r"^# Journal: .+$", text, re.MULTILINE)
    if len(journal_titles) != 1:
        errors.append(
            f"journal.md must contain exactly one `# Journal:` title; found {len(journal_titles)}"
        )
    level_one_headings = re.findall(r"^# ([^\n]+)$", text, re.MULTILINE)
    for heading in level_one_headings:
        if not heading.startswith("Journal: "):
            errors.append(f"journal.md has unknown level-one heading `{heading}`")
    level_two_headings = re.findall(r"^## ([^\n]+)$", text, re.MULTILINE)
    events_count = level_two_headings.count("Events")
    if events_count != 1:
        errors.append(
            f"journal.md section `## Events` appears {events_count} times; expected exactly one"
        )
    for heading in level_two_headings:
        if heading != "Events":
            errors.append(f"journal.md has unknown level-two section `{heading}`")
    events = section_body(text, "Events")
    if not events:
        errors.append("journal.md is missing non-empty `## Events`")
        return errors, 0
    event_lines = [line for line in events.splitlines() if line.strip()]
    for line in event_lines:
        if not re.match(r"^- \S+ \| (decision|scope_change|blocker|deviation) \| .+$", line):
            errors.append(f"journal.md has malformed event: {line[:120]}")
    return errors, len(event_lines)


def validate_canonical(plan_dir: Path) -> tuple[list[str], list[str], dict[str, int | str]]:
    path = plan_dir / "plan.md"
    text = read_text(path)
    errors = placeholder_errors(path, text)
    warnings: list[str] = []

    plan_titles = re.findall(r"^# Plan: .+$", text, re.MULTILINE)
    if len(plan_titles) != 1:
        errors.append(
            f"plan.md must contain exactly one `# Plan:` title; found {len(plan_titles)}"
        )
    level_one_headings = re.findall(r"^# ([^\n]+)$", text, re.MULTILINE)
    for heading in level_one_headings:
        if not heading.startswith("Plan: "):
            errors.append(f"plan.md has unknown level-one heading `{heading}`")

    required_sections = ("Plan", "Sources", "Tasks", "Change Log")
    level_two_headings = re.findall(r"^## ([^\n]+)$", text, re.MULTILINE)
    for heading in required_sections:
        count = level_two_headings.count(heading)
        if count != 1:
            errors.append(
                f"plan.md section `## {heading}` appears {count} times; expected exactly one"
            )
    for heading in level_two_headings:
        if heading not in required_sections:
            errors.append(f"plan.md has unknown level-two section `{heading}`")

    plan = parse_unified_plan(text)
    plan_body = section_body(text, "Plan")

    plan_field_names = ("Format", "Concurrency", "Intent", "Scope", "Non-goals")
    for field in plan_field_names:
        count = len(re.findall(rf"^- {re.escape(field)}:", plan_body, re.MULTILINE))
        if count > 1:
            errors.append(f"Plan field {field} appears {count} times; expected at most one")
    for match in re.finditer(r"^- ([^:\n]+):", plan_body, re.MULTILINE):
        if match.group(1).strip() not in plan_field_names:
            errors.append(f"Plan has unknown field `{match.group(1).strip()}`")

    for heading in required_sections:
        if not section_body(text, heading):
            errors.append(f"plan.md is missing non-empty `## {heading}`")
    for field, value in (
        ("Intent", plan.intent),
        ("Scope", plan.scope),
        ("Non-goals", plan.non_goals),
    ):
        if not value:
            errors.append(f"plan.md Plan section is missing `{field}`")

    if plan.format_version != "canonical-v2":
        errors.append(
            f"plan.md requires Format `canonical-v2`; found `{plan.format_version}`"
        )
    if not plan.sources:
        errors.append("canonical-v2 plan.md requires non-empty `## Sources`")
    errors.extend(validate_sources(plan_dir, text))
    errors.extend(validate_canonical_meta(plan_dir))
    errors.extend(canonical_execution_errors(plan_dir, plan))
    if not plan.tasks:
        errors.append("plan.md has no tasks")

    tasks_body = section_body(text, "Tasks")
    task_matches = list(re.finditer(r"^### (T\d+) \| (.+)$", tasks_body, re.MULTILINE))
    for heading in re.findall(r"^### ([^\n]+)$", tasks_body, re.MULTILINE):
        if not re.fullmatch(r"T\d+ \| .+", heading):
            errors.append(
                f"plan.md Tasks has non-canonical task heading `### {heading}`"
            )
    for index, task in enumerate(plan.tasks):
        start = task_matches[index].end()
        end = task_matches[index + 1].start() if index + 1 < len(task_matches) else len(tasks_body)
        raw_block = tasks_body[start:end]
        subsection_start = re.search(r"^#### ", raw_block, re.MULTILINE)
        metadata_block = raw_block[: subsection_start.start()] if subsection_start else raw_block
        task_fields = (
            "Status",
            "Depends On",
            "Blocker Reason",
            "Blocker Ref",
            "Unblocked Ref",
        )
        for field in task_fields:
            count = len(
                re.findall(rf"^- {re.escape(field)}:", metadata_block, re.MULTILINE)
            )
            if count > 1:
                errors.append(
                    f"{task.task_id} task field {field} appears {count} times; "
                    "expected at most one"
                )
        for match in re.finditer(r"^- ([^:\n]+):", metadata_block, re.MULTILINE):
            if match.group(1).strip() not in task_fields:
                errors.append(
                    f"{task.task_id} has unknown task field `{match.group(1).strip()}`"
                )

        subsection_names = [
            match.group(1).strip()
            for match in re.finditer(r"^#### ([^\n]+)$", raw_block, re.MULTILINE)
        ]
        allowed_subsections = (
            "Intent",
            "Expected Result",
            "Definition of Done",
            "Verification",
            "Verification Evidence",
        )
        for subsection in allowed_subsections:
            count = subsection_names.count(subsection)
            if count > 1:
                errors.append(
                    f"{task.task_id} task subsection {subsection} appears {count} times; "
                    "expected at most one"
                )
        for subsection in subsection_names:
            if subsection not in allowed_subsections:
                errors.append(
                    f"{task.task_id} has unknown task subsection `{subsection}`"
                )

        if task.status not in ALLOWED_TASK_STATUSES:
            errors.append(f"{task.task_id} uses invalid status `{task.status}`")
        if not task.intent:
            errors.append(f"{task.task_id} is missing Intent")
        if not task.expected_result:
            errors.append(f"{task.task_id} is missing Expected Result")
        if not task.verification:
            errors.append(f"{task.task_id} is missing Verification")
        if not re.search(r"^- Depends On:\s*\[[^\n]*\]\s*$", raw_block, re.MULTILINE):
            errors.append(f"{task.task_id} is missing Depends On")
        if not task.definition_of_done:
            errors.append(f"{task.task_id} is missing Definition of Done")
        if len(set(task.depends_on)) != len(task.depends_on):
            errors.append(f"{task.task_id} has duplicate dependencies")
        if len(set(task.verification)) != len(task.verification):
            errors.append(f"{task.task_id} has duplicate Verification commands")

    errors.extend(dependency_errors(list(plan.tasks)))
    journal_errors, journal_events = validate_journal(plan_dir)
    errors.extend(journal_errors)
    return errors, warnings, {
        "mode": "canonical",
        "format": plan.format_version,
        "tasks": len(plan.tasks),
        "concurrency": canonical_concurrency_limit(plan),
        "journal_events": journal_events,
    }


def validate_plan_dir(plan_dir: Path) -> tuple[dict[str, object], int]:
    canonical_path = plan_dir / "plan.md"
    retired_paths = [
        plan_dir / "implementation.md",
        plan_dir / "tasks.md",
        plan_dir / "notes.md",
    ]
    retired = [path.name for path in retired_paths if path.is_file()]
    if retired:
        payload = {
            "pass": False,
            "errors": [
                "tracked-v1 plan files are unsupported in v0.7 "
                f"({', '.join(retired)}); migrate to canonical plan/plan.md "
                "or pin skill-commons v0.6"
            ],
            "warnings": [],
            "stats": {"mode": "retired"},
        }
        return payload, 2

    try:
        if canonical_path.is_file():
            errors, warnings, stats = validate_canonical(plan_dir)
        else:
            errors = [f"no plan artifacts found in {plan_dir}"]
            warnings = []
            stats = {"mode": "missing"}
    except (OSError, UnicodeError) as exc:
        errors = [f"cannot read plan artifacts: {exc}"]
        warnings = []
        stats = {"mode": "incomplete"}

    payload = {
        "pass": not errors,
        "errors": errors,
        "warnings": warnings,
        "stats": stats,
    }
    if errors:
        return payload, 2
    if warnings:
        return payload, 1
    return payload, 0


def main() -> int:
    args = parse_args()
    plan_dir = plan_dir_from_args(args.plan_dir)
    payload, return_code = validate_plan_dir(plan_dir)
    print(render_json(payload))
    return return_code


if __name__ == "__main__":
    sys.exit(main())
