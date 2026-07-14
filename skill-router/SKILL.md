---
name: skill-router
description: |
  AI 任務分發器。每個新任務先讀本檔，用五條 flow 選擇最小必要 skills 與 Execution Mode。
  觸發時機: 每次對話開始、收到新任務時
source_kind: original
stage: skill
---

# Skill Router

把意圖路由到最小 workflow；utility 由各 skill 的 `description` 觸發。本檔只維護
跨階段 flow。Execution Mode 契約以 [`../protocol-registry.json`](../protocol-registry.json)
為 machine source；registry 是 declarative contract，不負責 runtime 或 scheduling。

## Global Iron Laws

1. 持久狀態與交接結果落檔，不能只存在對話 context。
2. 成功宣稱必須附 fresh verification evidence。
3. push、merge、刪除、history rewrite 等不可逆或外部副作用，執行前必須取得明確確認。

會寫檔、執行命令、改 Git 或呼叫外部服務時，preflight 讀 guardrails 與 manifest；
缺席就探測 repo 慣例，仍無法界定不可逆動作才詢問。派發前讀必要 `SKILL.md` 與相關
Domain Skill；相對 reference 從該 skill 解析。read-only 任務不建立骨架。

## Profile 邊界

- `personal`：七個 core owner；輕量 artifact 與直接驗證。
- `team-sprint`：core 加正式 PRD / Spec / QA / prototype / domain modeling。
- `frontend`：前端相關任務；`optional`：個人探索、PRD、review、onboarding 與 utilities。

**personal profile 硬規則**：`prd-interview`、`spec`、`qa`、`prototype`、`domain-modeling` 不在 bundle 內。

`brainstorming`、`grilling`、`to-prd`、`caveman-review`、`shared-skill-onboarder` 與
utilities 只在 `CAPABILITY_PACKS=optional` 時可派發；缺席就說明 selection，不模擬該
owner。`skill-creator` 只供 maintainer 使用。

## 任務判斷表

| 意圖 | 判斷 | Flow |
|---|---|---|
| 探索 | 有會改變實作的 material ambiguity、需求訪談、計畫壓測 | [探索](#flow-探索) |
| 建造 | 新功能、需求變更、重構、開始實作 | [建造](#flow-建造) |
| 修錯 | bug、測試失敗、行為異常 | [修錯](#flow-修錯) |
| 發布 | review、commit、PR、merge、恢復 branch | [發布](#flow-發布) |
| 理解 | codebase、架構、依賴與 domain 探索 | [理解](#flow-理解) |

## Flow: 探索

用於仍需釐清「做什麼」或壓測決策，且已安裝 `optional`。`brainstorming` 只處理 repo
evidence 無法回答、且會改變 scope、架構、公開行為或驗收方式的 material ambiguity。

```text
brainstorming（qualified discovery；artifact 只在 durable handoff 時建立）
  → to-prd（已有共識時快照）或 prd-interview（team 正式訪談）
  → grilling（高風險時逐題壓測；需要交接才開 durable docs mode）
```

- 依成本選 Skip / Quick / Standard / Deep；Standard 最多三問，Deep 需使用者同意。
- 清楚的 micro-task、bug、review、既有 spec 實作與 repo 可回答的問題 Skip。
- 事實問題直接用 repo 或權威來源回答；只有 qualified Standard / Deep 決策才條件式使用 Research。
- 跨 session 的 unresolved Fog 經使用者 consent 才進 Deep Wayfinding；route 清楚後才交給 plan-sync。
- personal 需要持久共識才 handoff optional `to-prd`；team 用 `prd-interview`。
- `grilling` 僅壓測高風險方案。

## Flow: 建造

### Team feature

Execution Mode: `team-feature`。

```text
prd-interview → 人工：PRD 核可
  → spec → 人工：team 設計核可
  → qa plan → plan-sync canonical plan → implement
  → qa validate → verification-before-completion
```

QA traceability 與 Plan Sync consistency 都是 machine gate。

### Personal feature

Execution Mode: `personal-feature`。

```text
optional `to-prd`（需要持久共識時）→ plan-sync canonical（多步或跨 session 時）
  → implement → verification-before-completion
```

### Refactor

Execution Mode: `refactor`。

```text
既有 PRD 或 optional `to-prd` → spec（team 或設計風險高時）
  → implement → verification-before-completion
```

### Micro-task 直達（相容別名：Flow A-P micro）

以下三項全部成立才可 `implement → verification-before-completion`：

| 條件 | 客觀邊界 |
|---|---|
| 單檔或少數檔 | 不超過 3 個互相關聯實作檔；tests 與 generate 產物不計 |
| 無新依賴 | 不新增 package、plugin、service 或 dependency graph |
| 無 schema/API 變更 | 不改持久化格式、公開 API、event 或跨服務 contract |

任一條件不成立或不確定，就走 personal feature。直達路徑為
`implement（帶 failing test）→ verification-before-completion`。

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

建置、整合或測試失敗也走本 flow；缺件時記錄現象、最小重現與 evidence。

## Flow: 發布

```text
verification-before-completion
  → optional caveman-review（需要且已安裝時）
  → security
  → 人工：發布核可
  → sync-work
```

- `sync-work` 是 Scoped Save、Integrate、Finish、Recovery 的單一 Git delivery 入口；
  branch / commit / push / merge / PR / 保留 / 放棄都由其模式處理。
- 先驗證 review finding；Critical/Important 修正後重跑 evidence。缺 remote、權限或
  artifact 就安全停止，不建立 remote 或繞過 protected branch。

## Flow: 理解

若 optional `codebase-understanding` 已安裝：

```text
codebase-understanding → architecture map / domain candidates
  → 必要時更新 manifest 指標
```

未安裝時使用 repo 搜尋與既有文件；接入 shared skills 需 optional
`shared-skill-onboarder`。

## Utility 自觸發

匹配 description 且已安裝時直接讀：文件轉換用 optional `markdown`；shared skill
接入用 optional `shared-skill-onboarder`；lo-fi 用 team `prototype`；多 task subagent
工作用 optional `subagent-driven-development`；建立或評測 skill 用 maintainer
`skill-creator`。

## Dispatch Checklist

```text
□ 已選定一條 flow 與 Execution Mode
□ side-effect 任務已讀 guardrails / manifest 或記錄 fallback
□ 已實際讀取所有派發 skills
□ 條件式 artifact 沒有被補造
□ 人工 Gate 只停在 PRD、team 設計、發布
□ 完成宣稱有 fresh evidence
```
