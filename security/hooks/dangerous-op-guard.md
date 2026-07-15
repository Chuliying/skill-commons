# On-Demand Hook: Dangerous Operation Guard

## 用途

當 `security` skill 被啟用時，可以配置 On-Demand Hook 攔截高風險操作，只在需要時激活，**不影響日常開發流程**。

## 可執行腳本

```bash
# 手動測試
echo "rm -rf /data" | bash <security-skill-dir>/hooks/dangerous-op-guard.sh

# 或帶參數
bash <security-skill-dir>/hooks/dangerous-op-guard.sh "git push --force"
```

> Exit code: `0` = 放行, `2` = 阻擋（Claude Code hook 協議）

## 受保護的操作

| 操作 | 模式 | 風險 |
|------|------|------|
| `rm -rf` | Bash PreToolUse | 永久刪除（無法還原） |
| `git push --force` / `git push -f` | Bash PreToolUse | 強制覆蓋遠端分支 |
| `DROP TABLE` / `TRUNCATE` | Bash PreToolUse | 資料庫破壞性操作 |
| `kubectl delete` | Bash PreToolUse | 刪除正式環境資源 |
| `> /dev/null 2>&1` + 危險指令組合 | Bash PreToolUse | 靜默執行危險操作 |

## 激活時機

只在以下情境激活（On-Demand）：
- 接觸生產環境
- 執行批次刪除操作
- 處理資料庫 migration
- 部署相關任務

**不要將此 hook 設為全域常駐** — 日常開發會頻繁觸發不必要的警告。

## 行為描述

Hook 觸發時，AI 應：

1. **顯示警告**：標明被攔截的操作和潛在風險
2. **要求確認**：請用戶輸入指定確認字串（如 `confirm-delete` 或 `i-understand`）
3. **等待明確指示**：不自動繼續，等待用戶決定
4. **記錄操作**：在 `~/.skill-memory/security/operations.log` 留下審計軌跡

## 範例攔截輸出

```
 DANGEROUS OPERATION INTERCEPTED
───────────────────────────────────
Command: rm -rf /data/uploads/*
Risk:    Permanent deletion, cannot be undone
Scope:   All files in /data/uploads/

Please type exactly "confirm-delete" to proceed, or "cancel" to abort.
```

## Claude Code Hook 設定

```jsonc
// .claude/settings.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "bash <security-skill-dir>/hooks/dangerous-op-guard.sh"
        }]
      }
    ]
  }
}
```

> 此設定激活後會在每次 Bash 執行前檢查，建議僅在高風險作業時啟用。
> 審計 log 自動寫入 `~/.skill-memory/security/operations.log`。
