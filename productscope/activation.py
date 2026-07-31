"""Two-step scope write: inert candidate, then CAS activation (PRD FR-004).

Why two steps. A single commit that both records the decision and references its own
published artifact would need the artifact ref to contain the commit that contains
it. The candidate is therefore committed first and published by Foundation second, and
a separate activation commit performs the parent CAS. That also makes crash recovery
possible: the idempotency key is {candidate Artifact Ref, parent revision}, so a retry
after a lost acknowledgement finds the existing receipt in the lineage and returns the
same revision instead of writing a second one.

This protocol was previously an inline harness inside
tests/py/e2e/test_consumer_contract_checkpoint.py. Keeping two copies would let the
frozen contract and production drift apart, so the test now consumes this module.
"""

import subprocess

from foundation import core, errors as foundation_errors, schema

from .errors import (
    ACTIVATION_GIT_ERROR,
    NeedsRebase,
    ProductScopeError,
    UNPUBLISHED_CANDIDATE,
)

# Product revisions live on their own ref so they cannot be confused with, or
# fast-forwarded by, ordinary branch activity.
SCOPE_REF = "refs/product-scope/head"
RECEIPT_PATH = "activation.json"
_NULL_OID = "0" * 40


def _git(git_dir, args, input_bytes=None):
    return subprocess.run(
        ["git", "--git-dir", git_dir] + args,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def _out(process):
    return process.stdout.decode("utf-8", "replace").strip()


def _checked_output(git_dir, args, input_bytes=None):
    """Run an activation plumbing command that must return an object ID."""
    process = _git(git_dir, args, input_bytes=input_bytes)
    output = _out(process)
    if process.returncode != 0 or not output:
        raise ProductScopeError(
            ACTIVATION_GIT_ERROR, "git %s failed" % args[0]
        )
    return output


def head(git_dir):
    """Current active Product Scope Revision, or None at genesis R0."""
    process = _git(git_dir, ["rev-parse", "--verify", "-q", SCOPE_REF])
    return (_out(process) or None) if process.returncode == 0 else None


def lineage(git_dir):
    """(commit, receipt) pairs newest first. Empty at genesis."""
    process = _git(git_dir, ["rev-list", SCOPE_REF])
    if process.returncode != 0:
        return []
    receipts = []
    for commit in _out(process).split():
        blob = _git(git_dir, ["cat-file", "blob", "%s:%s" % (commit, RECEIPT_PATH)])
        if blob.returncode == 0:
            import json

            receipts.append((commit, json.loads(_out(blob))))
    return receipts


def _activation_key(candidate_ref, parent_revision):
    return (schema.canonical_json(candidate_ref), parent_revision)


def activate(git_dir, foundation_home, candidate_ref, parent_revision):
    """Turn a published candidate into the next Product Scope Revision.

    parent_revision None activates against genesis R0. Raises NeedsRebase on a stale
    parent, leaving the ref unadvanced (the candidate blob/tree/commit are written first
    and become unreachable objects; no revision exists). Raises ProductScopeError(UNPUBLISHED_CANDIDATE) if
    Foundation cannot resolve the candidate, so an active revision can never reference
    an unpublished artifact.
    """
    # Resolvability is Foundation's judgement, not ours, and it is checked before any
    # object is written.
    try:
        core.resolve(foundation_home, candidate_ref)
    except (foundation_errors.Unresolvable, foundation_errors.FoundationError) as exc:
        raise ProductScopeError(
            UNPUBLISHED_CANDIDATE,
            "candidate is not resolvable through Foundation (%s)" % exc,
        )

    key = _activation_key(candidate_ref, parent_revision)
    for commit, receipt in lineage(git_dir):
        if _activation_key(receipt["candidate_ref"], receipt["parent_revision"]) == key:
            # Ack-loss replay: the work already happened, return the same revision.
            return {"scope_revision": commit, **receipt}

    receipt = {
        "candidate_ref": candidate_ref,
        "parent_revision": parent_revision,
        "kind": "activation",
    }
    blob = _checked_output(
        git_dir,
        ["hash-object", "-w", "--stdin"],
        input_bytes=schema.canonical_json(receipt).encode("utf-8"),
    )
    tree = _checked_output(
        git_dir,
        ["mktree"],
        input_bytes=("100644 blob %s\t%s\n" % (blob, RECEIPT_PATH)).encode("utf-8"),
    )
    args = ["commit-tree", tree, "-m", "activate"]
    if parent_revision is not None:
        args += ["-p", parent_revision]
    new_revision = _checked_output(git_dir, args)

    # CAS: update-ref with the expected old value. A concurrent activation moved the
    # ref, so this one performs zero writes to the ref and the proposal must rebase.
    expected_old = parent_revision if parent_revision is not None else _NULL_OID
    if _git(git_dir, ["update-ref", SCOPE_REF, new_revision, expected_old]).returncode != 0:
        # Classify an update-ref failure as stale only after a fresh ref read proves
        # the scope head moved. Other Git failures must not be misreported as CAS.
        current = _git(git_dir, ["rev-parse", "--verify", "-q", SCOPE_REF])
        current_head = _out(current)
        if (
            (current.returncode == 0 and current_head and current_head != parent_revision)
            or (current.returncode == 1 and parent_revision is not None)
        ):
            raise NeedsRebase()
        raise ProductScopeError(ACTIVATION_GIT_ERROR, "git update-ref failed")
    return {"scope_revision": new_revision, **receipt}
