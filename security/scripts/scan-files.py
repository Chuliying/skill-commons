#!/usr/bin/env python3
"""Canonical filesystem/search operations for scan-secrets.sh.

This helper replaces external find/grep pipelines with one versioned, stdlib-only
implementation. Successful content searches return rc 0 and a versioned coverage
envelope followed by zero or more ASCII-safe candidate records. Malformed input,
incomplete artifact coverage, or I/O failure returns rc 2 and no clean result.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections.abc import Iterable
from dataclasses import dataclass


HEALTH_SENTINEL = "scan-files:v2"
SEARCH_SENTINEL = "scan-files-search:v2"
EXCLUDED_DIRS = {
    ".git",
    ".agents",
    ".claude",
    ".codex",
    ".cursor",
    "_archive",
    "node_modules",
    "__pycache__",
}
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
EXCLUDED_PATHS = {
    os.path.abspath(os.path.join(SCRIPT_DIR, "scan-secrets.sh")),
    os.path.abspath(os.path.join(SCRIPT_DIR, "extract-secrets.py")),
    os.path.abspath(os.path.join(SCRIPT_DIR, "run-bounded.py")),
    os.path.abspath(os.path.join(SCRIPT_DIR, "scan-files.py")),
    os.path.abspath(
        os.path.join(SCRIPT_DIR, "..", "references", "nextjs-security-patterns.md")
    ),
}
KEYWORD_PREFILTER = re.compile(
    br"api[_-]?key|secret|private[_-]?key|access[_-]?token|refresh[_-]?token"
    br"|passwd|password|token|bearer",
    re.IGNORECASE,
)
LOG_PATTERN = re.compile(
    br"(?:console\.(?:log|info|warn|error)|print\(|logging\.)"
    # Whole-word keywords only. As a bare substring, `key` matched identifiers like
    # `sort_keys=True`, turning every structured-JSON dump into a log-hygiene warning
    # and training readers to ignore the category.
    br".*(?<![a-z0-9_])(?:token|keys?|secret|password|auth)(?![a-z0-9_])",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class SearchResult:
    enumerated: int
    scanned: int
    matches: list[str]


def parse_extensions(raw: str) -> set[str]:
    extensions = {part.lstrip(".") for part in raw.split(",") if part.lstrip(".")}
    if not extensions:
        raise ValueError("at least one source extension is required")
    return extensions


def has_extension(path: str, extensions: set[str]) -> bool:
    suffix = os.path.basename(path).rsplit(".", 1)
    return len(suffix) == 2 and suffix[1] in extensions


def is_scanner_owned_file(path: str) -> bool:
    """Exclude only this scanner copy's exact support files, never a basename."""
    return os.path.abspath(path) in EXCLUDED_PATHS


def raise_walk_error(error: OSError) -> None:
    raise error


def iter_files(
    targets: list[str], extensions: set[str] | None = None
) -> Iterable[str]:
    for target in targets:
        if target.startswith("-"):
            raise ValueError(f"unsafe option-shaped target: {target}")
        if os.path.islink(target):
            raise ValueError(f"symbolic link is not an auditable scan target: {target}")
        if os.path.isfile(target):
            if not is_scanner_owned_file(target) and (
                extensions is None or has_extension(target, extensions)
            ):
                yield target
            continue
        if not os.path.isdir(target):
            raise OSError(f"scan target is not a readable file or directory: {target}")
        for root, directories, filenames in os.walk(
            target, topdown=True, onerror=raise_walk_error, followlinks=False
        ):
            retained_directories: list[str] = []
            for name in directories:
                if name in EXCLUDED_DIRS:
                    continue
                path = os.path.join(root, name)
                if os.path.islink(path):
                    raise ValueError(f"symbolic link inside scan scope: {path}")
                retained_directories.append(name)
            directories[:] = retained_directories
            for filename in filenames:
                path = os.path.join(root, filename)
                if is_scanner_owned_file(path):
                    continue
                if os.path.islink(path):
                    raise ValueError(f"symbolic link inside scan scope: {path}")
                if not os.path.isfile(path):
                    continue
                if extensions is None or has_extension(path, extensions):
                    yield path


def ascii_safe(data: bytes, *, escape_colon: bool = False) -> str:
    """Render one record field without allowing bytes to alter line framing."""
    rendered: list[str] = []
    for value in data:
        printable = 0x20 <= value <= 0x7E
        if printable and value != 0x5C and not (escape_colon and value == 0x3A):
            rendered.append(chr(value))
        else:
            rendered.append(f"\\x{value:02x}")
    return "".join(rendered)


def matching_bytes(files: Iterable[str], pattern: re.Pattern[bytes]) -> SearchResult:
    """Scan every enumerated artifact as opaque bytes or raise before success."""
    paths = list(files)
    matches: list[str] = []
    scanned = 0
    for path in paths:
        with open(path, "rb") as handle:
            data = handle.read()
        scanned += 1
        display_path = ascii_safe(os.fsencode(path), escape_colon=True)
        for number, raw_line in enumerate(data.split(b"\n"), start=1):
            if pattern.search(raw_line):
                matches.append(
                    f"{display_path}:{number}:{ascii_safe(raw_line)}"
                )
    return SearchResult(enumerated=len(paths), scanned=scanned, matches=matches)


def git_bytes(arguments: list[str]) -> bytes:
    result = subprocess.run(
        ["git", *arguments],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        diagnostic = result.stderr.decode("utf-8", errors="replace").strip()
        raise OSError(
            f"git {' '.join(arguments[:2])} failed (exit {result.returncode}): {diagnostic}"
        )
    return result.stdout


def materialize_staged_index(destination: str) -> int:
    """Write raw stage-0 index blobs for changed paths, independent of attributes."""
    if os.path.islink(destination) or not os.path.isdir(destination):
        raise ValueError("staged materialization destination must be a real directory")
    if os.listdir(destination):
        raise ValueError("staged materialization destination must be empty")

    changed_raw = git_bytes(
        [
            "diff",
            "--cached",
            "--name-only",
            "-z",
            # Lowercase `d` excludes only deletions. Type changes and unmerged paths
            # must reach the mode/conflict checks below instead of disappearing.
            "--diff-filter=d",
            "--no-ext-diff",
        ]
    )
    changed_paths = [os.fsdecode(part) for part in changed_raw.split(b"\0") if part]
    if not changed_paths:
        return 0

    entries: dict[str, tuple[str, str]] = {}
    conflicted_paths: set[str] = set()
    for record in git_bytes(["ls-files", "--stage", "-z"]).split(b"\0"):
        if not record:
            continue
        try:
            metadata, raw_path = record.split(b"\t", 1)
            raw_mode, raw_object_id, raw_stage = metadata.split(b" ", 2)
        except ValueError as exc:
            raise ValueError("malformed git index entry") from exc
        path = os.fsdecode(raw_path)
        stage = raw_stage.decode("ascii")
        if stage == "0":
            entries[path] = (raw_mode.decode("ascii"), raw_object_id.decode("ascii"))
        else:
            conflicted_paths.add(path)

    destination_root = os.path.abspath(destination)
    materialized = 0
    for path in changed_paths:
        normalized = os.path.normpath(path)
        if (
            not path
            or os.path.isabs(path)
            or normalized == ".."
            or normalized.startswith(f"..{os.sep}")
        ):
            raise ValueError(f"unsafe staged index path: {path!r}")
        if path in conflicted_paths or path not in entries:
            raise ValueError(f"staged index path has no unambiguous stage-0 blob: {path}")
        mode, object_id = entries[path]
        if mode not in {"100644", "100755"}:
            raise ValueError(f"unsupported staged index mode {mode} for {path}")

        output_path = os.path.abspath(os.path.join(destination_root, normalized))
        if os.path.commonpath([destination_root, output_path]) != destination_root:
            raise ValueError(f"staged index path escapes materialization root: {path}")
        parent = os.path.dirname(output_path)
        os.makedirs(parent, mode=0o700, exist_ok=True)
        blob = git_bytes(["cat-file", "blob", object_id])
        with open(output_path, "xb") as handle:
            handle.write(blob)
        os.chmod(output_path, 0o600)
        materialized += 1
    return materialized


def emit_search_result(result: SearchResult) -> int:
    print(
        f"{SEARCH_SENTINEL}:{result.enumerated}:{result.scanned}:{len(result.matches)}"
    )
    if result.matches:
        sys.stdout.write("\n".join(result.matches) + "\n")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument(
        "mode",
        choices=(
            "count",
            "worktree",
            "client",
            "log",
            "staged",
            "staged-materialize",
            "staged-filter",
        ),
    )
    parser.add_argument("--extensions", default="")
    parser.add_argument("--prefixes", default="")
    parser.add_argument("targets", nargs="*")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args == ["--health-check"]:
        print(HEALTH_SENTINEL)
        return 0
    try:
        parsed = build_parser().parse_args(args)
        if parsed.mode == "staged-filter":
            if parsed.targets or parsed.extensions or parsed.prefixes:
                raise ValueError("staged-filter accepts no targets or options")
            input_lines = [line.rstrip("\n") for line in sys.stdin]
            matches = [line for line in input_lines if line.startswith("+")]
            return emit_search_result(
                SearchResult(len(input_lines), len(input_lines), matches)
            )

        if parsed.mode == "staged-materialize":
            if parsed.extensions or parsed.prefixes or len(parsed.targets) != 1:
                raise ValueError("staged-materialize requires exactly one destination")
            print(materialize_staged_index(parsed.targets[0]))
            return 0

        if parsed.mode == "staged":
            if parsed.extensions or parsed.prefixes or len(parsed.targets) != 1:
                raise ValueError("staged requires exactly one materialized index root")
            return emit_search_result(
                matching_bytes(iter_files(parsed.targets), KEYWORD_PREFILTER)
            )

        extensions = parse_extensions(parsed.extensions)
        if not parsed.targets:
            raise ValueError("at least one scan target is required")
        files = list(iter_files(parsed.targets, extensions))
        if parsed.mode == "count":
            print(len(files))
            return 0
        if parsed.mode == "worktree":
            return emit_search_result(matching_bytes(files, KEYWORD_PREFILTER))
        if parsed.mode == "log":
            return emit_search_result(matching_bytes(files, LOG_PATTERN))
        if not parsed.prefixes:
            raise ValueError("client mode requires --prefixes")
        client_pattern = re.compile(
            rb"(?:"
            + parsed.prefixes.encode("ascii")
            + rb").*(?:KEY|SECRET|TOKEN|PASSWORD|AUTH)"
        )
        return emit_search_result(matching_bytes(files, client_pattern))
    except (OSError, UnicodeError, ValueError, re.error) as exc:
        print(f"scan-files: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
