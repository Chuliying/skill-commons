"""Git object access for resolve (spec D-007, FR-005, ERR-004).

Reads bytes from a specific commit OID's tree via `git cat-file blob <oid>:<path>`
against an explicit --git-dir (never the worktree, HEAD, or cwd), and re-verifies
sha256. Paths are validated before any git argument is constructed.
"""

import hashlib
import re
import subprocess

from foundation import errors

_OID_RE = re.compile(r"^[0-9a-fA-F]{7,64}$")


def validate_repo_relative_path(path):
    """Return path or raise Unresolvable(path-escape).

    Rejects absolute paths, parent-dir traversal, and pathspec-magic / rev
    separators so a crafted path cannot escape the tree or inject git syntax.
    """
    if not isinstance(path, str) or path == "":
        raise errors.Unresolvable("path-escape")
    if path.startswith("/") or path.startswith("\\"):
        raise errors.Unresolvable("path-escape")
    if ":" in path or "\x00" in path:
        raise errors.Unresolvable("path-escape")
    parts = path.replace("\\", "/").split("/")
    if any(part == ".." for part in parts):
        raise errors.Unresolvable("path-escape")
    return path


def read_blob(git_dir, commit_oid, path):
    """Return raw blob bytes at commit_oid:path from git_dir's object store.

    Fails closed with Unresolvable(object-missing) if the oid/path/object is
    absent or unreadable. Never reads the worktree or HEAD.
    """
    validate_repo_relative_path(path)
    if not isinstance(commit_oid, str) or not _OID_RE.fullmatch(commit_oid):
        raise errors.Unresolvable("object-missing")
    # commit_oid must name a COMMIT object: an annotated-tag/tree/blob OID is not a
    # valid Artifact Ref commit identity (else one snapshot could carry two identities). #10b
    otype = subprocess.run(
        ["git", "--git-dir", git_dir, "cat-file", "-t", commit_oid],
        capture_output=True, text=True,
    )
    if otype.returncode != 0 or otype.stdout.strip() != "commit":
        raise errors.Unresolvable("object-missing")
    proc = subprocess.run(
        ["git", "--git-dir", git_dir, "cat-file", "blob", f"{commit_oid}:{path}"],
        capture_output=True,
    )
    if proc.returncode != 0:
        raise errors.Unresolvable("object-missing")
    return proc.stdout


def blob_sha256(data):
    """sha256 hex of raw blob bytes."""
    return hashlib.sha256(data).hexdigest()


def resolve_verified(git_dir, commit_oid, path, expected_digest):
    """Return blob bytes iff sha256 matches expected_digest, else fail closed."""
    data = read_blob(git_dir, commit_oid, path)
    if blob_sha256(data) != expected_digest:
        raise errors.Unresolvable("digest-unverifiable")
    return data
