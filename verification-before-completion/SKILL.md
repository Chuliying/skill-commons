---
name: verification-before-completion
description: Use before claiming work is complete, fixed or passing, and before commits or PRs. Runs the manifest-driven verify script and checks handoff checklists; overrides superpowers:verification-before-completion.
source: obra/superpowers@d884ae04edebef577e82ff7c4e143debd0bbec99
source_kind: adapted
stage: infra
---

# Verification Before Completion

> **與 `superpowers:verification-before-completion` 同名**：本工作流以此版為準（已對齊本 repo 的 verify 流程與 guardrails）。若 plugin 版同時載入，以本版優先。

## Overview

完成宣稱要附上本次變更後實際跑過的驗證輸出。過期或部分的證據會讓使用者以為工作已完成，
回頭重工的成本遠高於多跑一次命令。

## Available Script

`<skill-dir>` = 本檔絕對目錄；不得假設固定 fan-out 或 submodule mount。

```bash
# 一鍵執行 type-check + lint + tests，輸出結構化摘要
bash <skill-dir>/scripts/verify.sh

# 跳過測試（快速檢查）
bash <skill-dir>/scripts/verify.sh --skip-test
```

> 使用腳本取代手動逐一執行命令，每次都能獲得一致的輸出格式。
> 腳本從 consuming repo 的 `.agent/project-manifest.md` 讀取 capability flags 與 stack commands；
> `typed_contracts: false` 時 type-check 為 N/A，不假設 package manager。

## Core Rule

最後一次程式變更之後沒有跑過的驗證，不能拿來宣稱通過。

## The Gate Function

```
Before claiming any status:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the FULL command (fresh, complete)
3. READ: Full output, check exit code, count failures
4. VERIFY: Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. Make the claim, citing the command and result
```

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

## Key Patterns

- **Regression test:** write → run (pass) → revert fix → run (must fail) → restore → run (pass).
  A test that never failed has not been shown to catch the bug.
- **Delegated work:** a subagent's "success" is a claim, not evidence; check the diff and rerun
  the relevant command yourself.
- **Requirements:** re-read the plan or PRD and check each item; passing tests do not show
  that every requirement was implemented.
- **Hedged wording** ("should pass", "looks correct") is a signal that verification has not run yet.
  Run it, or report the status as unverified.

Apply this before commits, PRs, handing off, or moving to the next task.

---

## Execution Checklist 驗證

**當其他 Skill 交接 durable artifact 時，必須驗證該 artifact 內的 Execution Checklist：**

```
驗證項目:
□ Artifact handoff 是否包含 Checklist？（未輸出 = 該交接未完成）
□ 每個 Step 是否有證據？（無證據 = 未執行）
□ Gate 檢查是否有實際執行結果？（無結果 = 未驗證）
□ 備註是否合理？（可疑內容需追問）
```

**Red Flags（需要追問）：**

- 所有 Step 都是「完成」但無證據
- Gate 檢查全部 PASS 但沒有命令輸出
- 備註為空或過於簡單
- 時間戳記不合理（如未來時間）

**驗證失敗時：**

```
要求 AI 重新執行 Skill 並輸出完整 Checklist
```
