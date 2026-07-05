# Platform detection + context emission. Source this file.

detect_platform() {
  # Best-effort fallback only; generated artifacts pass --platform explicitly.
  if [ -n "${CURSOR_TRACE_ID:-}${CURSOR_PLUGIN_ROOT:-}" ]; then echo "cursor"; return; fi
  if [ -n "${CLAUDECODE:-}${CLAUDE_PLUGIN_ROOT:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]; then echo "claude-code"; return; fi
  if [ -n "${CODEX_SANDBOX:-}${CODEX_HOME:-}" ]; then echo "codex"; return; fi
  echo "text"
}

json_escape() {
  # $1 = string -> JSON-safe (no surrounding quotes)
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

emit() {
  # $1 platform, $2 directive body, $3 warnings (may be empty)
  local platform="$1" body="$2" warns="$3"
  local full="$body"
  if [ -n "$warns" ]; then full="${warns}

${body}"; fi
  if [ "$platform" = "claude-code" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$(json_escape "$full")"
  else
    printf '%s\n' "$full"
  fi
}
