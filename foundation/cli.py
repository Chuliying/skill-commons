"""Thin CLI over the Foundation core (spec Files cli.py).

Closed JSON to stdout, typed exit codes (0 ok, 2 typed failure). No aggregate
parsing or business logic here — dispatch only. There is deliberately no
activation/bind command: activation is consumer-owned (FR-006/AC-009).
"""

import argparse
import base64
import json
import sys

from foundation import core, errors, homelocator

_COMMANDS = ("register", "publish", "resolve", "query", "change-fact")


class _ArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def _emit(obj):
    sys.stdout.write(json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n")


def _parser():
    p = _ArgumentParser(prog="foundation", add_help=False, allow_abbrev=False)
    p.add_argument("--home-config", dest="home_config", required=True)
    p.add_argument("--ref")
    p.add_argument("--relations", default="[]")
    p.add_argument("--expected", default=None)
    p.add_argument("--kind", default=None)
    p.add_argument("--repo-id", dest="repo_id")
    p.add_argument("--locator")
    return p


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        _emit({"error": errors.SCHEMA_ERROR, "detail": "no command"})
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd not in _COMMANDS:
        _emit({"error": errors.SCHEMA_ERROR, "detail": f"unknown command: {cmd}"})
        return 2
    try:
        args = _parser().parse_args(rest)
    except (SystemExit, ValueError):
        _emit({"error": errors.SCHEMA_ERROR, "detail": "bad arguments"})
        return 2

    try:
        location = homelocator.require_home_location(args.home_config)
        git_dir = location["git_dir"]
        if cmd == "register":
            rev = core.register(git_dir, args.repo_id, args.locator, args.expected)
            _emit({"ok": True, "home_revision": rev})
        elif cmd == "publish":
            res = core.publish(
                git_dir,
                location["collection_identity"],
                json.loads(args.ref),
                json.loads(args.relations),
                args.expected,
            )
            _emit({"ok": True, **res})
        elif cmd == "resolve":
            out = core.resolve(git_dir, json.loads(args.ref))
            _emit({
                "ok": True,
                "artifact_ref": out["artifact_ref"],
                "resolution_receipt": out["resolution_receipt"],
                "content_b64": base64.b64encode(out["bytes"]).decode("ascii"),
            })
        elif cmd == "query":
            _emit({"ok": True, **core.query(git_dir, json.loads(args.ref), kind=args.kind)})
        elif cmd == "change-fact":
            _emit({"ok": True, **core.change_fact(git_dir, json.loads(args.ref))})
    except errors.FoundationError as err:
        _emit({"error": err.code, "detail": err.detail})
        return 2
    except errors.Unresolvable as unresolvable:
        _emit(unresolvable.as_fact())
        return 2
    except (ValueError, KeyError, TypeError) as bad:
        _emit({"error": errors.SCHEMA_ERROR, "detail": f"malformed input: {bad}"})
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
