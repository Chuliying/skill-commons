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

> 改編自 [obra/superpowers](https://github.com/obra/superpowers)，採 skill-commons 的最小路由與成本邊界。

把會改變實作的未決需求收斂成 decision brief；repo inspection、PRD、Spec、Plan 與
review 各自留在原 flow。

透明度放在 progress/commentary；final answer 只呈現決策與下一步，不重複 skill name 或 routing taxonomy。

## Qualification

依序確認：存在會改變 scope、架構、公開行為或驗收方式的 material ambiguity；repo
evidence 無法回答；使用者答案會改變後續工作。任一不成立就 Skip。預設 Skip：

- 邊界與驗收已明確的 micro-task 或既有 spec 實作。
- bug 重現、根因調查、測試失敗與修復。
- code review、release evidence 更新與 read-only 說明。
- 可由 repository 或權威來源查證的事實問題。

仍有兩種以上實質實作才繼續。事實問題直接查 repo、官方文件或 host browsing；只有
qualified Standard / Deep 決策需要額外證據時，才讀
[`references/research.md`](references/research.md)；Research 是 subroutine，不增加 mode。

## Cost modes

| Mode | Budget | Artifact |
|---|---|---|
| Skip | 0 問；直接走對應 flow | 無 |
| Quick | 最多 1 個問題；最多 2 個選項 | 無 |
| Standard | 最多 3 個問題；每個決策最多 2 個選項；一次最終確認 | 依交接需要 |
| Deep | 先記錄原因、範圍與預算；使用者明確同意後才擴張 | 必要時建立 |

能用 Quick 就停；其餘預設 Standard。高風險、跨 domain 或明確要求廣泛探索時才提議
Deep，未獲使用者明確同意不得升級。預算耗盡就列出剩餘決策與影響，由使用者選擇
Deep、縮小範圍或暫停。

跨 session 且重大未知仍無法拆成 task 時，Deep 才讀
[`references/wayfinding.md`](references/wayfinding.md)。consent package 仍屬 Standard：
`proceed` 載入 Wayfinding；`stay Standard` 留在原模式；`narrow` 縮小提案後重新取得同意。
缺 Wayfinding Control 的 legacy brief 僅供歷史讀取，走 Skip。

## Process

1. 查相關檔案、決策、測試與最近變更，不問 repo 已能回答的事。
2. 一次只問一個決策題，先給推薦與理由；沒有合理替代時不硬湊選項。
3. 問題、範圍、成功標準與限制足以選路徑就停。
4. 用短 brief 列出問題、in/out、決定、理由、風險與未決事項，做一次最終確認。

Research 回到當前決策；Wayfinding 清除主要 Fog 後交給 PRD、Spec 或 Plan。Spec/QA
研究留在原階段。避免重問、逐段確認或因載入 skill 製造文件。

## Artifact and handoff

brief 預設留在對話；跨 session、跨 agent、team handoff 或使用者要求 durable record
時才寫：

```text
<work_root>/<slug>/brainstorm.md
<work_root>/<slug>/meta.yml
```

落檔遵循 [`../ARTIFACTS.md`](../ARTIFACTS.md)。`brainstorm.md` 是 supporting input，不加
lifecycle stage；沒有 work item 時，由後續 PRD、Spec 或 Plan producer 建立 `meta.yml`。

Consented Deep 仍用 `brainstorm.md`；map、budget、resume 與尺寸依 Wayfinding reference。

Handoff：micro-task → `implement`；個人持久共識 → `to-prd`；team 需求 →
`prd-interview`；既有方案壓測 → `grilling`；多步、跨 session 或 drift → `plan-sync`。

## Evidence boundary

結構測試與 fixtures 只證明文字契約、案例覆蓋與載入體積。模型觸發率、token、時間
或品質主張需要同 prompt、模型與 host 的 matched runs 加人工 adjudication。
