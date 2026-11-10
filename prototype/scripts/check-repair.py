#!/usr/bin/env python3
"""Check a candidate map repair without writing either input.

Only explicitly selected, validator-reported scalar fields may change, and never the
G4 decision fields (frozenAt, gap acknowledgedBy). The hash proves which base was
compared; --base-rev REV:PATH also requires those bytes to equal a committed blob.
Neither binds the repair to a human identity.
"""
import argparse
import hashlib
import subprocess
from pathlib import Path

from prototype_contract import load_json, parse_json, pointer, validate_map

MISSING = object()


def changes(before, after, path=""):
    if isinstance(before, dict) and isinstance(after, dict):
        return [change for key in sorted(before.keys() | after.keys())
                for change in changes(before.get(key, MISSING), after.get(key, MISSING), pointer(path, key))]
    if isinstance(before, list) and isinstance(after, list) and len(before) == len(after):
        return [change for i, (old, new) in enumerate(zip(before, after))
                for change in changes(old, new, pointer(path, i))]
    if type(before) is not type(after) or before != after:
        return [(path, before, after)]
    return []


def decision(path):
    """Name the G4 decision recorded at or under a JSON pointer, else None."""
    keys = path.split("/")[1:]  # still escaped, but no ~0/~1 form equals these literal keys
    if keys[:2] == ["meta", "frozenAt"]:
        return "freeze cut"
    if keys[:2] == ["meta", "gaps"] and keys[3:4] == ["acknowledgedBy"]:
        return "accepted gap"
    return None


def git(failure, *args):
    try:
        result = subprocess.run(["git", *args], capture_output=True)
    except OSError as exc:
        raise ValueError(f"--base-rev cannot run git: {exc}") from exc
    if result.returncode:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise ValueError(f"--base-rev {failure}" + (f" ({detail})" if detail else ""))
    return result.stdout


def committed_blob(spec):
    """Raw bytes of PATH in commit REV, resolved in the working directory's repository."""
    rev, _, path = spec.partition(":")
    if not rev or not path or rev.startswith("-"):
        raise ValueError(f"--base-rev must be REV:PATH with a commit REV, got {spec!r}")
    commit = git(f"revision {rev!r} is not a commit", "rev-parse", "--verify", "--quiet", rev + "^{commit}")
    return git(f"path {path!r} is not a file in {rev}", "cat-file", "blob", commit.decode().strip() + ":" + path)


def check(base, candidate, digest, allowed, base_rev=None):
    base_bytes = base.read_bytes()
    if hashlib.sha256(base_bytes).hexdigest() != digest:
        raise ValueError("stale base hash; inspect the current artifact before retrying")
    if base_rev is not None and committed_blob(base_rev) != base_bytes:
        raise ValueError(f"base bytes differ from the committed blob {base_rev}; use that version as --base: "
                         f"git cat-file blob {base_rev} > base.json "
                         "(line-ending conversion in a checkout also changes the bytes)")
    before, after = parse_json(base_bytes.decode("utf-8")), load_json(candidate)
    if isinstance(before, dict) and isinstance(after, dict):
        old_routes, new_routes = before.get("routes"), after.get("routes")
        if isinstance(old_routes, dict) and isinstance(new_routes, dict) and list(old_routes) != list(new_routes):
            raise ValueError("repair changed route order")
    diff = changes(before, after)
    for path in [*(allowed or ()), *(change[0] for change in diff)]:
        recorded = decision(path)
        if recorded:
            raise ValueError(f"{path} is a decision field ({recorded}); "
                             "record it through the actual decision, not a repair")
    reported = {error["path"] for error in validate_map(before)}
    if not allowed or not set(allowed) <= reported:
        raise ValueError("allow paths must name current validator errors")
    if not diff:
        raise ValueError("candidate has no changes")
    for path, old, new in diff:
        if path not in allowed:
            raise ValueError(f"repair changed an unselected field: {path}")
        if any(isinstance(value, (dict, list)) or value is MISSING for value in (old, new)):
            raise ValueError(f"repair requires structural/content authoring, not scalar correction: {path}")
    errors = validate_map(after)
    if errors:
        raise ValueError(f"candidate still fails validation: {errors}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--base-sha256", required=True)
    parser.add_argument("--base-rev", metavar="REV:PATH",
                        help="commit and repository-root path the base bytes must equal")
    parser.add_argument("--allow", action="append", required=True)
    args = parser.parse_args()
    try:
        check(args.base, args.candidate, args.base_sha256, args.allow, args.base_rev)
    except (OSError, ValueError) as exc:
        print(f"FAIL {exc}")
        return 1
    source = "" if args.base_rev is None else f" against committed {args.base_rev}"
    print(f"PASS bounded scalar repair{source}; inputs unchanged, authorization not verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
