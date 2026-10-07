#!/usr/bin/env python3
"""Check a candidate map repair without writing either input.

Only explicitly selected, validator-reported scalar fields may change. A hash
binds the comparison to the caller's base version, not to a human identity.
"""
import argparse
import hashlib
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


def check(base, candidate, digest, allowed):
    base_bytes = base.read_bytes()
    if hashlib.sha256(base_bytes).hexdigest() != digest:
        raise ValueError("stale base hash; inspect the current artifact before retrying")
    before, after = parse_json(base_bytes.decode("utf-8")), load_json(candidate)
    if isinstance(before, dict) and isinstance(after, dict):
        old_routes, new_routes = before.get("routes"), after.get("routes")
        if isinstance(old_routes, dict) and isinstance(new_routes, dict) and list(old_routes) != list(new_routes):
            raise ValueError("repair changed route order")
    reported = {error["path"] for error in validate_map(before)}
    if not allowed or not set(allowed) <= reported:
        raise ValueError("allow paths must name current validator errors")
    diff = changes(before, after)
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
    parser.add_argument("--allow", action="append", required=True)
    args = parser.parse_args()
    try:
        check(args.base, args.candidate, args.base_sha256, args.allow)
    except (OSError, ValueError) as exc:
        print(f"FAIL {exc}")
        return 1
    print("PASS bounded scalar repair; inputs unchanged, authorization not verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
