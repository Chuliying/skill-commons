"""Git-backed Collection Home + compare-and-swap (spec D-004/D-011, FR-001/003).

home revision = commit OID at refs/foundation/home. All writes are plumbing
(hash-object/mktree/commit-tree/update-ref) so they never touch a worktree or
branch (M8). CAS is `git update-ref <ref> <new> <old>`: a stale expected head
loses the ref lock and is a zero-write STALE_HOME_REVISION (loser's blob/commit
objects are orphaned and unreachable from head). Layout is flat blobs:
`envelope-<digest>.json`, `registry-<repo_id>.json`.
"""

import os
import subprocess

from foundation import errors

HOME_REF = "refs/foundation/home"
_COMMIT_ENV = {
    "GIT_AUTHOR_NAME": "foundation",
    "GIT_AUTHOR_EMAIL": "foundation@local",
    "GIT_COMMITTER_NAME": "foundation",
    "GIT_COMMITTER_EMAIL": "foundation@local",
}


def _run(git_dir, args, input_bytes=None, env_extra=None):
    env = None
    if env_extra:
        env = dict(os.environ)
        env.update(env_extra)
    return subprocess.run(
        ["git", "--git-dir", git_dir, *args],
        input=input_bytes,
        capture_output=True,
        env=env,
    )


def _is_git_dir(git_dir):
    return _run(git_dir, ["rev-parse", "--git-dir"]).returncode == 0


def _zero_oid(git_dir):
    """All-zero OID for a must-not-exist CAS, sized to the repo's object format
    (sha1=40, sha256=64) so bootstrap works in sha256 homes too (#10a)."""
    proc = _run(git_dir, ["rev-parse", "--show-object-format"])
    fmt = proc.stdout.decode().strip() if proc.returncode == 0 else "sha1"
    return "0" * (64 if fmt == "sha256" else 40)


def read_head(git_dir):
    """Return the home commit OID, or None if the ref does not yet exist in a VALID home.

    An unresolvable git dir (or git failure) fails closed with HOME_ERROR (#5) — it must
    never be conflated with an empty home (which would fail open, serving empty facts).
    """
    if not _is_git_dir(git_dir):
        raise errors.FoundationError(errors.HOME_ERROR, "home git dir unresolvable")
    # Reject a symref home: for-each-ref dereferences it, so a symref to a user branch
    # would be accepted as an authoritative Home commit (fail-open). The home ref must be
    # a direct ref (M8). `symbolic-ref -q` exits 0 iff HOME_REF is a symref.
    if _run(git_dir, ["symbolic-ref", "-q", HOME_REF]).returncode == 0:
        raise errors.FoundationError(errors.HOME_ERROR, "home ref must be a direct ref, not a symref")
    proc = _run(
        git_dir,
        ["for-each-ref", "--format=%(objectname) %(refname)", HOME_REF],
    )
    if proc.returncode != 0:
        raise errors.FoundationError(errors.HOME_ERROR, "home ref lookup failed")
    output = proc.stdout.decode().strip()
    if not output:
        if proc.stderr.decode().strip():
            raise errors.FoundationError(errors.HOME_ERROR, "home ref is malformed")
        return None
    fields = output.split()
    if len(fields) != 2 or fields[1] != HOME_REF:
        raise errors.FoundationError(errors.HOME_ERROR, "home ref output is malformed")
    oid = fields[0]
    object_type = _run(git_dir, ["cat-file", "-t", oid])
    if object_type.returncode != 0 or object_type.stdout.decode().strip() != "commit":
        raise errors.FoundationError(
            errors.HOME_ERROR,
            "home ref does not resolve directly to a commit",
        )
    return oid


def _ls_tree(git_dir, head):
    if head is None:
        return {}
    proc = _run(git_dir, ["ls-tree", head])
    if proc.returncode != 0:
        raise errors.FoundationError(errors.HOME_ERROR, "ls-tree failed")
    entries = {}
    for line in proc.stdout.decode().splitlines():
        meta, name = line.split("\t", 1)
        mode, _type, oid = meta.split()
        entries[name] = (mode, oid)
    return entries


def get_entry(git_dir, head, name):
    """Return the blob bytes for `name` at `head`, or None if absent."""
    entries = _ls_tree(git_dir, head)
    if name not in entries:
        return None
    proc = _run(git_dir, ["cat-file", "blob", entries[name][1]])
    if proc.returncode != 0:
        raise errors.FoundationError(errors.HOME_ERROR, "cat-file failed")
    return proc.stdout


def read_state(git_dir, head):
    """Return {name: bytes} for every blob in the home tree at `head`."""
    return {name: get_entry(git_dir, head, name) for name in _ls_tree(git_dir, head)}


def is_ancestor(git_dir, older, newer):
    """True iff `older` is an ancestor of `newer` (append-only lineage check)."""
    return _run(git_dir, ["merge-base", "--is-ancestor", older, newer]).returncode == 0


def _hash_object(git_dir, data):
    proc = _run(git_dir, ["hash-object", "-w", "--stdin"], input_bytes=data)
    if proc.returncode != 0:
        raise errors.FoundationError(errors.HOME_ERROR, "hash-object failed")
    return proc.stdout.decode().strip()


def commit_entries(git_dir, expected_head, new_entries):
    """Atomically add/overwrite `new_entries` (name->bytes) onto expected_head.

    Returns the new home commit OID. Raises STALE_HOME_REVISION (zero reachable
    write) if the home head advanced past expected_head; raises HOME_ERROR if the
    home lineage was rewritten (expected_head is not an ancestor of the current
    head — a force-push/rewind, append-only violation, M8/B2). expected_head None
    means bootstrap: the ref must not already exist (all-zero old-value).
    """
    current = read_head(git_dir)
    if expected_head is not None and current is None:
        raise errors.FoundationError(
            errors.HOME_ERROR, "home ref deleted since expected revision (lineage violation)"
        )
    if expected_head is not None and current is not None and current != expected_head:
        if not is_ancestor(git_dir, expected_head, current):
            raise errors.FoundationError(
                errors.HOME_ERROR,
                "home lineage rewritten (expected revision is not an ancestor of head)",
            )
    entries = dict(_ls_tree(git_dir, expected_head))
    for name, data in new_entries.items():
        entries[name] = ("100644", _hash_object(git_dir, data))

    mktree_input = "".join(
        f"{mode} blob {oid}\t{name}\n" for name, (mode, oid) in entries.items()
    ).encode("utf-8")
    tree_proc = _run(git_dir, ["mktree"], input_bytes=mktree_input)
    if tree_proc.returncode != 0:
        raise errors.FoundationError(
            errors.HOME_ERROR, f"mktree failed: {tree_proc.stderr.decode()}"
        )
    tree = tree_proc.stdout.decode().strip()

    commit_args = ["commit-tree", tree, "-m", "foundation update"]
    if expected_head is not None:
        commit_args += ["-p", expected_head]
    commit_proc = _run(git_dir, commit_args, env_extra=_COMMIT_ENV)
    if commit_proc.returncode != 0:
        raise errors.FoundationError(
            errors.HOME_ERROR, f"commit-tree failed: {commit_proc.stderr.decode()}"
        )
    new_head = commit_proc.stdout.decode().strip()

    old = expected_head if expected_head is not None else _zero_oid(git_dir)
    # --no-deref: operate on refs/foundation/home itself, never follow a (hostile/
    # misconfigured) symref to a user branch (M8 — Foundation must not touch a branch).
    update_proc = _run(git_dir, ["update-ref", "--no-deref", HOME_REF, new_head, old])
    if update_proc.returncode != 0:
        # Lost the CAS. Re-read head to classify atomically (closes the TOCTOU
        # between the pre-check and here): a vanished ref is a lineage violation
        # (retry would silently re-bootstrap a new root and orphan history), not
        # a plain advance that the caller should re-read-and-retry.
        if expected_head is not None and read_head(git_dir) is None:
            raise errors.FoundationError(
                errors.HOME_ERROR, "home ref deleted during publish (lineage violation)"
            )
        raise errors.FoundationError(
            errors.STALE_HOME_REVISION, "home advanced since expected revision"
        )
    return new_head
