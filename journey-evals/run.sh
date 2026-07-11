#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIOS="personal-feature team-feature brownfield-bug refactor commit-pr"
HARNESS="codex"
MODEL="fable"
SCENARIO="all"
OUTPUT=""
DRY_RUN=0

usage() {
  echo "usage: bash journey-evals/run.sh [--harness codex|claude] [--model name] [--scenario name|all] [--output path] [--dry-run]"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --list) printf '%s\n' $SCENARIOS; exit 0 ;;
    --harness) HARNESS="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --scenario) SCENARIO="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$HARNESS" in codex|claude) ;; *) echo "invalid harness: $HARNESS" >&2; exit 2;; esac
if [ "$SCENARIO" = "all" ]; then
  selected="$SCENARIOS"
elif printf '%s\n' $SCENARIOS | grep -qx "$SCENARIO"; then
  selected="$SCENARIO"
else
  echo "invalid scenario: $SCENARIO" >&2
  exit 2
fi

if [ -z "$OUTPUT" ]; then
  stamp="$(date '+%Y%m%d-%H%M%S')"
  run_root="${SKILL_COMMONS_JOURNEY_ROOT:-$(dirname "$ROOT")/skill-commons-journey-runs}"
  OUTPUT="$run_root/$stamp-$HARNESS-$MODEL"
fi
OUTPUT="$(python3 - "$ROOT" "$OUTPUT" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).expanduser().resolve()
if output == source or source in output.parents:
    print("ERROR: journey output must stay outside the source repository", file=sys.stderr)
    raise SystemExit(2)
print(output)
PY
)"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"

failed=0
for scenario in $selected; do
  run_dir="$OUTPUT/$scenario"
  workspace="$run_dir/workspace"
  mkdir -p "$run_dir"
  cp "$ROOT/journey-evals/scenarios/$scenario/prompt.md" "$run_dir/prompt.md"
  python3 "$ROOT/journey-evals/scripts/setup_fixture.py" \
    --scenario "$scenario" --dest "$workspace" --skills-root "$ROOT"
  baseline_oid="$(git -C "$workspace" rev-parse HEAD)"

  if [ "$DRY_RUN" -eq 1 ]; then
    continue
  fi

  prompt="$(cat "$run_dir/prompt.md")"
  agent_rc=0
  if [ "$HARNESS" = "codex" ]; then
    (cd "$workspace" && codex exec --ephemeral --dangerously-bypass-approvals-and-sandbox -C "$workspace" "$prompt") \
      >"$run_dir/agent.log" 2>&1 || agent_rc=$?
  else
    (cd "$workspace" && claude -p --model "$MODEL" --permission-mode bypassPermissions \
      --dangerously-skip-permissions --no-session-persistence "$prompt") \
      >"$run_dir/agent.log" 2>&1 || agent_rc=$?
  fi
  printf '%s\n' "$agent_rc" > "$run_dir/agent.exit"

  grade_rc=0
  python3 "$ROOT/journey-evals/scripts/grade_journey.py" \
    --scenario "$scenario" --workspace "$workspace" --skills-root "$ROOT" \
    --baseline-oid "$baseline_oid" \
    > "$run_dir/grade.json" || grade_rc=$?
  if [ "$agent_rc" -ne 0 ] || [ "$grade_rc" -ne 0 ]; then
    failed=1
    echo "FAIL $scenario (agent=$agent_rc grade=$grade_rc)"
  else
    echo "PASS $scenario"
  fi
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry-run prepared: $OUTPUT"
  exit 0
fi
echo "journey results: $OUTPUT"
exit "$failed"
