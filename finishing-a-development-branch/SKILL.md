---
name: finishing-a-development-branch
description: |
  功能開發完成後的 Branch 收尾流程。當所有測試通過、準備整合時使用。引導完成 merge、PR、保留或放棄等選擇。
  觸發關鍵字: 功能完成, 要 merge, 要開 PR, 開發完成, 結束這個 branch
source: obra/superpowers@d884ae04edebef577e82ff7c4e143debd0bbec99
source_kind: adapted
stage: infra
---

# Finishing a Development Branch — Branch 收尾流程

> 改編自 [obra/superpowers](https://github.com/obra/superpowers)，套用 consuming repo 的 guardrails。
> **與 `superpowers:finishing-a-development-branch` 同名**：本工作流以此 manifest-aware 版為準（讀 manifest Git Workflow / guardrails）。若改用 plugin 版，需自行確認 guardrails 對齊。

## Overview

功能開發完成後，驗證測試 → 呈現選項 → 必要時 closeout 工作項 → 執行選擇 → 清理工作區。

**核心原則：** Verify tests → Present options → Close out before merge/PR → Execute choice → Clean up。

> **Announce at start:** 「我正在使用 finishing-a-development-branch skill 來完成這個 branch。」

---

## The Process

開始前先讀 manifest `Domain Skill Names`。若宣告 `git-workflow`，載入該 project skill，並以其中的專案特有整合階段、ticket 與 protected-branch 規則補充下列通用流程。

### Step 1: 驗證測試通過

```bash
# 使用腳本一鍵執行（推薦）— 內部委託 verify.sh，維護單一來源
bash .agent/skills/_shared/finishing-a-development-branch/scripts/pre-merge.sh
```

或手動執行 manifest `## Stack` 宣告的指令（`typecheck_cmd && lint_cmd && test_cmd`；沒有就問使用者）。例：

<!-- example -->
```bash
<typecheck_cmd> && <lint_cmd> && <test_cmd>
```

> 腳本委託 `verification-before-completion/scripts/verify.sh` 執行，確保 CI 檢查邏輯只維護一處。

**若測試失敗：**

```
測試失敗（N 個錯誤）。合併前必須修復：

[顯示失敗詳情]

必須修復後才能繼續。
```

停止。不進行 Step 2。

**若全部通過：** 繼續 Step 2。

### Step 2: 確認 Base Branch

先讀 manifest 的 `git_workflow.base_branch`；沒有就從 repo 探測或詢問：

```bash
# <base> = manifest git_workflow.base_branch（沒有就探測候選）
git merge-base HEAD "$BASE" 2>/dev/null
```

或詢問：「這個 branch 是從哪個分支切出來的？」（不假設分支名稱）

### Step 3: 呈現選項

這一步是發布核可。先依 [`../GATE-PACKAGE.md`](../GATE-PACKAGE.md) 提供自上個 Gate 的變更、fresh verification/review/security evidence、風險與下列四個決策選項。若存在 work item，使用 `qa-report.md`（無 QA 時用 `implement-report.md`）作為 release stage file，將 release stage 設為 `awaiting-approval`。

**精確呈現以下 4 個選項：**

```
實作完成！你想要怎麼處理？

1. 合併回 <base-branch>（本機 merge）
2. Push 並建立 Pull Request
3. 保留 branch 不動（之後自己處理）
4. 放棄這次的工作

選哪個？
```

**不要加多餘解釋** — 保持選項簡潔。

選項 1／2 是發布核可：先將 release stage 改為 `approved`，再進 Step 4。選項 3 將 release stage 設為 `blocked` 並維持 work item active；選項 4 只有在後續 `discard` 明確確認後才把 work item 標為 `abandoned`。

### Step 4: Work-item Closeout（只適用選項 1／2）

從 manifest 讀取 `paths.work_root`（預設 `docs/work`），定位本 branch 對應的
`<work_root>/<slug>/meta.yml`。若本次工作不屬於 work item，明確記錄 N/A 後繼續；
若存在 work item，merge／PR 前必須：

1. 在 `prd.md` 尾端追加 `## Delivery`：發布日、與 PRD 的顯式偏差（無則寫
   `無`）、`qa-report.md` PASS 連結、已升級的長期資產。
2. 將 `meta.yml` 的 `status` 改為 `shipped`，`updated_at` 更新為目前時間，
   並把已完成 stages 標為 `done` / `validated`。
3. 檢查 `adr.md` / `glossary.md`；仍長期有效的內容升級到專案層 ADR 或
   manifest 指向的 domain model，原件留在 work item 內。

依 [`../ARTIFACTS.md`](../ARTIFACTS.md) 執行。有 `qa-report.md` 時必須為 PASS；
允許只有 `meta.yml` + `implement-report.md` 的 hotfix 時，以其中的新鮮驗證 evidence
取代 QA report，並略過 PRD Delivery 段。驗證未通過或偏差仍未記錄時，停止，
不執行 merge／push；成功時仍須將 `meta.yml` 標記 `shipped`。

選項 3／4 不得標記 `shipped`：保留 branch 時維持 `active`；放棄流程依使用者
確認執行，不先做 closeout。

### Step 5: 執行選擇

#### 選項 1：本機 Merge

若沒有 remote，跳過 fetch 與 remote-tracking fast-forward 檢查，直接從本地
base branch merge。若 `git merge --ff-only origin/<base-branch>` 失敗或本地
base 與 remote 已分歧，停止並回報 divergence，不要繼續 merge。

```bash
# 更新 remote-tracking branch，不改動本地 base
git fetch origin <base-branch>

# 切換到 base branch
git switch <base-branch>

# 檢查本地 base 與 remote 是否可 fast-forward
git rev-list --left-right --count <base-branch>...origin/<base-branch>

# 只有本地 base 無額外 commit 且可 fast-forward 時才更新
git merge --ff-only origin/<base-branch>

# Merge feature branch
git merge <feature-branch>

# 驗證 merge 後的測試（指令讀 manifest stack.test_cmd）
<test_cmd>

# 若測試通過，刪除 feature branch
git branch -d <feature-branch>
```

#### 選項 2：Push 並建立 PR

```bash
# Push branch
git push -u origin <feature-branch>
```

> ⚠️ **Guardrails 提醒**：`gh pr create` 需要用戶確認後才執行
> 請提供以下內容讓用戶複製使用，或確認後代為執行：

```bash
gh pr create \
  --title "<feature 標題>" \
  --body "## Summary
- <變更重點 1>
- <變更重點 2>

## Test Plan
- [ ] <驗證步驟>
" \
  --base <base-branch>
```

#### 選項 3：保留 Branch

回報：「保留 branch `<name>`，未做任何合併或刪除操作。」

#### 選項 4：放棄工作

**先確認：**

```
這將會永久刪除：
- Branch：<name>
- 所有 commits：<list>

請輸入 'discard' 確認。
```

等待精確的 'discard' 文字。

確認後：

```bash
git checkout <base-branch>
git branch -D <feature-branch>
```

---

## Recovery Mode

Use this mode when a branch must return to a verified stable state instead of shipping.

1. Inspect `git status`, affected files, commit/push state, and the last known-good commit.
2. Prefer reversible actions. An uncommitted change may be stashed; a published commit must use `git revert` rather than history rewriting.
3. Before any command that discards work, rewrites history, deletes a branch, or changes remote state, show the exact impact and command, then obtain explicit user confirmation.
4. Never use `reset --hard`, force push, or whole-tree checkout as an automatic recovery shortcut.
5. After recovery, rerun the applicable manifest verification and record a short post-mortem when the failure was material.

Recovery is an alternative branch outcome, not permission to bypass the four closeout choices or their confirmation gates.

---

## Quick Reference

| 選項 | Merge | Push | 保留 Branch | 刪除 Branch |
|------|-------|------|------------|------------|
| 1. 本機 Merge | ✅ | - | - | ✅ |
| 2. 建立 PR | - | ✅ | ✅ | - |
| 3. 保留不動 | - | - | ✅ | - |
| 4. 放棄 | - | - | - | ✅（force） |

---

## ⚠️ 常見錯誤

| 錯誤 | 正確做法 |
|------|---------|
| 跳過測試驗證 | 一定要先跑完所有測試 |
| 問開放式問題 | 精確呈現 4 個選項 |
| 無確認就放棄 | 放棄前要求打 'discard' |
| 強制 push | **絕對禁止** `git push --force`（Guardrails 禁止） |

---

## Red Flags — 禁止

- ❌ 測試失敗還繼續
- ❌ merge 後沒驗證測試
- ❌ 沒有確認就刪除工作
- ❌ `git push --force`（Guardrails 明確禁止）

---

## 🔖 Execution Checklist（必填輸出）

```
📋 Skill: finishing-a-development-branch
📅 執行時間: YYYY-MM-DD HH:MM
🌿 Branch: <feature-branch-name>

Steps:
✅ Step 1: 測試驗證 - [PASS/FAIL]
   └─ type-check: [X errors] | lint: [X errors] | test: [X/Y passed]
✅ Step 2: Base Branch 確認 - [manifest / repo 證據解析值]
✅ Step 3: 呈現選項 - [完成]
✅ Step 4: Work-item Closeout - [完成/N/A（選項 3/4）]
   └─ artifact: [<work_root>/<slug> / N/A]
✅ Step 5: 執行選擇 - [選項: 1/2/3/4]
   └─ 執行結果: [成功/失敗]

📝 備註: [任何特殊狀況]
```

**未輸出 Checklist = 未完成 Skill**

---

## Integration

**Called by:**
- `caveman-review` — code review 通過後觸發
- `subagent-driven-development` — 所有任務完成後
