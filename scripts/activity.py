#!/usr/bin/env python3
"""Append-only activity log for a work item: `<work_root>/<slug>/activity.jsonl`.

Commands append one JSON line after they succeed (`work-items.sh new`, `start`, `complete`,
`verify.sh --work-item`, `approve`, `reaffirm`). Each line records the time, the event, its result
and the AI tools detected in the environment. The log is written by commands, never by hand.

Tools and sessions come from environment variables the agents set:

- claude-code: `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` or `CLAUDE_PLUGIN_ROOT`; session
  `CLAUDE_CODE_SESSION_ID`; `CLAUDE_CODE_CHILD_SESSION=1` is recorded as `child_session_flag`
  exactly as the environment reports it (it is also set for SDK and desktop sessions, so it does
  not prove a subagent).
- codex: `CODEX_THREAD_ID`, `CODEX_SANDBOX` or `CODEX_HOME`; session `CODEX_THREAD_ID`.
- cursor: `CURSOR_TRACE_ID` or `CURSOR_PLUGIN_ROOT`; no known session variable.

A process inherits its parent's variables, so a Codex run started from Claude Code shows both.
Every detected tool is recorded and none is chosen as "the" tool. CI and a plain terminal record
no tool. `SKILL_COMMONS_SESSION=<id>` records an explicit `session_override`; `SKILL_COMMONS_SESSION=none`
records tools and time without any session id. A Claude Code session id names a transcript in the
user's home directory, so public repositories may prefer `none`.

`approve` and `reaffirm` lines also carry `confirmation` (`terminal` or `agent-reported`, T11). A
terminal confirmation with no detected tool is shown as `person`.

These values are what the agent environment reports. They are not identity verification.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

ACTIVITY_FILE = "activity.jsonl"
SESSION_OVERRIDE = "SKILL_COMMONS_SESSION"
MERGE_HINT = "activity.jsonl merge=union"


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds")


# The variables that mark each tool. `agent_env_vars` and `detect_agents` read the same lists.
AGENT_VARS = {
    "codex": ("CODEX_THREAD_ID", "CODEX_SANDBOX", "CODEX_HOME"),
    "cursor": ("CURSOR_TRACE_ID", "CURSOR_PLUGIN_ROOT"),
    "claude-code": ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_PLUGIN_ROOT"),
}


def agent_env_vars(env: dict | None = None) -> list[str]:
    """Names of the agent variables that are set, in AGENT_VARS order. Some can also be set in a
    person's own shell (`CODEX_HOME` in a profile, `CURSOR_TRACE_ID` in Cursor's terminal)."""
    env = os.environ if env is None else env
    return [name for names in AGENT_VARS.values() for name in names if env.get(name)]


def detect_agents(env: dict | None = None) -> list[dict]:
    env = os.environ if env is None else env
    agents: list[dict] = []
    present = lambda tool: any(env.get(name) for name in AGENT_VARS[tool])  # noqa: E731
    if present("codex"):
        agents.append({"tool": "codex", "session": env.get("CODEX_THREAD_ID") or None})
    if present("cursor"):
        agents.append({"tool": "cursor", "session": None})
    if present("claude-code"):
        entry = {"tool": "claude-code", "session": env.get("CLAUDE_CODE_SESSION_ID") or None}
        if env.get("CLAUDE_CODE_CHILD_SESSION") == "1":
            entry["child_session_flag"] = True
        agents.append(entry)
    if env.get(SESSION_OVERRIDE, "").strip() == "none":
        for entry in agents:
            entry["session"] = None
    return agents


def session_override(env: dict | None = None) -> str | None:
    env = os.environ if env is None else env
    value = env.get(SESSION_OVERRIDE, "").strip()
    return value if value and value != "none" else None


def append(item_dir: Path, event: str, result: str = "ok", **extra) -> None:
    """Write one line. Callers append only after the command has succeeded."""
    line = {"at": now(), "event": event, "result": result, "agents": detect_agents(),
            "session_override": session_override()}
    line = {key: value for key, value in line.items() if value is not None}
    line.update({key: value for key, value in extra.items() if value is not None})
    with (item_dir / ACTIVITY_FILE).open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(line, ensure_ascii=False, sort_keys=True) + "\n")


def read(item_dir: Path) -> tuple[list[dict], int]:
    """Events in file order, plus the number of unreadable lines (merge-conflict markers or
    malformed JSON). A missing log is an empty list."""
    path = item_dir / ACTIVITY_FILE
    if not path.is_file():
        return [], 0
    events: list[dict] = []
    unreadable = 0
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not raw.strip():
            continue
        try:
            value = json.loads(raw)
        except ValueError:
            unreadable += 1
            continue
        if isinstance(value, dict) and isinstance(value.get("event"), str):
            events.append(value)
        else:
            unreadable += 1
    return events, unreadable


def tool_label(agents: list, event: dict | None = None) -> str:
    """`codex+claude-code` style label; `person` for an approval or reaffirm confirmed at a
    terminal with no agent detected (T11); `unknown` when no tool was detected."""
    tools = [str(entry.get("tool")) for entry in agents if isinstance(entry, dict) and entry.get("tool")]
    if tools:
        return "+".join(tools)
    return "person" if (event or {}).get("confirmation") == "terminal" else "unknown"


def event_sessions(event: dict) -> list[str]:
    found = [str(event["session_override"])] if event.get("session_override") else []
    found += [str(entry["session"]) for entry in event.get("agents") or []
              if isinstance(entry, dict) and entry.get("session")]
    return found


def try_append(item_dir: Path, event: str, result: str = "ok", **extra) -> None:
    """append(), but a log that cannot be written never fails the command that succeeded."""
    try:
        append(item_dir, event, result, **extra)
    except OSError as exc:
        print(f"warning: could not write {item_dir / ACTIVITY_FILE}: {exc}", file=sys.stderr)


def summarize(item_dir: Path) -> dict:
    events, unreadable = read(item_dir)
    sessions = sorted({session for event in events for session in event_sessions(event)})
    last = events[-1] if events else None
    return {
        "present": (item_dir / ACTIVITY_FILE).is_file(),
        "events": len(events),
        "unreadable": unreadable,
        "sessions": sessions,
        "last": None if last is None else {
            "at": last.get("at"),
            "event": last.get("event"),
            "result": last.get("result"),
            "tools": tool_label(last.get("agents") or [], last),
            "sessions": event_sessions(last),
        },
        "first_at": events[0].get("at") if events else None,
        "timeline": [
            {key: event.get(key) for key in ("at", "event", "result", "started_at")}
            | {"tools": tool_label(event.get("agents") or [], event), "sessions": event_sessions(event)}
            for event in events
        ],
    }
