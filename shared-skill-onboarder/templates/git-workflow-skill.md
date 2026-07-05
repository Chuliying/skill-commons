# Scaffold: project/git-workflow domain skill

> `shared-skill-onboarder` 用此模板，在 consuming repo 的 `.agent/skills/project/git-workflow/SKILL.md`
> scaffold 一個專案專屬 git 流程 domain skill。**只有當專案 git 流程複雜時才建立**
> （多階段整合、角色分支、ticket 綁定）。簡單流程靠 manifest `## Git Workflow` 即可，不需要這支 skill。

把以下內容寫入 `.agent/skills/project/git-workflow/SKILL.md`，並把 `<...>` 換成從 repo 觀察到的真實值：

```markdown
---
name: git-workflow
description: |
  本專案的 Git 整合流程（分支、ticket、整合階段、角色分支）。Use when: 收尾 branch、merge、整合、開 PR 時需要專案專屬規則。
  觸發關鍵字: merge, 整合, branch 收尾, PR, <專案 ticket 前綴>
stage: infra
---

# <專案名> Git Workflow

> 由 shared-skill-onboarder 從本 repo 觀察歸納。shared 的 `finishing-a-development-branch` / `sync-work`
> 在偵測到 `project/git-workflow` 時 defer 到此。

## 分支模型
- base branch: <manifest `git_workflow.base_branch`>
- release branch: <repo 的 release branch；沒有則略>
- 整合流程: <manifest `git_workflow.integration_flow`>

## 命名慣例
- feature: `feature/<ticket>-<slug>`
- fix: `fix/<ticket>-<slug>`
- 角色分支（若有）: <從 repo 觀察到的真實 pattern>
- ticket 格式: <manifest `git_workflow.ticket_pattern` 的真實值>

## Commit 規範
- <例：conventional commits；scope 用模組名>

## 整合步驟（專案特有）
1. <步驟，引用真實 repo 命令 / CI gate>
2. ...

## 禁止
- <依 repo protected-branch 規則填寫>
```

建立後，把 manifest `## Git Workflow` 的對應鍵填好，並在 `## Domain Skill Names` 登記
`- git-workflow: git-workflow`。
