"""Home locator resolution (spec FR-001/D-011, AC-001/AC-003, ERR-005, CH-5).

The home is located from an explicit locator config (`.agent/artifact-home.json`)
— never cwd, auto-search, or a hardcoded global path. Absent config = Foundation
disabled (AC-003, no error, zero ceremony). A malformed/unresolvable config, or
one naming more than one home (split-brain, CH-5), fails closed with HOME_ERROR.
"""

import json
import os
import subprocess

from foundation import errors, schema

CONFIG_BASENAME = os.path.join(".agent", "artifact-home.json")


def _no_duplicate_keys(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError(f"duplicate key in home locator: {key}")
        seen[key] = value
    return seen


def _is_git_dir(path):
    if not isinstance(path, str) or path == "" or not os.path.isdir(path):
        return False
    proc = subprocess.run(
        ["git", "--git-dir", path, "rev-parse", "--git-dir"], capture_output=True
    )
    return proc.returncode == 0


def resolve_home_location(config_path):
    """Resolve the home git dir and canonical identity, or None when disabled.

    Home identity = stable repo_id + repo-relative path (#2/D-011): the config is
    exactly {repo_id, path}, and the home resolves to <anchor repo toplevel>/<path>
    where the anchor is the git repo containing the locator file (deterministic — not
    cwd, not auto-search, not a hardcoded global/absolute path). Raises HOME_ERROR
    (ERR-005) on a malformed/unresolvable config, a global/absolute-path form, or a
    config that names more than one home (split-brain, CH-5).
    """
    if not os.path.exists(config_path):
        return None  # AC-003: no home configured => Foundation disabled.
    try:
        with open(config_path, "r", encoding="utf-8") as handle:
            config = json.load(handle, object_pairs_hook=_no_duplicate_keys)
    except (OSError, ValueError) as exc:
        raise errors.FoundationError(errors.HOME_ERROR, f"unreadable home locator: {exc}")

    if isinstance(config, list):
        raise errors.FoundationError(errors.HOME_ERROR, "split-brain: locator names multiple homes")
    # Home identity = stable repo_id + repo-relative path (D-011/#2). A hardcoded
    # global/absolute path (the old {home_git_dir} form) is NOT a valid identity.
    if not isinstance(config, dict) or set(config) != {"repo_id", "path"}:
        raise errors.FoundationError(
            errors.HOME_ERROR,
            "malformed home locator (expected exactly {repo_id, path}; a global/absolute path is not a valid identity)",
        )
    repo_id, path = config["repo_id"], config["path"]
    try:
        identity = schema.collection_identity(repo_id, path)
    except errors.FoundationError as invalid:
        raise errors.FoundationError(errors.HOME_ERROR, invalid.detail)
    # Anchor = the git repo containing the locator file — deterministic from the config
    # location, not cwd, not auto-search, not a hardcoded global path.
    anchor = os.path.dirname(os.path.abspath(config_path))
    proc = subprocess.run(
        ["git", "-C", anchor, "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        raise errors.FoundationError(errors.HOME_ERROR, "home locator file is not inside a resolvable repo")
    repo_root = os.path.realpath(proc.stdout.strip())
    home_git_dir = os.path.realpath(os.path.join(repo_root, path))
    try:
        contained = os.path.commonpath([repo_root, home_git_dir]) == repo_root
    except ValueError:
        contained = False
    if not contained:
        raise errors.FoundationError(errors.HOME_ERROR, "home path escapes the anchor repo")
    if not _is_git_dir(home_git_dir):
        raise errors.FoundationError(errors.HOME_ERROR, f"home not resolvable at repo-relative path {path!r}")
    return {"git_dir": home_git_dir, "collection_identity": identity}


def resolve_home(config_path):
    """Resolve only the home git dir for read APIs and compatibility."""
    location = resolve_home_location(config_path)
    return None if location is None else location["git_dir"]


def require_home_location(config_path):
    """Resolve the configured home and identity, or fail closed when disabled."""
    location = resolve_home_location(config_path)
    if location is None:
        raise errors.FoundationError(errors.HOME_ERROR, "Foundation home not configured")
    return location


def require_home(config_path):
    """Resolve the home git_dir, or fail closed if the Foundation is disabled."""
    return require_home_location(config_path)["git_dir"]
