#!/usr/bin/env python3
"""Verification evidence bound to content.

`record` is called by verification-before-completion/scripts/verify.sh after it runs the
manifest checks. It writes `<work_root>/<slug>/verification.json` with the result and a
fingerprint of the files the checks covered: the manifest `source_roots` and `tests_root`
when set, otherwise every tracked or new file outside the work root and the generated
agent directories. Uncommitted content is hashed as it is on disk.

`assess` recomputes that fingerprint and says whether the evidence still describes the
current content. It never writes. States:

- current: the last recorded run passed and the fingerprinted files are unchanged.
- stale:   the files, the manifest check commands or a bound segment changed after the run.
- failed:  the last recorded run did not pass, including runs that skipped the tests.
- unknown: no evidence, evidence that cannot be read, comes from another format or has no
           recorded command, or a scope that covers no files.

The fingerprint includes the manifest check commands (`test_cmd`, `typecheck_cmd`,
`lint_cmd`, `typed_contracts`), so weakening the test command makes evidence stale.
`record` only runs when verify.sh sets SKILL_COMMONS_VERIFY_RUN=1. This makes the record
tamper-evident, not tamper-proof: someone who sets that variable or edits the file by hand
can still forge it.

`source_roots: .` means the whole repository, the same as leaving the roots unset.

Evidence also binds content segments: an acceptance criterion or task in the work item's
documents, named `<file>#<ID>` (for example `prd.md#AC-002`). A segment starts at the line
that opens with the ID, as a heading or a list item, and ends before the next heading or
the next line that opens an ID of the same kind. Its fingerprint ignores whitespace and
punctuation. Without `--covers`, a run binds every `AC-` segment in the item's `prd.md` and
`spec.md`, so editing a criterion after the run makes the evidence stale.

`approve` binds a person's approval to the same segments in `approval.json`. `--by` is a
typed reference such as `user:<name>`. The record says how the approval was obtained (T11):

- `terminal`: a person confirmed it by typing `yes` at `/dev/tty`, with no agent variable set.
  `--by` defaults to `user:<git config user.name>`.
- `agent-reported`: an agent ran it with `--agent-reported` and `--quote` (the person's words)
  or `--reason`. Use it when the person has no shell on this checkout, for example a cloud chat.
- `recorded before levels`: an approval written before T11 (schema 1).

Without `--agent-reported`, `approve` refuses when `/dev/tty` cannot be opened or an agent
variable is set, and prints both commands. `agent_env` records the agent variables seen. This
records how the approval was obtained; it is not identity verification. A process that gets a
terminal and clears the agent variables can still write `terminal`, and so can a hand edit.

`reaffirm` records that an edited acceptance segment still means the same, with a reason; it
applies only to work-item document segments, never to the code fingerprint, and status reports
how many segments were reaffirmed. When `approval.json` records the segment, `reaffirm` passes
the same confirmation as `approve`, and each reaffirm entry keeps its own level; the
approval's level is the lowest of the approval and its reaffirms. `--evidence-only` reaffirms
only `verification.json`.

Caches that test runs write (`__pycache__`, `.pytest_cache`, `node_modules` and similar)
are never fingerprinted, even when the repository does not ignore them.

Known limits: dependencies, configuration outside the roots and the environment are not
fingerprinted; nested Git repositories inside a root are skipped; a flaky test can give
different results for the same content.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import unicodedata
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import activity  # noqa: E402
except ImportError:  # an older or partial install: evidence still records, the log is skipped
    activity = None


def _log(item_dir: Path, event: str, result: str = "ok", **extra) -> None:
    if activity is None:
        print("warning: activity.py is missing; activity.jsonl was not written", file=sys.stderr)
        return
    activity.try_append(item_dir, event, result, **extra)

EVIDENCE_FILE = "verification.json"
APPROVAL_FILE = "approval.json"
SCHEMA = 2
READABLE_SCHEMAS = {1, 2}
AUTO_COVER_FILES = ("prd.md", "spec.md")
SEGMENT_ID = re.compile(r"(?:[A-Z][A-Z0-9]*-\d+|T\d+)")
SEGMENT_START = re.compile(
    r"^(#{1,6}\s+|\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?)?(?:\*\*|`)?(" + SEGMENT_ID.pattern + r")\b"
)
HEADING = re.compile(r"^(#{1,6})\s")
FENCE = re.compile(r"^\s*(```|~~~)")
APPROVAL_SCHEMA = 2
LEVELS = ("recorded before levels", "agent-reported", "terminal")  # lowest first
APPROVER_REF = re.compile(r"(?:user|local|external):[A-Za-z0-9][A-Za-z0-9._@/:+-]*")
ALGORITHM = "sha256-of-git-blob-ids+stack-v4"
STACK_KEYS = ("test_cmd", "typecheck_cmd", "lint_cmd", "typed_contracts")
RECORD_TOKEN = "SKILL_COMMONS_VERIFY_RUN"
# Generated per-agent directories and Git metadata are never part of the verified content.
EXCLUDED_TOP = {".git", ".agent", ".agents", ".claude", ".codex", ".cursor"}
# Caches that running the checks writes. A repository that does not ignore them would
# otherwise go stale on every test run (competitor test round 2: `__pycache__`).
CACHE_DIRS = {"__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox", ".hypothesis",
              ".venv", "venv", "node_modules", ".next", ".turbo", ".nyc_output", ".vitest",
              "htmlcov", "coverage", "test-results", "playwright-report", "target"}
CACHE_SUFFIXES = (".pyc", ".pyo")
CACHE_FILES = {".coverage", ".DS_Store"}


# ── content segments ────────────────────────────────────────────────────────


def _kind(segment_id: str) -> str:
    return segment_id.split("-", 1)[0] if "-" in segment_id else segment_id[0]


def _normalize(text: str) -> str:
    """Punctuation counts as a word break, so `1.5` and `15` differ but `a, b` and `a b` match."""
    spaced = "".join(" " if unicodedata.category(ch).startswith("P") else ch for ch in text)
    return " ".join(spaced.split())


def _unfenced(lines: list[str]) -> list[str | None]:
    """Lines inside fenced code blocks become None: an ID there opens no segment."""
    out: list[str | None] = []
    fenced = False
    for line in lines:
        if FENCE.match(line):
            fenced = not fenced
            out.append(None)
            continue
        out.append(None if fenced else line)
    return out


def segments(text: str) -> dict[str, list[str]]:
    """Map each ID that opens a segment to the segment texts (more than one is ambiguous).
    A segment ends at the next same-kind ID, or at a heading of the same or a higher level than
    a heading opener (any heading for a list or line opener)."""
    found: dict[str, list[str]] = {}
    raw = text.splitlines()
    lines = _unfenced(raw)
    for index, line in enumerate(lines):
        match = SEGMENT_START.match(line) if line is not None else None
        if not match:
            continue
        segment_id = match.group(2)
        opener_heading = HEADING.match(line)
        level = len(opener_heading.group(1)) if opener_heading else 7
        body = [line]
        for offset, following in enumerate(lines[index + 1:], start=index + 1):
            if following is not None:
                heading = HEADING.match(following)
                if heading and len(heading.group(1)) <= level:
                    break
                opener = SEGMENT_START.match(following)
                if opener and _kind(opener.group(2)) == _kind(segment_id):
                    break
            body.append(raw[offset])
        found.setdefault(segment_id, []).append("\n".join(body))
    return found


def _split_ref(ref: str) -> tuple[str, str]:
    name, separator, segment_id = ref.partition("#")
    if not separator or not name or not SEGMENT_ID.fullmatch(segment_id):
        raise ValueError(f"segment reference must look like prd.md#AC-002: {ref}")
    norm = os.path.normpath(name).replace(os.sep, "/")
    if os.path.isabs(name) or norm == ".." or norm.startswith("../"):
        raise ValueError(f"segment reference must stay inside the work item: {ref}")
    return norm, segment_id


def segment_digest(item_dir: Path, ref: str) -> str | None:
    """Fingerprint of one segment; None when the file or ID is missing or ambiguous."""
    name, segment_id = _split_ref(ref)
    path = item_dir / name
    if not path.is_file():
        return None
    bodies = segments(path.read_text(errors="replace")).get(segment_id, [])
    if len(bodies) != 1:
        return None
    return hashlib.sha256(_normalize(bodies[0]).encode()).hexdigest()


def auto_covers(item_dir: Path) -> list[str]:
    refs = []
    for name in AUTO_COVER_FILES:
        path = item_dir / name
        if path.is_file():
            refs += [f"{name}#{sid}" for sid in segments(path.read_text(errors="replace")) if sid.startswith("AC-")]
    return refs


def bind(item_dir: Path, covers: list[str]) -> list[dict]:
    if not covers:
        _note_unbound(item_dir)
    bound = []
    for ref in covers or auto_covers(item_dir):
        digest = segment_digest(item_dir, ref)
        if digest is None:
            raise SystemExit(f"verification evidence: segment not found or ambiguous: {ref}")
        bound.append({"ref": ref, "digest": digest})
    return bound


def _note_unbound(item_dir: Path) -> None:
    present = [name for name in AUTO_COVER_FILES if (item_dir / name).is_file()]
    if present and not auto_covers(item_dir):
        print(f"note: no AC- segments in {', '.join(present)}; acceptance criteria are not bound",
              file=sys.stderr)


def assess_segments(item_dir: Path, bound: list, auto: bool = False) -> tuple[str, str]:
    """('current'|'stale'|'unknown', detail) for recorded segment fingerprints. With `auto`, a
    criterion added after the run (an AC- segment that was not bound) also counts as a change."""
    changed, missing = [], []
    if auto:
        recorded = {str(entry.get("ref")) for entry in bound if isinstance(entry, dict)}
        added = [ref for ref in auto_covers(item_dir) if ref not in recorded]
        if added:
            return "stale", f"criteria added after it was recorded: {', '.join(added)}"
    for entry in bound:
        try:
            digest = segment_digest(item_dir, str(entry["ref"]))
        except (ValueError, KeyError, TypeError):
            return "unknown", "a recorded segment reference is malformed"
        if digest is None:
            missing.append(str(entry["ref"]))
        elif digest != entry.get("digest"):
            changed.append(str(entry["ref"]))
    if missing:
        return "unknown", f"segment missing or ambiguous: {', '.join(missing)}"
    if changed:
        return "stale", f"changed after it was recorded: {', '.join(changed)}"
    return "current", ""


def manifest_value(project_root: Path, key: str) -> str:
    manifest = Path(os.environ.get("PROJECT_MANIFEST", project_root / ".agent" / "project-manifest.md"))
    if not manifest.is_file():
        return ""
    for line in manifest.read_text(errors="replace").splitlines():
        stripped = line.strip()
        for prefix in (f"- {key}:", f"- `{key}`:"):
            if stripped.startswith(prefix):
                value = stripped[len(prefix):].strip()
                if len(value) >= 2 and value[0] == value[-1] == "`":
                    value = value[1:-1]
                return value
    return ""


def work_root_of(project_root: Path) -> str:
    return (manifest_value(project_root, "work_root") or "docs/work").strip("/")


def normalize_root(raw: str) -> str:
    """`./src`, `src/` and `src` are the same root; roots must stay inside the project."""
    text = raw.strip().strip("`").strip()
    if not text:
        return ""
    if os.path.isabs(text):
        raise ValueError(f"root must be project-relative: {text}")
    norm = os.path.normpath(text).replace(os.sep, "/")
    if norm == ".." or norm.startswith("../"):
        raise ValueError(f"root escapes the project: {text}")
    return "" if norm == "." else norm


def scope_roots(project_root: Path) -> list[str]:
    roots: list[str] = []
    for key in ("source_roots", "tests_root"):
        for part in manifest_value(project_root, key).split(","):
            root = normalize_root(part)
            if root and root not in roots:
                roots.append(root)
    return roots


def stack_commands(project_root: Path) -> dict:
    return {key: manifest_value(project_root, key) for key in STACK_KEYS}


def _under(path: str, root: str) -> bool:
    return root in ("", ".") or path == root or path.startswith(root + "/")


def scope_files(project_root: Path, roots: list[str], work_root: str) -> list[str]:
    git = subprocess.run(
        ["git", "-C", str(project_root), "ls-files", "-co", "--exclude-standard", "-z"],
        capture_output=True,
    )
    if git.returncode == 0:
        names = [os.fsdecode(raw) for raw in git.stdout.split(b"\0") if raw]
    else:
        names = [
            str(path.relative_to(project_root))
            for path in project_root.rglob("*")
            if path.is_file()
        ]
    selected = []
    for name in names:
        if _under(name, work_root) or name.split("/", 1)[0] in EXCLUDED_TOP:
            continue
        parts = name.split("/")
        if (CACHE_DIRS.intersection(parts[:-1]) or parts[-1] in CACHE_FILES
                or parts[-1].startswith(".coverage.") or name.endswith(CACHE_SUFFIXES)):
            continue
        if roots and not any(_under(name, root) for root in roots):
            continue
        path = project_root / name
        # Deleted-but-tracked paths, submodule links and nested repositories are not
        # file content; a symlink is fingerprinted by its target text, not followed.
        if path.is_symlink() or path.is_file():
            selected.append(name)
    return sorted(selected)


def blob_ids(project_root: Path, files: list[str]) -> list[str]:
    if not files:
        return []
    if any((project_root / name).is_symlink() or "\n" in name for name in files):
        return [_blob_id(project_root / name) for name in files]
    git = subprocess.run(
        ["git", "-C", str(project_root), "hash-object", "--stdin-paths"],
        input="\n".join(files) + "\n", capture_output=True, text=True,
    )
    if git.returncode == 0:
        ids = git.stdout.split()
        if len(ids) == len(files):
            return ids
    return [_blob_id(project_root / name) for name in files]


def _blob_id(path: Path) -> str:
    data = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


@lru_cache(maxsize=None)
def _cached_fingerprint(project_root: Path, roots: tuple[str, ...], work_root: str, stack: tuple) -> dict:
    files = scope_files(project_root, list(roots), work_root)
    digest = hashlib.sha256()
    for name, blob in zip(files, blob_ids(project_root, files)):
        digest.update(f"{name}\0{blob}\n".encode())
    for key, value in stack:
        digest.update(f"stack:{key}\0{value}\n".encode())
    return {
        "algorithm": ALGORITHM,
        "mode": "roots" if roots else "repository",
        "roots": list(roots),
        "work_root": work_root,
        "files": len(files),
        "digest": digest.hexdigest(),
    }


def fingerprint(project_root: Path, roots: list[str], work_root: str) -> dict:
    stack = tuple(sorted(stack_commands(project_root).items()))
    return dict(_cached_fingerprint(project_root, tuple(roots), work_root, stack))


# ── allowed scope (T12) ────────────────────────────────────────────────────


def _meta_fields(item_dir: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    try:
        text = (item_dir / "meta.yml").read_text(errors="replace")
    except OSError:
        return fields
    for line in text.splitlines():
        if line and not line[0].isspace() and ":" in line:
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip().strip("'\"")
    return fields


def _glob_regex(pattern: str) -> re.Pattern:
    """Project-relative POSIX glob: `**` crosses directories, `*` and `?` do not, and a
    trailing `/` means everything under that directory."""
    if pattern.endswith("/"):
        pattern += "**"
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"; i += 3
        elif pattern.startswith("**", i):
            out += ".*"; i += 2
        elif pattern[i] == "*":
            out += "[^/]*"; i += 1
        elif pattern[i] == "?":
            out += "[^/]"; i += 1
        else:
            out += re.escape(pattern[i]); i += 1
    return re.compile(out + r"\Z")


def _git_lines(project_root: Path, *args: str) -> list[str] | None:
    proc = subprocess.run(["git", "-C", str(project_root), *args], capture_output=True)
    if proc.returncode != 0:
        return None
    return [os.fsdecode(raw) for raw in proc.stdout.split(b"\0" if "-z" in args else b"\n") if raw]


DEFAULT_BRANCH_REFS = ("origin/main", "origin/master", "main", "master")


@lru_cache(maxsize=None)
def _repo_view(project_root: Path) -> dict:
    """Per-process Git facts shared by every item's scope check: the project's prefix inside
    the repository, the current branch, the default-branch refs to exclude, and the
    uncommitted paths. One `git status` per status call, not one per item."""
    prefix = (_git_lines(project_root, "rev-parse", "--show-prefix") or [""])[0]
    branch = (_git_lines(project_root, "rev-parse", "--abbrev-ref", "HEAD") or [""])[0]
    remote_head = (_git_lines(project_root, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD") or [""])[0]
    names = [remote_head] if remote_head else []
    names += [ref for ref in DEFAULT_BRANCH_REFS if ref != remote_head]
    default_names = {ref.split("/", 1)[-1] for ref in names}
    # On the default branch every new commit counts, including commits pulled from others:
    # excluding the remote would also hide the item's own pushed commits.
    excluded = [] if branch in default_names else [
        ref for ref in names if _git_lines(project_root, "rev-parse", "--verify", "-q", ref + "^{commit}")]
    uncommitted = [entry[3:] for entry in _git_lines(
        project_root, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames") or []]
    return {"prefix": prefix, "branch": branch, "excluded": excluded,
            "on_default": branch in default_names, "uncommitted": uncommitted}


def _project_relative(name: str, prefix: str) -> str | None:
    """Git prints repository-relative paths; allowed_paths and the work root are relative to
    the project, which can sit below the repository top level."""
    if not prefix:
        return name
    return name[len(prefix):] if name.startswith(prefix) else None


def _is_cache(name: str) -> bool:
    parts = name.split("/")
    return bool(CACHE_DIRS.intersection(parts[:-1]) or parts[-1] in CACHE_FILES
                or parts[-1].startswith(".coverage.") or name.endswith(CACHE_SUFFIXES))


def _scope_pattern(project_root: Path, pattern: str) -> str:
    """`./src` and `/src` mean `src`; a bare name of an existing folder means the folder."""
    pattern = pattern.strip()
    while pattern.startswith("./"):
        pattern = pattern[2:]
    pattern = pattern.lstrip("/")
    if pattern and not any(ch in pattern for ch in "*?[") and not pattern.endswith("/") \
            and (project_root / pattern).is_dir():
        pattern += "/"
    return pattern


def scope_check(project_root: Path, item_dir: Path, shared_range: bool = False) -> dict | None:
    """Changes outside the item's `allowed_paths`, or None when the item declares none.
    Committed: files touched by `<base_commit>..HEAD`, excluding commits already on the
    default branch (`origin/HEAD`, `origin/main`, `origin/master`, `main`, `master`) unless the
    item is on the default branch itself. Uncommitted: the working tree and index, without
    caches. Always allowed: the work root and the generated agent directories. Deletions and
    both sides of a rename count. A committed cache always counts, even inside an allowed
    folder; uncommitted caches do not. A base that is no longer an ancestor of HEAD (a
    rebase) or does not resolve falls back to uncommitted changes."""
    fields = _meta_fields(item_dir)
    raw = fields.get("allowed_paths", "")
    if not raw.strip():
        return None
    patterns = [part.strip() for part in raw.split(",") if part.strip()]
    regexes = [_glob_regex(_scope_pattern(project_root, part)) for part in patterns]
    work_root = work_root_of(project_root)
    base = fields.get("base_commit", "")
    notes: list[str] = []
    committed: set[str] = set()
    checked_range = "uncommitted only"
    if _git_lines(project_root, "rev-parse", "--git-dir") is None:
        return {"allowed_paths": patterns, "range": "none", "violations": [],
                "notes": ["not a Git repository; the scope cannot be checked"]}
    view = _repo_view(project_root)
    if base and _git_lines(project_root, "rev-parse", "--verify", "-q", base + "^{commit}") is not None:
        if subprocess.run(["git", "-C", str(project_root), "merge-base", "--is-ancestor", base, "HEAD"],
                          capture_output=True).returncode == 0:
            args = ["log", "--format=", "--name-only", "--no-renames", "-z", f"{base}..HEAD"]
            if view["excluded"]:
                args += ["--not", *view["excluded"]]
            committed = set(_git_lines(project_root, *args) or [])
            checked_range = f"{base[:12]}..HEAD" + (
                f" excluding {', '.join(view['excluded'])}" if view["excluded"] else "")
            if view["on_default"]:
                notes.append("on the default branch: commits pulled from others since base_commit also count")
        else:
            notes.append(f"base_commit {base[:12]} is not an ancestor of HEAD (rebased); only uncommitted changes are checked")
    elif base:
        notes.append(f"base_commit {base[:12]} does not resolve; only uncommitted changes are checked")
    else:
        notes.append("no base_commit recorded; only uncommitted changes are checked")
    committed = {rel for name in committed if (rel := _project_relative(name, view["prefix"]))}
    uncommitted = {rel for name in view["uncommitted"]
                   if (rel := _project_relative(name, view["prefix"])) and not _is_cache(rel)}

    def allowed(name: str) -> bool:
        return (_under(name, work_root) or name.split("/", 1)[0] in EXCLUDED_TOP
                or any(regex.match(name) for regex in regexes))

    # A committed cache is never an intended change, even inside an allowed folder; both
    # competitors in round 4 flagged exactly that (`__pycache__`).
    violations = sorted({name for name in committed if _is_cache(name) or not allowed(name)}
                        | {name for name in uncommitted if not allowed(name)})
    if shared_range:
        notes.append("several items with allowed_paths share this branch; the list is shown, not attention")
    return {"allowed_paths": patterns, "range": checked_range, "notes": notes, "violations": violations,
            "shared_range": shared_range}


def record(project_root: Path, slug: str, result: str, exit_code: int, checks: int, command: str,
           covers: list[str] | None = None, started_at: str | None = None) -> Path:
    if os.environ.get(RECORD_TOKEN) != "1":
        raise SystemExit("verification evidence is written by verify.sh --work-item, not by hand")
    work_root = work_root_of(project_root)
    item_dir = project_root / work_root / slug
    if not (item_dir / "meta.yml").is_file():
        raise SystemExit(f"verification evidence: no work item `{slug}` under {work_root}")
    for line in (item_dir / "meta.yml").read_text(errors="replace").splitlines():
        if line.strip() == "work_status: queued":
            raise SystemExit(f"verification evidence: `{slug}` is queued; start it first (work-items.sh start {slug})")
    evidence = {
        "schema": SCHEMA,
        "recorded_at": datetime.now(timezone.utc).isoformat(timespec="microseconds"),
        "command": command,
        "result": result,
        "exit_code": exit_code,
        "checks_run": checks,
        "fingerprint": fingerprint(project_root, _record_roots(project_root), work_root),
        "segments": _bind_or_exit(item_dir, covers or []),
        "auto_covers": not covers,
        "reaffirmed": [],
    }
    scope = scope_check(project_root, item_dir)
    if scope is not None:
        evidence["scope"] = scope
        if scope["violations"]:
            shown = ", ".join(scope["violations"][:3])
            more = len(scope["violations"]) - 3
            print(f"scope: {len(scope['violations'])} change(s) outside allowed_paths: {shown}"
                  + (f" and {more} more" if more > 0 else ""), file=sys.stderr)
    if started_at:
        try:
            evidence["started_at"] = datetime.fromisoformat(started_at).astimezone(timezone.utc).isoformat(timespec="microseconds")
        except ValueError:
            evidence["started_at"] = started_at
    target = item_dir / EVIDENCE_FILE
    target.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n")
    _log(item_dir, "verify", result, started_at=evidence.get("started_at"), command=command,
                    checks_run=checks, segments=len(evidence["segments"]))
    return target


def _bind_or_exit(item_dir: Path, covers: list[str]) -> list[dict]:
    try:
        return bind(item_dir, covers)
    except ValueError as exc:
        raise SystemExit(f"verification evidence: {exc}") from exc


def _record_roots(project_root: Path) -> list[str]:
    try:
        return scope_roots(project_root)
    except ValueError as exc:
        raise SystemExit(f"verification evidence: {exc}") from exc


def assess(project_root: Path, item_dir: Path) -> dict:
    path = item_dir / EVIDENCE_FILE
    if not path.is_file():
        return {"state": "unknown", "detail": "no verification evidence"}
    try:
        evidence = json.loads(path.read_text())
        recorded = evidence["fingerprint"]
        roots = [normalize_root(root) for root in recorded["roots"]]
        work_root = str(recorded["work_root"])
        result = evidence["result"]
        files = int(recorded["files"])
    except (ValueError, KeyError, TypeError, AttributeError):
        return {"state": "unknown", "detail": "verification evidence is unreadable"}
    if evidence.get("schema") not in READABLE_SCHEMAS or recorded.get("algorithm") != ALGORITHM:
        return {"state": "unknown", "detail": "verification evidence uses another format; run verify.sh again"}
    if not str(evidence.get("command") or "").strip():
        return {"state": "unknown", "detail": "verification evidence names no test command; run verify.sh again"}
    base = {
        "recorded_at": evidence.get("recorded_at"),
        "command": evidence.get("command"),
        "files": files,
        "scope": {"roots": roots, "work_root": work_root},
        "segments": len(evidence.get("segments") or []),
        "reaffirmed": len(evidence.get("reaffirmed") or []),
    }
    if result != "pass":
        return {**base, "state": "failed", "detail": f"last recorded run: {result}"}
    if files == 0:
        return {**base, "state": "unknown", "detail": "the fingerprint covers no files; check source_roots and tests_root"}
    # Compare with the scope the run recorded, so a later manifest edit cannot hide drift.
    current = fingerprint(project_root, roots, work_root)
    # Segments are checked even when files changed: a changed acceptance segment must not
    # be hidden behind a files-only stale that newer code evidence can cover.
    state, detail = assess_segments(item_dir, evidence.get("segments") or [], evidence.get("schema") == 2 and bool(evidence.get("auto_covers")))
    if state != "current":
        return {**base, "state": state, "stale_kind": "segments", "detail": detail}
    if current["digest"] != recorded.get("digest"):
        return {**base, "state": "stale", "stale_kind": "files",
                "detail": "files or check commands changed after the recorded run"}
    return {**base, "state": "current", "detail": "unchanged since the recorded run"}


class Refused(SystemExit):
    """A confirmation was refused; exit code 2, nothing written."""


def _script_cmd() -> str:
    script = Path(__file__).resolve()
    try:
        return f"python3 {os.path.relpath(script)}"
    except ValueError:
        return f"python3 {script}"


def _root_args(project_root: Path) -> list[str]:
    return [] if Path.cwd().resolve() == project_root else ["--project-root", str(project_root)]


def _git_user(project_root: Path) -> str:
    try:
        name = subprocess.run(["git", "-C", str(project_root), "config", "user.name"],
                              capture_output=True, text=True, check=False).stdout.strip()
    except OSError:
        name = ""
    if not name:
        raise SystemExit("approval: pass --by user:<name>; git config user.name is not set")
    ref = "user:" + re.sub(r"[^A-Za-z0-9._@/:+-]", "", re.sub(r"\s+", "-", name)).strip("-")
    if not APPROVER_REF.fullmatch(ref):
        raise SystemExit("approval: git config user.name has no usable ASCII characters; pass --by user:<name>")
    return ref


def confirm(action: str, args: list[str], summary: list[str], agent_reported: bool,
            quote: str | None, reason: str | None) -> dict:
    """Decide the confirmation level for `approve` or a gated `reaffirm` (T11). Returns the
    fields to record, or raises Refused with both commands to run."""
    if activity is None:
        raise SystemExit(f"{action}: activity.py is missing; cannot check the environment")
    env_vars = activity.agent_env_vars()
    quote = (quote or "").strip() or None
    reason = (reason or "").strip() or None
    if agent_reported:
        if not quote and not reason:
            raise SystemExit(f"{action}: --agent-reported needs --quote \"<the person's words>\" or --reason \"<basis>\"")
        return {"confirmation": "agent-reported", "agent_env": env_vars,
                **({"quote": quote} if quote else {}), **({"basis": reason} if reason else {})}
    if quote:
        raise SystemExit(f"{action}: --quote goes with --agent-reported")
    tty = None
    why = None
    if env_vars:
        why = "agent environment detected: " + ", ".join(env_vars)
    else:
        try:
            tty = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
        except OSError:
            why = "no terminal: /dev/tty cannot be opened"
    if why:
        person = f"{_script_cmd()} {action} {shlex.join(args)}"
        lines = [
            f"{action}: refused, {why}. Nothing was written.",
            "Hand this command to the person to run in their own terminal on this checkout:",
            f"  {person}",
        ]
        if env_vars:
            lines += ["A person whose own terminal sets these variables (Cursor's terminal, CODEX_HOME in a profile) runs:",
                      f"  env {' '.join(f'-u {name}' for name in env_vars)} {person}",
                      "An agent does not run that form, and does not create a terminal to answer the prompt."]
        lines += [
            "Only when the person has no shell on this checkout (for example a cloud chat), an agent records",
            "what the person said in this conversation. Never write words the person did not say:",
            f"  {person} --agent-reported --quote '<the person's words>'",
        ]
        print("\n".join(lines), file=sys.stderr)
        raise Refused(2)
    try:
        os.write(tty, ("\n".join(summary) + "\nType yes to confirm: ").encode())
        answer = b""
        while not answer.endswith(b"\n") and len(answer) < 256:
            chunk = os.read(tty, 1)
            if not chunk:
                break
            answer += chunk
    finally:
        os.close(tty)
    if answer.decode(errors="replace").strip() != "yes":
        raise SystemExit(f"{action}: not confirmed; nothing was written")
    return {"confirmation": "terminal", "agent_env": []}


def approve(project_root: Path, slug: str, by: str | None, covers: list[str],
            agent_reported: bool = False, quote: str | None = None, reason: str | None = None) -> Path:
    if by is None and not agent_reported:
        by = _git_user(project_root)
    if by is None:
        raise SystemExit("approval: --agent-reported needs --by user:<name>")
    if not APPROVER_REF.fullmatch(by):
        raise SystemExit("approval: --by must be a typed reference such as user:<name>")
    item_dir = _item_dir(project_root, slug)
    bound = _bind_or_exit(item_dir, covers)
    if not bound:
        raise SystemExit("approval: nothing to bind; the item has no AC- segments, pass --covers <file>#<ID>")
    args = ["--work-item", slug, "--by", by, *[part for ref in covers for part in ("--covers", ref)],
            *_root_args(project_root)]
    summary = [f"Approve work item {slug} as {by}. Segments and fingerprints:"] + [
        f"  {entry['ref']}  {str(entry['digest'])[:12]}" for entry in bound]
    level = confirm("approve", args, summary, agent_reported, quote, reason)
    approval = {
        "schema": APPROVAL_SCHEMA,
        "approved_at": datetime.now(timezone.utc).isoformat(timespec="microseconds"),
        "by": by,
        **level,
        "agents": activity.detect_agents() if activity else [],
        "segments": bound,
        "auto_covers": not covers,
        "reaffirmed": [],
    }
    verification = assess(project_root, item_dir)
    if verification.get("state") != "current":
        print(f"note: verification is {verification.get('state')}; the approval binds the criteria, "
              "not a passing run", file=sys.stderr)
    target = item_dir / APPROVAL_FILE
    target.write_text(json.dumps(approval, indent=2, ensure_ascii=False) + "\n")
    _log(item_dir, "approve", by=by, segments=len(bound), confirmation=level["confirmation"])
    return target


def _level_of(entry: dict, default: str) -> str:
    value = entry.get("confirmation")
    return value if value in LEVELS else default


def assess_approval(item_dir: Path) -> dict:
    path = item_dir / APPROVAL_FILE
    if not path.is_file():
        return {"state": "n/a"}
    try:
        approval = json.loads(path.read_text())
        bound = list(approval["segments"])
        by = str(approval["by"])
    except (ValueError, KeyError, TypeError):
        return {"state": "unknown", "detail": "approval.json is unreadable"}
    schema = approval.get("schema")
    if isinstance(schema, int) and schema > APPROVAL_SCHEMA:
        return {"state": "unknown", "detail": "approval.json uses a newer format; update the submodule"}
    if schema not in (1, APPROVAL_SCHEMA) or not bound:
        return {"state": "unknown", "detail": "approval.json uses another format or binds nothing"}
    if not APPROVER_REF.fullmatch(by):
        return {"state": "unknown", "detail": f"approval.json approver is not a typed reference: {by}"}
    base = "recorded before levels" if schema == 1 else _level_of(approval, "")
    if not base:
        return {"state": "unknown", "detail": "approval.json has no confirmation level"}
    reaffirmed = list(approval.get("reaffirmed") or [])
    levels = [base] + [_level_of(entry, "recorded before levels" if schema == 1 else "agent-reported")
                       for entry in reaffirmed if isinstance(entry, dict)]
    confirmation = min(levels, key=LEVELS.index)
    state, detail = assess_segments(item_dir, bound, bool(approval.get("auto_covers")))
    return {
        "state": state,
        "detail": detail or f"approved by {by} ({confirmation}); segments unchanged",
        "by": by,
        "approved_at": approval.get("approved_at"),
        "confirmation": confirmation,
        "approved_confirmation": base,
        "quote": approval.get("quote"),
        "basis": approval.get("basis"),
        "segments": len(bound),
        "reaffirmed": len(reaffirmed),
    }


def reaffirm(project_root: Path, slug: str, ref: str, reason: str, agent_reported: bool = False,
             quote: str | None = None, evidence_only: bool = False) -> list[Path]:
    """Accept an edited segment as meaning the same. Only work-item document segments can
    be reaffirmed; the code fingerprint has no such exemption. Changing an approved segment
    needs the same confirmation as `approve` (T11)."""
    if not reason.strip():
        raise SystemExit("reaffirm: --reason is required")
    item_dir = _item_dir(project_root, slug)
    try:
        digest = segment_digest(item_dir, ref)
    except ValueError as exc:
        raise SystemExit(f"reaffirm: {exc}") from exc
    if digest is None:
        raise SystemExit(f"reaffirm: segment not found or ambiguous: {ref}")
    names = (EVIDENCE_FILE,) if evidence_only else (EVIDENCE_FILE, APPROVAL_FILE)
    pending: list[tuple[str, Path, dict]] = []
    for name in names:
        path = item_dir / name
        if not path.is_file():
            continue
        data = json.loads(path.read_text())
        if any(entry.get("ref") == ref and entry.get("digest") != digest for entry in data.get("segments") or []):
            pending.append((name, path, data))
    if not pending:
        raise SystemExit(f"reaffirm: no evidence or approval records a changed {ref}")
    level: dict = {}
    if any(name == APPROVAL_FILE for name, _, _ in pending):
        summary = [f"Reaffirm {ref} in the approval of {slug}: the edited text means the same.",
                   f"  reason: {reason.strip()}", f"  new fingerprint: {digest[:12]}"]
        level = confirm("reaffirm", ["--work-item", slug, "--ref", ref, "--reason", reason.strip(),
                                     *_root_args(project_root)],
                        summary, agent_reported, quote, None if quote else (reason if agent_reported else None))
    updated = []
    for name, path, data in pending:
        for entry in data.get("segments") or []:
            if entry.get("ref") == ref and entry.get("digest") != digest:
                record = {"ref": ref, "from": entry["digest"], "to": digest, "reason": reason.strip(),
                          "at": datetime.now(timezone.utc).isoformat(timespec="microseconds")}
                if name == APPROVAL_FILE:
                    record.update(level)
                data.setdefault("reaffirmed", []).append(record)
                entry["digest"] = digest
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        updated.append(path)
    _log(item_dir, "reaffirm", ref=ref, reason=reason.strip(), confirmation=level.get("confirmation"))
    return updated


def _item_dir(project_root: Path, slug: str) -> Path:
    item_dir = project_root / work_root_of(project_root) / slug
    if not (item_dir / "meta.yml").is_file():
        raise SystemExit(f"no work item `{slug}` under {work_root_of(project_root)}")
    return item_dir


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    rec = sub.add_parser("record", help="internal: called by verify.sh --work-item")
    rec.add_argument("--work-item", required=True)
    rec.add_argument("--result", choices=["pass", "fail", "skipped"], required=True)
    rec.add_argument("--exit-code", type=int, required=True)
    rec.add_argument("--checks", type=int, required=True)
    rec.add_argument("--command-text", default="")
    rec.add_argument("--covers", action="append", default=[])
    rec.add_argument("--started-at")
    rec.add_argument("--project-root", type=Path, default=Path("."))
    appr = sub.add_parser("approve", help="bind an approval to the item's acceptance segments")
    appr.add_argument("--work-item", required=True)
    appr.add_argument("--by", help="typed reference, e.g. user:<name>; not identity verification. "
                      "Defaults to user:<git config user.name> when confirmed at a terminal")
    appr.add_argument("--covers", action="append", default=[])
    appr.add_argument("--agent-reported", action="store_true",
                      help="an agent records the person's approval given in chat; needs --quote or --reason")
    appr.add_argument("--quote", help="the person's words, with --agent-reported")
    appr.add_argument("--reason", help="the basis for the approval, with --agent-reported")
    appr.add_argument("--project-root", type=Path, default=Path("."))
    reaf = sub.add_parser("reaffirm", help="record that an edited segment means the same")
    reaf.add_argument("--work-item", required=True)
    reaf.add_argument("--ref", required=True)
    reaf.add_argument("--reason", required=True)
    reaf.add_argument("--agent-reported", action="store_true",
                      help="for an approved segment: an agent records that the person agreed")
    reaf.add_argument("--quote", help="the person's words, with --agent-reported")
    reaf.add_argument("--evidence-only", action="store_true", help="reaffirm verification.json only")
    reaf.add_argument("--project-root", type=Path, default=Path("."))
    check = sub.add_parser("assess", help="compare evidence with current content")
    check.add_argument("--work-item", required=True)
    check.add_argument("--project-root", type=Path, default=Path("."))
    args = parser.parse_args()
    project_root = args.project_root.resolve()
    if args.command == "record":
        target = record(project_root, args.work_item, args.result, args.exit_code, args.checks,
                        args.command_text, args.covers, args.started_at)
        print(f"verification evidence: {target.relative_to(project_root)} ({args.result})")
        return 0
    if args.command == "approve":
        target = approve(project_root, args.work_item, args.by, args.covers,
                         args.agent_reported, args.quote, args.reason)
        recorded = json.loads(target.read_text())
        print(f"approval: {target.relative_to(project_root)} (by {recorded['by']}, {recorded['confirmation']})")
        return 0
    if args.command == "reaffirm":
        for target in reaffirm(project_root, args.work_item, args.ref, args.reason,
                               args.agent_reported, args.quote, args.evidence_only):
            print(f"reaffirmed {args.ref} in {target.relative_to(project_root)}")
        return 0
    item_dir = project_root / work_root_of(project_root) / args.work_item
    print(json.dumps(assess(project_root, item_dir), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
