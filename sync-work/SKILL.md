---
name: sync-work
description: |
  Git 工作同步工具。依專案 manifest 或既有 repository 慣例建立/切換分支、檢查變更、選擇性 stage、commit 與 push。
  觸發關鍵字: /sync-work, 開始工作, 保存進度, commit, push, merge
source_kind: original
stage: infra
---

# Sync Work

提供跨專案的 Git 同步流程。不得假設固定分支名稱、ticket 格式、remote 或角色分支。

> 分工：sync-work 處理**進行中**的存檔/同步（建/切分支、stage、commit、push）。**分支收尾的終局決策**（merge / PR / 保留 / 放棄）交給 `finishing-a-development-branch`。

## Hard Rules

1. 先讀 `.agent/project-manifest.md` 的 `Git Workflow`；沒有該區塊時，從目前 branch、remote 與最近 commit 推導，仍無法確定就詢問使用者。
2. 若 manifest `Domain Skill Names` 宣告 `git-workflow`，先讀該 project skill；專案特有的角色分支、多階段整合與 ticket 規則以它為準。
3. 禁止 `git add .`、`git add -A`；只 stage 本次任務的明確檔案。
4. 禁止未經確認切換、rebase、merge 或 push protected branch。
5. commit 前必須先執行 `verification-before-completion` 與安全檢查。
6. 工作樹中的既有、無關變更屬於使用者，不得混入 commit。

## Manifest Contract

專案可選擇宣告：

```markdown
## Git Workflow
- base_branch: <branch>
- remote: <remote>
- branch_pattern: <pattern>
- ticket_pattern: <pattern or omitted>
- commit_format: <format>
- integration_flow: <source → target stages>
```

未宣告的欄位不自行補預設值。

## Modes

### Start

1. 執行 `git status --short`, `git branch --show-current`, `git remote -v`。
2. 解析 manifest 或現有 repo 慣例，確認 base branch 與 branch naming。
3. 任何會覆蓋或重排工作樹的動作前，先回報影響並取得確認。
4. 建立或切換工作分支後，回報 branch 與 base。

### Save

1. 執行 `git status --short`、`git diff --stat`、`git diff -- <scoped-files>`。
2. 列出本次任務檔案；排除不相關修改與未追蹤檔。
3. 跑專案定義的 verification 與 security gates。
4. 只 stage 明確檔案：

   ```bash
   git add -- <file-1> <file-2>
   ```

5. 依 manifest 或 repo 慣例產生 commit message；規則不明時先詢問。
6. commit 後確認 `git status --short` 與 `git show --stat --oneline HEAD`。
7. 只有使用者要求或 workflow 明確授權時才 push。

### Integrate

1. 從 manifest 的 `integration_flow`、`project/git-workflow` 或使用者指定取得來源與目標；不得假設角色分支或固定 branch。
2. 先 fetch，再顯示 commit 與 diff stat：

   ```bash
   git fetch <remote> <source> <target>
   git log --oneline <target>..<remote>/<source>
   git diff --stat <target>..<remote>/<source>
   ```

3. 使用者確認差異後才 merge/rebase。
4. 衝突時停止並回報，不自行捨棄任何一方修改。
5. 整合後重新跑 verification。

## Completion Report

```text
mode: start | save | integrate
branch: <current>
base/target: <branch>
scoped files: <list>
verification: PASS | FAIL
commit: <sha or N/A>
push: <remote/branch or not requested>
remaining unrelated changes: <list or none>
```
