# Merge Strategy 選擇指南

跨專案通用的 Branch 合併策略。**不假設固定分支名稱、ticket 格式或整合流程**：開始前先讀 manifest 的 `## Git Workflow`（沒有就問使用者 / 用 repo 慣例）。

> 專案專屬的多階段整合、角色分支、ticket 綁定流程，請放 `project/git-workflow` domain skill（`shared-skill-onboarder` 可 scaffold），不寫在此 shared skill。

---

## 目錄

- [Manifest 來源](#sec-manifest)
- [策略對比](#sec-compare)
- [通用整合流程](#sec-flow)
  - [Feature Branch → Base](#sec-feature-to-base)
  - [Base → Release](#sec-base-to-release)
- [Branch 命名慣例](#sec-naming)
- [常見情境](#sec-scenarios)
  - [Scenario 1: Feature branch 落後 base](#sec-scenario-1)
  - [Scenario 2: Merge conflict](#sec-scenario-2)
  - [Scenario 3: 需要放棄 feature branch](#sec-scenario-3)
- [Guardrails 提醒](#sec-guardrails)

---

<a id="sec-manifest"></a>
## Manifest 來源

| 需要的值 | 讀 manifest 的鍵 | 沒有時 |
|---|---|---|
| 主整合分支 | `git_workflow.base_branch` | 從目前 branch / remote / 最近 commit 推導，仍不確定就問 |
| 分支命名 | `git_workflow.branch_pattern` | 用 repo 既有命名慣例 |
| ticket 格式 | `git_workflow.ticket_pattern` | 無 ticket 制度則略 |
| commit 規範 | `git_workflow.commit_format` | 用 repo 慣例 |
| 整合流程 | `git_workflow.integration_flow` | 預設「feature → base」單階段 |

以下用 `<base>`、`<feature>` 代表 manifest 解析出的值。

---

<a id="sec-compare"></a>
## 策略對比

| 策略 | 歷史 | 適用情境 |
|------|------|---------|
| **Merge** | 保留完整分支歷史 | 功能分支合入 base |
| **Squash Merge** | 壓縮成一個 commit | PR 進 release 分支 |
| **Rebase** | 線性歷史 | 同步最新 base |
| **Force Push** | 改寫歷史 | ❌ 禁止 |

---

<a id="sec-flow"></a>
## 通用整合流程

<a id="sec-feature-to-base"></a>
### Feature Branch → Base

```bash
# 1. 在 feature branch 上確保測試通過
bash .agent/skills/_shared/finishing-a-development-branch/scripts/pre-merge.sh

# 2. 切到 base branch（<base> = manifest git_workflow.base_branch）
git checkout <base>
git pull origin <base>

# 3. Merge feature branch（保留歷史）
git merge <feature>

# 4. 確認 merge 後測試仍通過（指令讀 manifest stack.test_cmd）
<test_cmd>

# 5. Push
git push origin <base>

# 6. 刪除 feature branch
git branch -d <feature>
```

<a id="sec-base-to-release"></a>
### Base → Release

多階段流程依 manifest `git_workflow.integration_flow`（例如 feature → base → release）。通常透過 PR + Squash Merge 讓 release 分支保持線性歷史。

---

<a id="sec-naming"></a>
## Branch 命名慣例

依 manifest `git_workflow.branch_pattern`；沒有就沿用 repo 既有慣例。常見前綴：

| 前綴 | 用途 | 範例 <!-- example --> |
|------|------|------|
| `feature/` | 新功能 | `feature/<ticket>-<slug>` |
| `fix/` | Bug 修復 | `fix/<ticket>-<slug>` |
| `chore/` | 雜項 | `chore/<slug>` |

> `<ticket>` 格式讀 `git_workflow.ticket_pattern`；無 ticket 制度則省略。

---

<a id="sec-scenarios"></a>
## 常見情境

<a id="sec-scenario-1"></a>
### Scenario 1: Feature branch 落後 base

```bash
# 在 feature branch 上
git fetch origin
git rebase origin/<base>  # 使用 rebase 保持線性
```

<a id="sec-scenario-2"></a>
### Scenario 2: Merge conflict

```bash
# merge 後出現 conflict
git status           # 查看 conflict 檔案
# 手動解決 conflict
git add <resolved-files>
git commit           # 完成 merge commit
```

<a id="sec-scenario-3"></a>
### Scenario 3: 需要放棄 feature branch

```bash
# 確認沒有要保留的工作
git stash list       # 檢查 stash
git log              # 確認 commits

# 刪除 branch（本機）
git checkout <base>
git branch -D <feature>

# 刪除 branch（遠端）— 需用戶確認
git push origin --delete <feature>
```

---

<a id="sec-guardrails"></a>
## Guardrails 提醒

- ❌ `git push --force`：**絕對禁止**，會破壞團隊協作
- ❌ 未 review 就 push 進 release 分支：需要 PR
- ✅ 在 feature branch 上自由 rebase/amend
