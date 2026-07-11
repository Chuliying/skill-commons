---
name: brainstorming
description: |
  釐清會實質改變 scope、architecture、public contract 或 acceptance criteria 的 material ambiguity。
  只在 repo evidence 無法回答且答案會改變實作時使用；清楚的 micro-task、bug、review 與說明題直接跳過。
source: obra/superpowers@d884ae04edebef577e82ff7c4e143debd0bbec99
source_kind: adapted
stage: docs
output: <work_root>/<slug>/brainstorm.md
---

# Brainstorming — Bounded Discovery

> 改編自 [obra/superpowers](https://github.com/obra/superpowers)，本版以 skill-commons 的最小路由與成本邊界為準。

將尚未決定、而且會改變實作的需求收斂成足夠執行的 decision brief。它不是所有
任務的前置 Gate，也不替代 repo inspection、PRD、Spec、Plan 或 review。

使用時先告知：「我正在使用 brainstorming 釐清會改變實作的未決事項。」

## Qualification

依序判斷：

1. 是否存在會改變 scope、架構、公開行為或驗收方式的 material ambiguity？
2. 現有 spec、程式碼、測試或其他 repo evidence 能否直接回答？
3. 使用者的答案是否真的會改變接下來的工作？

任一答案為「否」就用 Skip，不載入更多探索流程。下列任務預設 Skip：

- 邊界與驗收已明確的 micro-task 或既有 spec 實作。
- bug 重現、根因調查、測試失敗與修復。
- code review、release evidence 更新與 read-only 說明。
- 可由 repository 或權威來源查證的事實問題。

未決事項仍會造成兩種以上實質不同的實作時，才使用本 skill。

## Cost modes

| Mode | Budget | Artifact |
|---|---|---|
| Skip | 0 問；直接走對應 flow | 無 |
| Quick | 最多 1 個問題；最多 2 個選項 | 無 |
| Standard | 最多 3 個問題；每個決策最多 2 個選項；一次最終確認 | 依交接需要 |
| Deep | 先記錄原因、範圍與預算；使用者明確同意後才擴張 | 必要時建立 |

預設使用 Standard，但能用 Quick 解決就立即停止。只有高風險、跨 domain 或使用者
明確要求廣泛探索時才提議 Deep；未獲同意不得自行升級。問題預算用完仍有 material
ambiguity 時，回報剩餘決策與影響，請使用者決定是否 Deep、縮小範圍或暫停。

## Process

1. **先查證**：讀相關檔案、既有決策、測試與最近變更；不要詢問 repo 已能回答的事。
2. **只問決策題**：一次一問，先給推薦與理由；沒有合理替代方案時不用硬湊選項。
3. **足夠即停**：當問題、範圍、成功標準與關鍵限制已足以選實作路徑，就停止探索。
4. **收斂一次**：用短 decision brief 列出問題、in/out、決定、理由、風險與未決事項，做一次最終確認。

不得每段要求確認、重問已回答事項，或因 skill 被載入就製造額外文件。

## Artifact and handoff

預設把 decision brief 留在當前對話。只有跨 session、跨 agent handoff、正式 team
交接或使用者要求 durable record 時，才寫：

```text
<work_root>/<slug>/brainstorm.md
<work_root>/<slug>/meta.yml
```

落檔時遵循 [`../ARTIFACTS.md`](../ARTIFACTS.md)。這個 `output` 是條件式能力，
不是每次執行的完成條件。

- 清楚的 micro-task → `implement`。
- 個人工作需要持久共識 → `to-prd`。
- team 正式需求交接 → `prd-interview`。
- 已有方案、只需壓測漏洞 → `grilling`，不要重跑 brainstorming。
- 多步、跨 session 或需追蹤 drift → `plan-sync`。

## Evidence boundary

結構測試與 routing fixtures 只能證明文字契約、案例覆蓋與載入體積，不能證明模型
一定正確觸發，也不能證明 token、時間或產出品質改善。這些主張需要同 prompt、同
模型／host 的 with-skill／without-skill 重複執行與人工 adjudication。
