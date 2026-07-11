#!/usr/bin/env python3
"""Build and validate a deterministic, Git-scoped repository evidence cache."""

from __future__ import annotations

import argparse
import ast
import hashlib
import io
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import tokenize
from typing import (
    Any,
    Dict,
    Iterable,
    List,
    Mapping,
    MutableMapping,
    Optional,
    Sequence,
    Set,
    Tuple,
)

try:
    import fcntl
except ImportError:  # The no-follow cache contract already requires POSIX.
    fcntl = None


SCHEMA = "repo-map/v1"
SCANNER_VERSION = "1.0.0"
CACHE_KEY = "skill-commons/repo-map/v1"
CACHE_PARTS = tuple(CACHE_KEY.split("/"))
CACHE_LOCK_NAME = f".{CACHE_PARTS[-1]}.lock"
MAX_PARSE_BYTES = 2 * 1024 * 1024
PYTHON_EXTRACTOR = "python_ast_v1"
JS_EXTRACTOR = "js_text_v1"
INVENTORY_EXTRACTOR = "inventory_v1"
SUPPORTED_LANGUAGES = {"python", "javascript", "typescript"}
VALID_COVERAGE = {"complete", "partial", "inventory_only"}
VALID_KINDS = {"file", "symlink", "submodule", "missing"}
VALID_LANGUAGES = SUPPORTED_LANGUAGES | {"other"}
VALID_ANALYSIS = {
    "ok",
    "unsupported",
    "syntax_error",
    "decode_error",
    "skipped_too_large",
    "missing",
}
SHA256_PATTERN = re.compile(r"sha256:[0-9a-f]{64}")


class RepoMapError(RuntimeError):
    """An operational or contract error that should produce exit code 2."""


class CompactArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise RepoMapError(message)


def _json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        + "\n"
    ).encode("utf-8")


def _emit(value: Mapping[str, Any]) -> None:
    sys.stdout.buffer.write(_json_bytes(dict(value)))


def _sha256_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
    except OSError as exc:
        raise RepoMapError(f"cannot read {path.name}: {exc}") from exc
    return "sha256:" + digest.hexdigest()


def _python_runtime() -> str:
    return f"cpython-{sys.version_info.major}.{sys.version_info.minor}"


def _git(repo: Path, args: Sequence[str], *, allow_failure: bool = False) -> bytes:
    command = ["git", "-C", str(repo), *args]
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as exc:
        raise RepoMapError(f"cannot execute Git: {exc}") from exc
    if result.returncode != 0 and not allow_failure:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise RepoMapError(detail or f"Git exited {result.returncode}")
    if result.returncode != 0:
        return b""
    return result.stdout


def _discover_repo(cwd: Path) -> Path:
    inside = _git(cwd, ["rev-parse", "--is-inside-work-tree"]).decode().strip()
    if inside != "true":
        raise RepoMapError("Repo Map requires a Git worktree")
    raw = _git(cwd, ["rev-parse", "--show-toplevel"])
    try:
        return Path(raw.decode("utf-8").strip()).resolve(strict=True)
    except (UnicodeDecodeError, OSError) as exc:
        raise RepoMapError(f"cannot resolve Git worktree root: {exc}") from exc


def _git_dir(repo: Path) -> Path:
    raw_bytes = _git(repo, ["rev-parse", "--absolute-git-dir"])
    try:
        raw = Path(raw_bytes.decode("utf-8").strip())
    except UnicodeDecodeError as exc:
        raise RepoMapError("Git directory path is not valid UTF-8") from exc
    if not raw.is_absolute():
        raise RepoMapError("Git returned a non-absolute private directory")
    try:
        resolved = raw.resolve(strict=True)
    except OSError as exc:
        raise RepoMapError(f"cannot resolve Git private directory: {exc}") from exc
    if not resolved.is_dir():
        raise RepoMapError("Git private directory is not a directory")
    return resolved


def _cache_path(git_dir: Path) -> Path:
    """Return the lexical cache path without resolving cache-owned components."""
    return git_dir.joinpath(*CACHE_PARTS)


def _directory_open_flags() -> int:
    required = ("O_DIRECTORY", "O_NOFOLLOW")
    if any(not hasattr(os, name) for name in required):
        raise RepoMapError("runtime lacks no-follow directory operations")
    return os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)


def _open_private_dir(
    git_dir: Path, parts: Sequence[str], *, create: bool
) -> Optional[int]:
    """Open a Git-private descendant without following cache-owned symlinks."""
    flags = _directory_open_flags()
    try:
        current_fd = os.open(str(git_dir), flags)
    except OSError as exc:
        raise RepoMapError(f"cannot open Git private directory safely: {exc}") from exc

    current_path = git_dir
    try:
        for part in parts:
            current_path = current_path / part
            try:
                component = os.lstat(part, dir_fd=current_fd)
            except FileNotFoundError:
                if not create:
                    os.close(current_fd)
                    return None
                try:
                    os.mkdir(part, mode=0o700, dir_fd=current_fd)
                except FileExistsError:
                    pass
                except OSError as exc:
                    raise RepoMapError(
                        f"cannot create Repo Map cache component {part}: {exc}"
                    ) from exc
                try:
                    component = os.lstat(part, dir_fd=current_fd)
                except OSError as exc:
                    raise RepoMapError(
                        f"cannot verify Repo Map cache component {part}: {exc}"
                    ) from exc
            except OSError as exc:
                raise RepoMapError(
                    f"cannot inspect Repo Map cache component {part}: {exc}"
                ) from exc

            if stat.S_ISLNK(component.st_mode):
                raise RepoMapError(
                    f"unsafe Repo Map cache path: symlink component {current_path}"
                )
            if not stat.S_ISDIR(component.st_mode):
                raise RepoMapError(
                    f"unsafe Repo Map cache path: non-directory component {current_path}"
                )
            try:
                next_fd = os.open(part, flags, dir_fd=current_fd)
            except OSError as exc:
                raise RepoMapError(
                    f"cannot open Repo Map cache component {part} safely: {exc}"
                ) from exc
            os.close(current_fd)
            current_fd = next_fd
        return current_fd
    except Exception:
        os.close(current_fd)
        raise


def _open_cache_dir(git_dir: Path, *, create: bool) -> Optional[int]:
    return _open_private_dir(git_dir, CACHE_PARTS, create=create)


def _open_cache_parent(git_dir: Path, *, create: bool) -> Optional[int]:
    return _open_private_dir(git_dir, CACHE_PARTS[:-1], create=create)


def _normalize_scan_root(repo: Path, requested: str) -> Tuple[Path, str]:
    raw = Path(requested)
    if raw.is_absolute():
        raise RepoMapError("--root must be a repository-relative directory")
    try:
        resolved = (repo / raw).resolve(strict=True)
    except OSError as exc:
        raise RepoMapError(f"scan root does not exist: {requested}") from exc
    try:
        relative = resolved.relative_to(repo)
    except ValueError as exc:
        raise RepoMapError("scan root resolves outside the Git worktree") from exc
    if not resolved.is_dir():
        raise RepoMapError("--root must resolve to a directory")
    normalized = relative.as_posix()
    return resolved, normalized if normalized != "." else "."


def _decode_git_path(raw: bytes) -> str:
    try:
        path = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RepoMapError("Repo Map v1 requires UTF-8 Git paths") from exc
    if path.startswith("/") or "\x00" in path:
        raise RepoMapError("Git returned an invalid repository path")
    return path


def _in_scope(path: str, scan_root: str) -> bool:
    return scan_root == "." or path == scan_root or path.startswith(scan_root + "/")


def _git_entries(repo: Path, scan_root: str) -> List[Tuple[str, Optional[str], Optional[str]]]:
    """Return (path, index mode, index oid) for tracked and visible untracked paths."""
    tracked: MutableMapping[str, Tuple[Optional[str], Optional[str], int]] = {}
    for item in _git(repo, ["ls-files", "--stage", "-z"]).split(b"\0"):
        if not item:
            continue
        try:
            header, raw_path = item.split(b"\t", 1)
            mode_raw, oid_raw, stage_raw = header.split(b" ", 2)
            mode = mode_raw.decode("ascii")
            oid = oid_raw.decode("ascii")
            stage = int(stage_raw)
        except (ValueError, UnicodeDecodeError) as exc:
            raise RepoMapError("cannot parse Git index inventory") from exc
        path = _decode_git_path(raw_path)
        if not _in_scope(path, scan_root):
            continue
        previous = tracked.get(path)
        if previous is None or stage == 0 or (previous[2] != 0 and stage == 2):
            tracked[path] = (mode, oid, stage)

    entries: MutableMapping[str, Tuple[Optional[str], Optional[str]]] = {
        path: (mode, oid) for path, (mode, oid, _stage) in tracked.items()
    }
    for raw_path in _git(repo, ["ls-files", "--others", "--exclude-standard", "-z"]).split(b"\0"):
        if not raw_path:
            continue
        path = _decode_git_path(raw_path)
        if _in_scope(path, scan_root) and path not in entries:
            entries[path] = (None, None)

    return [
        (path, entries[path][0], entries[path][1])
        for path in sorted(entries, key=lambda value: value.encode("utf-8"))
    ]


def _language(path: str) -> str:
    suffix = Path(path).suffix.lower()
    if suffix in {".py", ".pyi"}:
        return "python"
    if suffix in {".js", ".jsx", ".mjs", ".cjs"}:
        return "javascript"
    if suffix in {".ts", ".tsx", ".mts", ".cts"}:
        return "typescript"
    return "other"


def _extractor_for(language: str) -> str:
    if language == "python":
        return PYTHON_EXTRACTOR
    if language in {"javascript", "typescript"}:
        return JS_EXTRACTOR
    return INVENTORY_EXTRACTOR


def _classify(repo: Path, path: str, mode: Optional[str]) -> str:
    candidate = repo / Path(path)
    if mode == "160000":
        return "submodule"
    if not os.path.lexists(str(candidate)):
        return "missing"
    if candidate.is_symlink():
        return "symlink"
    if candidate.is_file():
        return "file"
    return "missing"


def _regular_file_hash_and_bytes(path: Path) -> Tuple[str, Optional[bytes]]:
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise RepoMapError(f"cannot stat repository file {path.name}: {exc}") from exc
    if size > MAX_PARSE_BYTES:
        return _sha256_file(path), None
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise RepoMapError(f"cannot read repository file {path.name}: {exc}") from exc
    return _sha256_bytes(data), data


def _content_for_scan(
    repo: Path,
    path: str,
    kind: str,
    language: str,
) -> Tuple[Optional[str], Optional[bytes]]:
    candidate = repo / Path(path)
    if kind == "file" and language in SUPPORTED_LANGUAGES:
        return _regular_file_hash_and_bytes(candidate)
    return None, None


def _decode_python(data: bytes) -> str:
    try:
        encoding, _ = tokenize.detect_encoding(io.BytesIO(data).readline)
        return data.decode(encoding)
    except (LookupError, SyntaxError, UnicodeDecodeError) as exc:
        raise UnicodeDecodeError("utf-8", b"", 0, 1, str(exc)) from exc


EdgeLocations = MutableMapping[Tuple[str, str, str], Set[int]]


def _add_edge(
    edges: EdgeLocations,
    extractor: str,
    source: str,
    specifier: str,
    line: int,
) -> None:
    if specifier:
        edges.setdefault((extractor, source, specifier), set()).add(line)


def _python_analysis(path: str, data: bytes, edges: EdgeLocations) -> str:
    try:
        text = _decode_python(data)
    except UnicodeDecodeError:
        return "decode_error"
    try:
        tree = ast.parse(text, filename=path)
    except SyntaxError:
        return "syntax_error"
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                _add_edge(edges, PYTHON_EXTRACTOR, path, alias.name, node.lineno)
        elif isinstance(node, ast.ImportFrom):
            specifier = "." * node.level + (node.module or "")
            _add_edge(edges, PYTHON_EXTRACTOR, path, specifier, node.lineno)
    return "ok"


_FROM_LITERAL = re.compile(
    r"^\s*(?:import|export)\b.*?\bfrom\s*([\"'])([^\"'\\\r\n]+)\1"
)
_MULTILINE_TAIL_LITERAL = re.compile(
    r"^\s*}\s*from\s*([\"'])([^\"'\\\r\n]+)\1"
)
_SIDE_EFFECT_LITERAL = re.compile(
    r"^\s*import\s*([\"'])([^\"'\\\r\n]+)\1"
)
_CALL_LITERAL = re.compile(
    r"\b(?:require|import)\s*\(\s*([\"'])([^\"'\\\r\n]+)\1\s*\)"
)


def _js_analysis(path: str, data: bytes, edges: EdgeLocations) -> str:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return "decode_error"
    for line_number, line in enumerate(text.splitlines(), 1):
        stripped = line.lstrip()
        if stripped.startswith(("//", "/*", "*")):
            continue
        for pattern in (_FROM_LITERAL, _MULTILINE_TAIL_LITERAL, _SIDE_EFFECT_LITERAL):
            match = pattern.search(line)
            if match:
                _add_edge(edges, JS_EXTRACTOR, path, match.group(2), line_number)
        for match in _CALL_LITERAL.finditer(line):
            _add_edge(edges, JS_EXTRACTOR, path, match.group(2), line_number)
    return "ok"


def _coverage(inventory: Iterable[Mapping[str, Any]]) -> Dict[str, Any]:
    counts = {
        "analyzed": 0,
        "decode_error": 0,
        "missing": 0,
        "skipped_too_large": 0,
        "syntax_error": 0,
        "total": 0,
        "unsupported": 0,
    }
    supported_count = 0
    has_gap = False
    for record in inventory:
        counts["total"] += 1
        status = record["analysis"]["status"]
        language = record["language"]
        kind = record["kind"]
        if language in SUPPORTED_LANGUAGES and kind in {"file", "missing"}:
            supported_count += 1
        if status == "ok":
            counts["analyzed"] += 1
        elif status in counts:
            counts[status] += 1
            has_gap = True
        else:
            raise RepoMapError(f"unknown analysis status: {status}")
    if supported_count == 0:
        state = "inventory_only"
    elif has_gap:
        state = "partial"
    else:
        state = "complete"
    return {"files": counts, "state": state}


def _edge_records(edges: EdgeLocations) -> List[Dict[str, Any]]:
    records = []
    for (extractor, source, specifier), locations in edges.items():
        records.append(
            {
                "extractor": extractor,
                "from": source,
                "kind": "module_reference",
                "locations": sorted(locations),
                "precision": "syntax_exact"
                if extractor == PYTHON_EXTRACTOR
                else "textual_candidate",
                "specifier": specifier,
            }
        )
    return sorted(
        records,
        key=lambda record: (
            record["from"].encode("utf-8"),
            record["extractor"],
            record["specifier"].encode("utf-8"),
        ),
    )


def _input_digest(
    scan_root: str,
    descriptors: Iterable[Mapping[str, Any]],
) -> str:
    files = []
    for descriptor in descriptors:
        files.append(
            {
                "content_sha256": descriptor.get("input_content_sha256"),
                "kind": descriptor["kind"],
                "language": descriptor["language"],
                "path": descriptor["path"],
            }
        )
    value = {
        "extractors": {
            "javascript": JS_EXTRACTOR,
            "python": {"id": PYTHON_EXTRACTOR, "runtime": _python_runtime()},
        },
        "max_parse_bytes": MAX_PARSE_BYTES,
        "scan_root": scan_root,
        "scanner_version": SCANNER_VERSION,
        "schema": SCHEMA,
        "files": files,
    }
    return _sha256_bytes(_json_bytes(value))


def _scan_snapshot(
    repo: Path,
    scan_root: str,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], str, Dict[str, Any]]:
    inventory: List[Dict[str, Any]] = []
    descriptors: List[Dict[str, Any]] = []
    edges: EdgeLocations = {}
    for path, mode, _oid in _git_entries(repo, scan_root):
        language = _language(path)
        extractor = _extractor_for(language)
        kind = _classify(repo, path, mode)
        content_sha256, parse_bytes = _content_for_scan(repo, path, kind, language)
        if kind == "missing":
            status = "missing"
        elif kind != "file" or language == "other":
            status = "unsupported"
        elif parse_bytes is None:
            status = "skipped_too_large"
        elif language == "python":
            status = _python_analysis(path, parse_bytes, edges)
        else:
            status = _js_analysis(path, parse_bytes, edges)
        inventory.append(
            {
                "analysis": {"extractor": extractor, "status": status},
                "content_sha256": content_sha256,
                "kind": kind,
                "language": language,
                "path": path,
            }
        )
        descriptors.append(
            {
                "input_content_sha256": content_sha256
                if kind == "file" and language in SUPPORTED_LANGUAGES
                else None,
                "kind": kind,
                "language": language,
                "path": path,
            }
        )
    coverage = _coverage(inventory)
    return inventory, _edge_records(edges), _input_digest(scan_root, descriptors), coverage


def _current_input_digest(repo: Path, scan_root: str) -> str:
    descriptors = []
    for path, mode, _oid in _git_entries(repo, scan_root):
        language = _language(path)
        kind = _classify(repo, path, mode)
        content_sha256 = None
        if kind == "file" and language in SUPPORTED_LANGUAGES:
            content_sha256 = _sha256_file(repo / Path(path))
        descriptors.append(
            {
                "input_content_sha256": content_sha256,
                "kind": kind,
                "language": language,
                "path": path,
            }
        )
    return _input_digest(scan_root, descriptors)


def _jsonl_bytes(records: Iterable[Mapping[str, Any]]) -> bytes:
    return b"".join(_json_bytes(dict(record)) for record in records)


def _artifact_lstat(cache_fd: int, name: str) -> Optional[os.stat_result]:
    try:
        value = os.lstat(name, dir_fd=cache_fd)
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise RepoMapError(f"cannot inspect Repo Map artifact {name}: {exc}") from exc
    if stat.S_ISLNK(value.st_mode):
        raise RepoMapError(f"unsafe Repo Map cache artifact: symlink {name}")
    if not stat.S_ISREG(value.st_mode):
        raise RepoMapError(f"unsafe Repo Map cache artifact: non-regular file {name}")
    return value


def _acquire_cache_lock(
    git_dir: Path, *, exclusive: bool, create_parent: bool
) -> Optional[int]:
    """Acquire the shared reader/exclusive writer lock adjacent to the cache."""
    if fcntl is None:
        raise RepoMapError("runtime lacks POSIX file locking")
    parent_fd = _open_cache_parent(git_dir, create=create_parent)
    if parent_fd is None:
        return None
    lock_fd: Optional[int] = None
    flags = os.O_RDWR | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        existing = _artifact_lstat(parent_fd, CACHE_LOCK_NAME)
        if existing is None:
            try:
                lock_fd = os.open(
                    CACHE_LOCK_NAME,
                    flags | os.O_CREAT | os.O_EXCL,
                    0o600,
                    dir_fd=parent_fd,
                )
            except FileExistsError:
                existing = _artifact_lstat(parent_fd, CACHE_LOCK_NAME)
        if lock_fd is None:
            lock_fd = os.open(CACHE_LOCK_NAME, flags, dir_fd=parent_fd)
        opened = os.fstat(lock_fd)
        if not stat.S_ISREG(opened.st_mode):
            raise RepoMapError(
                f"unsafe Repo Map cache lock: non-regular file {CACHE_LOCK_NAME}"
            )
        fcntl.flock(lock_fd, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
        current = _artifact_lstat(parent_fd, CACHE_LOCK_NAME)
        if current is None or (current.st_dev, current.st_ino) != (
            opened.st_dev,
            opened.st_ino,
        ):
            raise RepoMapError("unsafe Repo Map cache lock: path changed while locking")
        acquired_fd = lock_fd
        lock_fd = None
        return acquired_fd
    except RepoMapError:
        raise
    except OSError as exc:
        raise RepoMapError(f"cannot acquire Repo Map cache lock: {exc}") from exc
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
        os.close(parent_fd)


def _atomic_replace(cache_fd: int, name: str, data: bytes) -> None:
    _artifact_lstat(cache_fd, name)
    temporary: Optional[str] = None
    handle_fd: Optional[int] = None
    flags = (
        os.O_WRONLY
        | os.O_CREAT
        | os.O_EXCL
        | os.O_NOFOLLOW
        | getattr(os, "O_CLOEXEC", 0)
    )
    try:
        for _attempt in range(100):
            candidate = f".{name}.{secrets.token_hex(8)}"
            try:
                handle_fd = os.open(candidate, flags, 0o600, dir_fd=cache_fd)
                temporary = candidate
                break
            except FileExistsError:
                continue
        if handle_fd is None or temporary is None:
            raise RepoMapError(f"cannot allocate temporary artifact for {name}")
        with os.fdopen(handle_fd, "wb") as handle:
            handle_fd = None
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        _artifact_lstat(cache_fd, name)
        os.replace(
            temporary,
            name,
            src_dir_fd=cache_fd,
            dst_dir_fd=cache_fd,
        )
        temporary = None
    except OSError as exc:
        raise RepoMapError(f"cannot atomically write {name}: {exc}") from exc
    finally:
        if handle_fd is not None:
            os.close(handle_fd)
        if temporary is not None:
            try:
                os.unlink(temporary, dir_fd=cache_fd)
            except OSError:
                pass


def _head_oid(repo: Path) -> Optional[str]:
    raw = _git(repo, ["rev-parse", "--verify", "HEAD"], allow_failure=True)
    return raw.decode("ascii").strip() if raw else None


def _write_cache(
    git_dir: Path,
    inventory: List[Dict[str, Any]],
    edges: List[Dict[str, Any]],
    meta: Dict[str, Any],
) -> None:
    inventory_bytes = _jsonl_bytes(inventory)
    edges_bytes = _jsonl_bytes(edges)
    meta["artifacts"] = {
        "edges_sha256": _sha256_bytes(edges_bytes),
        "inventory_sha256": _sha256_bytes(inventory_bytes),
    }
    lock_fd = _acquire_cache_lock(git_dir, exclusive=True, create_parent=True)
    assert lock_fd is not None
    try:
        cache_fd = _open_cache_dir(git_dir, create=True)
        assert cache_fd is not None
        try:
            _atomic_replace(cache_fd, "inventory.jsonl", inventory_bytes)
            _atomic_replace(cache_fd, "edges.jsonl", edges_bytes)
            _atomic_replace(cache_fd, "meta.json", _json_bytes(meta))
        finally:
            os.close(cache_fd)
    finally:
        os.close(lock_fd)


def _result(
    command: str,
    cache: Path,
    scan_root: str,
    state: str,
    coverage: Optional[str],
    reasons: Sequence[str],
    **extra: Any,
) -> Dict[str, Any]:
    value: Dict[str, Any] = {
        "cache_path": str(cache),
        "command": command,
        "coverage": coverage,
        "reasons": list(reasons),
        "scan_root": scan_root,
        "state": state,
    }
    value.update(extra)
    return value


def _scan(
    repo: Path, git_dir: Path, scan_root: str, cache: Path
) -> Tuple[Dict[str, Any], int]:
    inventory, edges, input_digest, coverage = _scan_snapshot(repo, scan_root)
    meta = {
        "coverage": coverage,
        "extractors": {
            "javascript": {
                "id": JS_EXTRACTOR,
                "precision": "textual_candidate",
            },
            "python": {
                "id": PYTHON_EXTRACTOR,
                "precision": "syntax_exact",
                "runtime": _python_runtime(),
            },
        },
        "head_oid": _head_oid(repo),
        "input_digest": input_digest,
        "scan_root": scan_root,
        "scanner_version": SCANNER_VERSION,
        "schema": SCHEMA,
    }
    _write_cache(git_dir, inventory, edges, meta)
    return (
        _result(
            "scan",
            cache,
            scan_root,
            "fresh",
            coverage["state"],
            [],
            edges=len(edges),
            files=len(inventory),
            input_digest=input_digest,
        ),
        0,
    )


def _read_artifact(cache_fd: int, name: str) -> bytes:
    _artifact_lstat(cache_fd, name)
    flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        artifact_fd = os.open(name, flags, dir_fd=cache_fd)
    except OSError as exc:
        raise RepoMapError(f"cannot open Repo Map artifact {name}: {exc}") from exc
    try:
        opened = os.fstat(artifact_fd)
        if not stat.S_ISREG(opened.st_mode):
            raise RepoMapError(f"unsafe Repo Map cache artifact: non-regular file {name}")
        with os.fdopen(artifact_fd, "rb") as handle:
            artifact_fd = -1
            return handle.read()
    except OSError as exc:
        raise RepoMapError(f"cannot read Repo Map artifact {name}: {exc}") from exc
    finally:
        if artifact_fd >= 0:
            os.close(artifact_fd)


def _load_json(raw: bytes, name: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RepoMapError(f"invalid {name}: {exc}") from exc


def _read_jsonl(raw: bytes, name: str) -> List[Dict[str, Any]]:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RepoMapError(f"invalid {name}: {exc}") from exc
    if raw and not raw.endswith(b"\n"):
        raise RepoMapError(f"invalid {name}: final newline is missing")
    records = []
    for line in text.splitlines():
        if not line:
            raise RepoMapError(f"invalid {name}: empty record")
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise RepoMapError(f"invalid {name}: {exc}") from exc
        if not isinstance(value, dict):
            raise RepoMapError(f"invalid {name}: record is not an object")
        if _json_bytes(value).decode("utf-8").rstrip("\n") != line:
            raise RepoMapError(f"invalid {name}: record is not canonical JSON")
        records.append(value)
    return records


def _valid_repo_path(value: Any) -> bool:
    return (
        isinstance(value, str)
        and bool(value)
        and not value.startswith("/")
        and all(part not in {"", ".", ".."} for part in value.split("/"))
    )


def _validate_inventory(records: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    required = {"analysis", "content_sha256", "kind", "language", "path"}
    paths = []
    by_path = {}
    for record in records:
        if set(record) != required or not _valid_repo_path(record.get("path")):
            raise RepoMapError("invalid inventory.jsonl: invalid record shape")
        path = record["path"]
        kind = record.get("kind")
        language = record.get("language")
        analysis = record.get("analysis")
        if kind not in VALID_KINDS or language not in VALID_LANGUAGES:
            raise RepoMapError("invalid inventory.jsonl: invalid kind or language")
        if not isinstance(analysis, dict) or set(analysis) != {"extractor", "status"}:
            raise RepoMapError("invalid inventory.jsonl: invalid analysis")
        status = analysis.get("status")
        if analysis.get("extractor") != _extractor_for(language) or status not in VALID_ANALYSIS:
            raise RepoMapError("invalid inventory.jsonl: invalid extractor or status")
        content_hash = record.get("content_sha256")
        supported_file = kind == "file" and language in SUPPORTED_LANGUAGES
        if supported_file:
            if not isinstance(content_hash, str) or not SHA256_PATTERN.fullmatch(content_hash):
                raise RepoMapError("invalid inventory.jsonl: supported file lacks content hash")
            if status not in {"ok", "syntax_error", "decode_error", "skipped_too_large"}:
                raise RepoMapError("invalid inventory.jsonl: invalid supported-file status")
        elif content_hash is not None:
            raise RepoMapError("invalid inventory.jsonl: inventory-only record has content hash")
        elif kind == "missing" and status != "missing":
            raise RepoMapError("invalid inventory.jsonl: missing path has invalid status")
        elif kind != "missing" and status != "unsupported":
            raise RepoMapError("invalid inventory.jsonl: inventory-only path has invalid status")
        paths.append(path)
        by_path[path] = record
    expected_paths = sorted(paths, key=lambda value: value.encode("utf-8"))
    if paths != expected_paths or len(paths) != len(set(paths)):
        raise RepoMapError("invalid inventory.jsonl: paths are not uniquely sorted")
    return by_path


def _validate_edges(
    records: List[Dict[str, Any]], inventory: Mapping[str, Dict[str, Any]]
) -> None:
    required = {"extractor", "from", "kind", "locations", "precision", "specifier"}
    keys = []
    for record in records:
        if set(record) != required or not _valid_repo_path(record.get("from")):
            raise RepoMapError("invalid edges.jsonl: invalid record shape")
        extractor = record.get("extractor")
        source = record["from"]
        precision = record.get("precision")
        expected_precision = (
            "syntax_exact" if extractor == PYTHON_EXTRACTOR else "textual_candidate"
        )
        locations = record.get("locations")
        if extractor not in {PYTHON_EXTRACTOR, JS_EXTRACTOR} or precision != expected_precision:
            raise RepoMapError("invalid edges.jsonl: invalid extractor precision")
        if (
            source not in inventory
            or inventory[source]["analysis"]["extractor"] != extractor
            or inventory[source]["analysis"]["status"] != "ok"
        ):
            raise RepoMapError("invalid edges.jsonl: source is absent or incompatible")
        if record.get("kind") != "module_reference" or not isinstance(record.get("specifier"), str):
            raise RepoMapError("invalid edges.jsonl: invalid module reference")
        if not record["specifier"]:
            raise RepoMapError("invalid edges.jsonl: empty specifier")
        if (
            not isinstance(locations, list)
            or not locations
            or any(
                not isinstance(line, int) or isinstance(line, bool) or line < 1
                for line in locations
            )
            or locations != sorted(set(locations))
        ):
            raise RepoMapError("invalid edges.jsonl: locations are not positive and sorted")
        keys.append((source.encode("utf-8"), extractor, record["specifier"].encode("utf-8")))
    if keys != sorted(keys) or len(keys) != len(set(keys)):
        raise RepoMapError("invalid edges.jsonl: records are not uniquely sorted")


def _read_meta(cache_fd: int) -> Tuple[Optional[Dict[str, Any]], str, List[str]]:
    names = ("meta.json", "inventory.jsonl", "edges.jsonl")
    present = [_artifact_lstat(cache_fd, name) is not None for name in names]
    if not all(present):
        return None, "corrupt", ["incomplete_artifact_set"]
    try:
        meta_bytes = _read_artifact(cache_fd, "meta.json")
        inventory_bytes = _read_artifact(cache_fd, "inventory.jsonl")
        edges_bytes = _read_artifact(cache_fd, "edges.jsonl")
        meta = _load_json(meta_bytes, "meta.json")
    except RepoMapError:
        return None, "corrupt", ["invalid_meta"]
    if not isinstance(meta, dict):
        return None, "corrupt", ["invalid_meta"]
    if meta.get("schema") != SCHEMA:
        return meta, "incompatible", ["schema_mismatch"]
    if "scanner_version" not in meta:
        return meta, "corrupt", ["missing_scanner_version"]
    if meta.get("scanner_version") != SCANNER_VERSION:
        return meta, "incompatible", ["scanner_version_mismatch"]
    required = {"artifacts", "coverage", "input_digest", "scan_root"}
    if not required.issubset(meta):
        return meta, "corrupt", ["missing_meta_field"]
    coverage = meta.get("coverage")
    if (
        not isinstance(coverage, dict)
        or coverage.get("state") not in VALID_COVERAGE
        or not isinstance(coverage.get("files"), dict)
    ):
        return meta, "corrupt", ["invalid_coverage"]
    artifacts = meta.get("artifacts")
    if not isinstance(artifacts, dict):
        return meta, "corrupt", ["invalid_artifact_checksums"]
    expected_inventory = artifacts.get("inventory_sha256")
    expected_edges = artifacts.get("edges_sha256")
    if not all(
        isinstance(value, str) and SHA256_PATTERN.fullmatch(value)
        for value in (expected_inventory, expected_edges)
    ):
        return meta, "corrupt", ["invalid_artifact_checksums"]
    actual_inventory = _sha256_bytes(inventory_bytes)
    actual_edges = _sha256_bytes(edges_bytes)
    if actual_inventory != expected_inventory or actual_edges != expected_edges:
        return meta, "corrupt", ["artifact_checksum_mismatch"]
    try:
        inventory_records = _read_jsonl(inventory_bytes, "inventory.jsonl")
        inventory = _validate_inventory(inventory_records)
        _validate_edges(_read_jsonl(edges_bytes, "edges.jsonl"), inventory)
    except RepoMapError:
        return meta, "corrupt", ["invalid_jsonl"]
    if _coverage(inventory_records) != coverage:
        return meta, "corrupt", ["coverage_mismatch"]
    if not isinstance(meta.get("input_digest"), str) or not re.fullmatch(
        SHA256_PATTERN, meta["input_digest"]
    ):
        return meta, "corrupt", ["invalid_input_digest"]
    if not isinstance(meta.get("scan_root"), str):
        return meta, "corrupt", ["invalid_scan_root"]
    return meta, "valid", []


def _status(
    repo: Path, git_dir: Path, scan_root: str, cache: Path
) -> Tuple[Dict[str, Any], int]:
    lock_fd = _acquire_cache_lock(git_dir, exclusive=False, create_parent=False)
    if lock_fd is None:
        meta, artifact_state, reasons = None, "missing", []
    else:
        try:
            cache_fd = _open_cache_dir(git_dir, create=False)
            if cache_fd is None:
                meta, artifact_state, reasons = None, "missing", []
            else:
                try:
                    meta, artifact_state, reasons = _read_meta(cache_fd)
                finally:
                    os.close(cache_fd)
        finally:
            os.close(lock_fd)
    if artifact_state == "missing":
        return _result("status", cache, scan_root, "missing", None, reasons), 1
    coverage = None
    if meta and isinstance(meta.get("coverage"), dict):
        coverage = meta["coverage"].get("state")
    if artifact_state in {"corrupt", "incompatible"}:
        return _result("status", cache, scan_root, artifact_state, coverage, reasons), 2
    assert meta is not None
    if meta["scan_root"] != scan_root:
        return (
            _result(
                "status", cache, scan_root, "stale", coverage, ["scan_root_mismatch"]
            ),
            1,
        )
    current_digest = _current_input_digest(repo, scan_root)
    if current_digest != meta["input_digest"]:
        return (
            _result(
                "status",
                cache,
                scan_root,
                "stale",
                coverage,
                ["input_digest_changed"],
                input_digest=current_digest,
            ),
            1,
        )
    return (
        _result(
            "status",
            cache,
            scan_root,
            "fresh",
            coverage,
            [],
            input_digest=current_digest,
        ),
        0,
    )


def _parser() -> CompactArgumentParser:
    parser = CompactArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("scan", "status"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument(
            "--root",
            default=".",
            help="repository-relative directory to scan (default: .)",
        )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    command = "unknown"
    cache: Optional[Path] = None
    requested_root = "."
    try:
        args = _parser().parse_args(argv)
        command = args.command
        requested_root = args.root
        repo = _discover_repo(Path.cwd())
        git_dir = _git_dir(repo)
        cache = _cache_path(git_dir)
        _resolved_root, scan_root = _normalize_scan_root(repo, requested_root)
        if command == "scan":
            result, exit_code = _scan(repo, git_dir, scan_root, cache)
        else:
            result, exit_code = _status(repo, git_dir, scan_root, cache)
        _emit(result)
        return exit_code
    except RepoMapError as exc:
        print(f"repo-map: {exc}", file=sys.stderr)
        _emit(
            {
                "cache_path": str(cache) if cache is not None else None,
                "command": command,
                "coverage": None,
                "error": str(exc),
                "reasons": ["runtime_error"],
                "scan_root": requested_root,
                "state": "error",
            }
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
