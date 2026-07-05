#!/bin/bash
# dangerous-op-guard.sh — security skill hook
# PreToolUse hook：攔截高風險 CLI 操作
# 用法：由 .claude/settings.json 中 PreToolUse hook 自動呼叫
#       也可手動：echo "rm -rf /data" | bash dangerous-op-guard.sh
#
# 輸入：從 stdin 讀取即將執行的指令（Claude Code hook 行為）
# 輸出：exit 2 = 阻擋（BLOCK），exit 0 = 放行

set -o pipefail

# 讀取即將執行的指令（從 stdin 或第一個參數）
if [[ -n "$1" ]]; then
  COMMAND="$1"
else
  COMMAND=$(cat)
fi

# 如果指令為空，放行
[[ -z "$COMMAND" ]] && exit 0

# ── 危險模式定義 ──────────────────────────────
declare -a DANGEROUS_PATTERNS=(
  "rm -rf"
  "rm -fr"
  "git push --force"
  "git push -f"
  "DROP TABLE"
  "DROP DATABASE"
  "TRUNCATE"
  "kubectl delete"
  "docker rm -f"
  "docker system prune"
)

BLOCKED=""
RISK=""

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qi "$pattern"; then
    BLOCKED="$pattern"
    case "$pattern" in
      rm*)    RISK="永久刪除檔案/目錄，無法還原" ;;
      *force*|*-f*) RISK="強制覆蓋遠端分支歷史" ;;
      DROP*|TRUNCATE*) RISK="資料庫破壞性操作，資料不可恢復" ;;
      kubectl*) RISK="刪除 Kubernetes 正式環境資源" ;;
      docker*) RISK="強制移除 Docker 容器/映像" ;;
    esac
    break
  fi
done

# 沒有匹配到危險模式 → 放行
if [[ -z "$BLOCKED" ]]; then
  exit 0
fi

# ── 攔截並輸出警告 ────────────────────────────
echo "" >&2
echo "⛔ DANGEROUS OPERATION INTERCEPTED" >&2
echo "───────────────────────────────────" >&2
echo "Command:  $COMMAND" >&2
echo "Pattern:  $BLOCKED" >&2
echo "Risk:     $RISK" >&2
echo "───────────────────────────────────" >&2
echo "" >&2

# ── 寫入審計 log ──────────────────────────────
LOG_DIR="$HOME/.skill-memory/security"
mkdir -p "$LOG_DIR"
echo "{\"date\":\"$(date +%F)\",\"time\":\"$(date +%T)\",\"action\":\"BLOCKED\",\"pattern\":\"$BLOCKED\",\"command\":\"$COMMAND\"}" \
  >> "$LOG_DIR/operations.log"

# exit 2 = BLOCK（Claude Code hook 協議）
exit 2
