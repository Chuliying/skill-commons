---
name: security
description: |
  安全預檢與範圍化審查協調。Use when: commit 前需要 secrets 預檢、依賴變更需要 audit、
  認證/授權邏輯需要人工審查，或高風險操作需要 on-demand guard。
  觸發關鍵字: security, secrets, 安全檢查, dependency audit, auth review, api key 外洩
source_kind: original
stage: infra
---

# Security Preflight

這個 skill 協調數種不同強度的安全工作，不把它們合併成一個總體結論：

| Scope | 證據類型 | 何時適用 |
|---|---|---|
| Secret preflight | machine-executed heuristic | commit 前或疑似憑證外洩 |
| Dependency audit | conditional machine command | 依賴或 lockfile 有變更，或 release policy 要求 |
| Auth review | scoped manual attestation | 認證、授權、session、token 邏輯有變更 |
| Operation guard | on-demand command result | 明確涉及高風險操作 |

`scan-secrets.sh` 只是 heuristic secret preflight。exit 0 表示規則沒有找到
blocking candidate，不表示程式、依賴、認證或部署整體安全，也不取代人工審查。

## 1. Secret preflight

先從 manifest 取得 source roots、extensions、UI capability 與 framework；manifest
缺席時使用 repo 慣例並明確記錄 fallback。從 consuming repo root 執行：

執行前，將 `<security-skill-dir>` 解析為本輪實際讀取之 `security/SKILL.md`
所在目錄的絕對路徑；不得假設固定 fan-out 或 submodule mount。

```bash
bash <security-skill-dir>/scripts/scan-secrets.sh
bash <security-skill-dir>/scripts/scan-secrets.sh <target-dir>
```

指令最多接受一個 target directory。執行前必須位於 Git worktree；所有 manifest
預設或明確指定的 target 都要存在、可讀、可 traverse、不是 symlink，且 canonical
path 位於目前 Git worktree 內。任一 precondition 失敗時，scanner 會在輸出任何
`CLEAR` 前停止。

Scanner 檢查範圍：

- 常見硬編碼 secret assignment candidate。
- `has_ui: true` 時的 client-exposed env 敏感名稱；前綴由 manifest/framework 決定
  （例：Next.js 的 `NEXT_PUBLIC_`）。
- 可能把 token/key/secret/password 寫入 log 的文字 candidate。
- `.env` 是否依 `git check-ignore` 的實際 Git 規則被排除；註解、只忽略
  `.env.example` 或最後生效的 negation 都不算。
- staged diff 中常見的 secret assignment candidate。

Scanner 不涵蓋：Git history、binary、編碼/混淆 secret、雲端 secret manager 狀態、
dependency vulnerability、完整 data-flow、auth correctness 或 production policy。

Exit code：

- `0`：沒有 blocking heuristic finding；warning 仍需讀取。
- `>0`：找到一個以上 blocking finding group，manifest/config 無法安全判定，或
  `grep`、`git diff --cached`、`git check-ignore` 等必要檢查無法完成。

Findings 必須回報實際 command、scope、exit code 與命中位置；scanner 只輸出位置與
候選類別，不重印可能是真實 credential 的原始值。不要只留下裸的結果詞。

## 2. Dependency audit（獨立條件式 scope）

只有依賴/lockfile 改變或 release policy 明確要求時才執行。從 manifest 取得 package
manager 與 `dependency_audit_cmd`；沒有指令、工具或必要網路權限時記錄 `SKIP` 與原因，
不自動安裝工具、不自行開啟網路，也不把 secret preflight 當成 dependency audit。

Evidence 至少包含：command、lockfile/scope、exit code、finding 數與未執行原因（若有）。

## 3. Auth / authorization review（人工、條件式）

只有本次 change 觸及 auth domain、API authorization、cookie/session 或 token lifecycle
時才啟用。這裡沒有自動 code-review engine；輸出只能是 scoped manual attestation。

檢查：

- authority 是否由可信任的 server-side boundary 建立並 default-deny。
- token/cookie 傳遞、過期、撤銷與錯誤處理是否符合既有 contract。
- log、URL、client-exposed env 與錯誤訊息是否洩漏敏感內容。
- 新增 endpoint 是否有明確 authentication / authorization policy。

記錄必須綁定 change scope（例如 base SHA＋diff command）與 reviewer；裸的 PASS 不足。
未修改 auth surface 時記 `N/A`，不要製造審查結果。

## 4. Operation guard（獨立 on-demand scope）

只有實際要執行高風險操作時才手動啟用：

```bash
echo "rm -rf /data" | bash <security-skill-dir>/hooks/dangerous-op-guard.sh
# exit 0 = 放行；exit 2 = 阻擋
```

Guard 涵蓋的文字模式與 audit log 見
[`hooks/dangerous-op-guard.md`](hooks/dangerous-op-guard.md)。不要把 hook 靜默設成全域
`PreToolUse`；常駐前必須讓使用者知情並確認範圍。只有實際執行 hook 才能記為 evidence。

## Pre-commit 接入

先以 repo 證據確認是否已有 pre-commit framework/hook：

- 已有：確認是否接入 secret preflight；缺少時提出變更，不暗中改 hook。
- 沒有：commit 前手動執行 scanner；不要聲稱 repo 已有自動防護。

## Framework reference

只有 manifest `stack.framework` 匹配時才讀對應 reference：

| Framework | Reference |
|---|---|
| Next.js | [`references/nextjs-security-patterns.md`](references/nextjs-security-patterns.md) |

## Execution Checklist

> 格式慣例見 [CHECKLIST-CONVENTION.md](../CHECKLIST-CONVENTION.md)。各 scope 分開記錄，
> 不輸出一個包住全部的總體安全結論。

```text
Skill: security
Executed At: YYYY-MM-DD HH:MM
Change Scope: [base SHA / diff / files]

Machine evidence:
- Secret preflight: [CLEAR/FINDINGS/SKIP]
  Evidence: [command, target, exit code, finding groups]
- Dependency audit: [CLEAR/FINDINGS/SKIP]
  Evidence: [command, lockfile/scope, exit code, skip reason]

Recorded/manual evidence:
- Auth review: [RECORDED/N/A]
  Evidence: [reviewer, diff scope, findings/resolution]
- Operation guard: [EXECUTED/SKIP]
  Evidence: [command category, exit code, log reference]

Findings: [具體問題 / none in executed scope]
Unverified scopes: [未執行或只能人工判定的項目]
```

只有本次交接需要 durable security report 時，才把這份 checklist 寫入該 report。
