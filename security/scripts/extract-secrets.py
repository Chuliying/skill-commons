#!/usr/bin/env python3
"""Extract real hard-coded-secret candidate lines from stdin.

Shared, case-insensitive candidate extractor used by BOTH the worktree scan and the
staged-diff scan in scan-secrets.sh, so the two paths cannot diverge.

Input: one candidate line per stdin line, either `path:line:content` (grep -n) or
`+content` (git diff). For each secret KEYWORD on a line it extracts the value assigned
to THAT keyword and decides whether it is a real secret:

- value forms: single/double/backtick quoted literal (>= 6 chars), or a long unquoted
  token (>= 16 chars) after `=`. A type annotation is tolerated
  (`const password: string = "..."` -> the quoted value is still found).
- matching is case-insensitive (`PASSWORD="..."` is caught).
- suppression (placeholder / example / env-ref words) is evaluated PER keyword+value
  token -- never against the whole line, a comment, or an unrelated identifier.

Prints the original candidate lines that carry at least one non-suppressed real secret.
Writes the total number of suppressed candidates to stderr as a WARN. With no
arguments the exit code is always 0; the caller decides what a non-empty stdout means.
`--health-check` emits a versioned sentinel so the caller can prove this exact engine
was executed instead of treating an empty rc-0 no-op as healthy.
"""

from __future__ import annotations

import re
import sys

HEALTH_SENTINEL = "extract-secrets:v1"

# Keyword tokens, matched as whole words (case-insensitive). Compound forms
# (secret_key, access_token, ...) are listed before the bare forms in the alternation,
# but word-boundary lookarounds make the bare `secret`/`token` not match inside them.
KEYWORDS = re.compile(
    r"(?<![a-z0-9_])"
    r"(?:api[_-]?key|secret[_-]?key|private[_-]?key|access[_-]?token|refresh[_-]?token"
    r"|secret|password|passwd|token|bearer)"
    r"(?![a-z0-9_])",
    re.IGNORECASE,
)
# The value ASSIGNED to a keyword: after the keyword there must be an assignment
# separator (`=`, or `:` for JSON / typed fields) before the value. This prevents a
# keyword that merely appears near a string (e.g. `for token in ("PROTOTYPE_MAP")`)
# from being mistaken for a secret assignment. Tolerates a JSON key-closing quote and
# a type annotation (`password: string = "..."`). Value is a quoted literal (any of
# " ' `, >= 6 chars) or a long unquoted token (>= 16 chars).
ASSIGN = re.compile(
    r"""^\s*["'`]?\s*"""                        # optional JSON key-closing quote
    r"""(?:"""
    r""":\s*(["'`])([^"'`]{6,})\1"""            # `:` (JSON) -> value MUST be quoted
    r"""|"""
    r"""(?::\s*[A-Za-z_][\w.\[\]<>,| ]*)?\s*=\s*"""   # optional type annotation, then `=`
    r"""(?:(["'`])([^"'`]{6,})\3|([A-Za-z0-9_+/.=-]{16,}))"""  # quoted or long unquoted
    r""")"""
)
SUPPRESS = re.compile(
    r"(?:^|[^a-z0-9_])(?:placeholder|example|test|mock|fake)(?:[^a-z0-9_]|$)"
    r"|process\.env|os\.environ|your-|fixture_project",
    re.IGNORECASE,
)
# `type`/`interface` are deliberately NOT suppressors. They were meant to skip TS
# type declarations, but those never reach here: a declared type (`token: string`)
# has no quoted literal >= 6 chars and no unquoted run >= 16, so ASSIGN does not
# match it. Meanwhile the words appear inside real secret values and inside a
# trailing `# type: ignore`, where suppressing them hid genuine findings.

# An env lookup is not itself a secret. The risk is a hard-coded FALLBACK beside
# it -- `os.environ.get("K") or "real-secret"` -- which is the common real-world
# leak. ASSIGN either grabs the lookup expression as the value (process.env.X is a
# long unquoted run) or fails to match at all, so both paths are handled below.
ENV_LOOKUP = re.compile(r"^(?:process\.env|os\.environ|import\.meta\.env)\b")
ASSIGN_ENV = re.compile(
    r"""^\s*["'`]?\s*(?::\s*[A-Za-z_][\w.\[\]<>,| ]*)?\s*[:=]\s*"""
    r"""(?:process\.env|os\.environ|import\.meta\.env)\b"""
)
# A quoted literal reached through a fallback operator, not the lookup's own key.
FALLBACK = re.compile(r"""(?:\|\||\bor\b|\?\?|,)\s*(["'`])([^"'`]{6,})\1""")
GREP_PREFIX = re.compile(r"^[^:]*:\d+:")


def evaluate(content: str) -> tuple[bool, int]:
    """Return (has_real_secret, suppressed_candidate_count) for one line."""
    real = 0
    suppressed = 0
    for km in KEYWORDS.finditer(content):
        rest = content[km.end():]
        m = ASSIGN.match(rest)
        if m is None:
            # The assigned expression is an env lookup, so there is no literal for
            # ASSIGN to capture; a quoted fallback on the same line still is one.
            if ASSIGN_ENV.match(rest) is None:
                continue
            fb = FALLBACK.search(rest)
            if fb is None:
                continue
            value = fb.group(2)
        else:
            # group 2 = JSON-quoted value, group 4 = `=` quoted value, group 5 = unquoted.
            value = m.group(2) or m.group(4) or m.group(5)
            if value is None:
                continue
            if ENV_LOOKUP.match(value):
                fb = FALLBACK.search(rest)
                if fb is None:
                    continue
                value = fb.group(2)
        token = km.group(0) + " " + value
        if SUPPRESS.search(token):
            suppressed += 1
        else:
            real += 1
    return real > 0, suppressed


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args == ["--health-check"]:
        print(HEALTH_SENTINEL)
        return 0
    if args:
        sys.stderr.write(f"ERROR: unsupported argument(s): {' '.join(args)}\n")
        return 2

    total_suppressed = 0
    for raw in sys.stdin:
        line = raw.rstrip("\n")
        content = GREP_PREFIX.sub("", line)
        if content.startswith("+"):
            content = content[1:]
        found, suppressed = evaluate(content)
        total_suppressed += suppressed
        if found:
            print(line)
    if total_suppressed:
        sys.stderr.write(f"WARN: {total_suppressed} suppressed secret candidate(s)\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
