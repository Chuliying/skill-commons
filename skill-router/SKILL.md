---
name: skill-router
description: |
  AI 任務分發器。每個新任務先讀本檔，用五條 flow 選擇最小必要 skills 與 Execution Mode。
  觸發時機: 每次對話開始、收到新任務時
source_kind: original
stage: skill
---

# Skill Router

把使用者意圖路由到最小 workflow。Skill 自己的 `description` 是 utility 觸發條件 source of truth；本檔只維護跨階段 flow。

Execution Mode 的 artifact requirement、producer、handoff 與 human gate 以
[`../protocol-registry.json`](../protocol-registry.json) 為唯一 machine source。
本檔保留可讀流程與 mode key，不另維護一份矩陣。Registry 只是 declarative
contract，由 conformance tests 驗證；它不執行 workflow、不管理 state 或 scheduling。

## Global Iron Laws

1. 持久狀態與交接結果落檔，不能只存在對話 context。
2. 成功宣稱必須附 fresh verification evidence。
3. push、merge、刪除、history rewrite 等不可逆或外部副作用，執行前必須取得明確確認。

只有會寫檔、執行命令、改 Git 或呼叫外部服務的任務需要 preflight：讀 `.agent/guardrails.md` 與 `.agent/project-manifest.md`。檔案缺席時，先探測 repo 慣例；涉及不可逆動作仍無法確定邊界就停止詢問。純說明與 read-only 分析不要求製造骨架。

派發前實際讀取每個必要 skill 的 `SKILL.md`；不可只聲稱遵循。相對 reference 以該 skill 目錄解析。Manifest 有 Domain Skill Names 時，只載入與本次範圍相關者。

## Profile 邊界

- `team-sprint`：正式 PRD / Spec / QA 交接，設計核可為人工 Gate。
- `personal`：輕量 artifact 與直接驗證，不製造 team ceremony。

**personal profile 硬規則**：`prd-interview`、`spec`、`qa`、`prototype`、`domain-modeling` 不在 bundle 內。

`markdown`、`codebase-understanding`、`subagent-driven-development` 位於 optional profile；安裝後依各自 description 觸發。`skill-creator` 是 maintainer-only top-level 工具，不在 consuming profiles。

## 任務判斷表

| 意圖 | 判斷 | Flow |
|---|---|---|
| 探索 | 有會改變實作的 material ambiguity、需求訪談、計畫壓測 | [探索](#flow-探索) |
| 建造 | 新功能、需求變更、重構、開始實作 | [建造](#flow-建造) |
| 修錯 | bug、測試失敗、行為異常 | [修錯](#flow-修錯) |
| 發布 | review、commit、PR、merge、恢復 branch | [發布](#flow-發布) |
| 理解 | codebase、架構、依賴與 domain 探索 | [理解](#flow-理解) |

## Flow: 探索

用於仍需要釐清「做什麼」或壓測決策。`brainstorming` 只處理 repo evidence
無法回答、且答案會改變 scope、架構、公開行為或驗收方式的 material ambiguity。

```text
brainstorming（qualified discovery；artifact 只在 durable handoff 時建立）
  → to-prd（已有共識時快照）或 prd-interview（team 正式訪談）
  → grilling（高風險時逐題壓測；需要交接才開 durable docs mode）
```

- 依成本選 Skip / Quick / Standard / Deep；Standard 最多三問，Deep 需使用者同意。
- 清楚的 micro-task、bug、review、既有 spec 實作與 repo 可回答的問題 Skip。
- personal 需要持久共識時才 handoff `to-prd`；不因 profile 製造 discovery artifact。
- team 可用 `prd-interview`，PRD 核可後才進建造。
- `grilling` 不替代 PRD 核可，也不為低風險工作增加 ceremony。

## Flow: 建造

### Team feature

Execution Mode: `team-feature`。條件式 artifacts 與 handoff 依 registry。

```text
prd-interview 或 to-prd → 人工：PRD 核可
  → spec → 人工：team 設計核可
  → qa plan → plan-sync canonical plan → implement
  → qa validate → verification-before-completion
```

QA 的 AC traceability 是 machine gate。`plan-sync` 的一致性檢查也是 machine gate，不增加人工核可。

### Personal feature

Execution Mode: `personal-feature`。條件式 artifacts 與 handoff 依 registry。

```text
to-prd（需要持久共識時）→ plan-sync canonical（多步或跨 session 時）
  → implement → verification-before-completion
```

### Refactor

Execution Mode: `refactor`。條件式 artifacts 與 handoff 依 registry。

```text
to-prd → spec（team 或設計風險高時）→ implement → verification-before-completion
```

### Micro-task 直達（相容別名：Flow A-P micro）

以下三項全部成立才可 `implement → verification-before-completion`：

| 條件 | 客觀邊界 |
|---|---|
| 單檔或少數檔 | 不超過 3 個互相關聯實作檔；tests 與 generate 產物不計 |
| 無新依賴 | 不新增 package、plugin、service 或 dependency graph |
| 無 schema/API 變更 | 不改持久化格式、公開 API、event 或跨服務 contract |

任一條件不成立或不確定，就走一般 personal feature。直達路徑為 `implement（帶 failing test）→ verification-before-completion`；`implement` 自己完成 RED → GREEN → REFACTOR，不另派同能力包裝。

Plan selection：micro-task 不建立 plan；其他需要多步、handoff、resume 或
drift tracking 的工作使用 canonical `plan/plan.md`。v0.7 不載入舊三件式
plan；消費端需先遷移到 canonical-v2，或在遷移前 pin v0.6。

## Flow: 修錯

Execution Mode: `bug-fix`。條件式 artifacts 與 handoff 依 registry。

```text
systematic-debugging（重現與 root cause）
  → implement（observed failing test → fix）
  → verification-before-completion
```

先完成根因調查。建置、整合或測試失敗也走本 flow；缺件 fallback 是現象、最小重現與 evidence，不補 feature 文件。

## Flow: 發布

```text
verification-before-completion
  → caveman-review（需要時派 fresh-context reviewer）
  → security
  → 人工：發布核可
  → finishing-a-development-branch
```

- `sync-work` 處理進行中的 branch / stage / commit；只有明確授權才 push。
- `finishing-a-development-branch` 處理 merge / PR / 保留 / 放棄，以及 Recovery Mode。
- Review finding 必須先驗證；Critical/Important 修正後重跑 evidence。
- 無 remote、權限或必要 artifact 時安全停止並回報 fallback，不自行建立 remote 或繞過 protected branch。

## Flow: 理解

若 optional `codebase-understanding` 已安裝：

```text
codebase-understanding → architecture map / domain candidates
  → 必要時更新 manifest 指標
```

未安裝時使用 read-only 搜尋與 repo 既有文件，不把理解任務升級成 onboarding。只有使用者要求接入 shared skills 時，才派 `shared-skill-onboarder`。

## Utility 自觸發

下列能力不佔新 flow；匹配其 frontmatter description 時直接讀取：

| 任務 | Skill |
|---|---|
| PDF / Word / Excel / PPT / API 文件轉 Markdown | `markdown`（optional） |
| shared skill 接入、manifest 掃描 | `shared-skill-onboarder` |
| lo-fi / wireframe / prototype 與微調 | `prototype`（team） |
| 多 task 且明確要求 subagent 執行 | `subagent-driven-development`（optional） |
| 建立或評測 skill | `skill-creator`（maintainer-only） |

Prototype 的人工確認為 G1 / G4 / G6，屬該技能針對非工程操作者的內部 gate，不增加 workflow 的 PRD、team 設計、發布三個判斷點。

## Dispatch Checklist

```text
□ 已選定一條 flow 與 Execution Mode
□ side-effect 任務已讀 guardrails / manifest 或記錄 fallback
□ 已實際讀取所有派發 skills
□ 條件式 artifact 沒有被補造
□ 人工 Gate 只停在 PRD、team 設計、發布
□ 完成宣稱有 fresh evidence
```
