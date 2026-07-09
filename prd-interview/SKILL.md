---
name: prd-interview
description: |
  透過結構化訪談把新功能需求整理成可驗收的 PRD。Use when: (1) 使用者提出新功能, (2) 需要釐清範圍與風險, (3) 準備進入技術規格前。
  觸發關鍵字: PRD, 需求訪談, 新功能, 需求釐清, product requirements
source_kind: original
stage: docs
output: <work_root>/<slug>/prd.md
---

# PRD Interview

用五個階段把需求訪談收斂為可追溯、可驗收的 PRD。資訊不足時繼續提問，不以猜測補洞。

## When to Use

- 使用者提出需要多角色協作、跨模組，或風險尚未釐清的新功能。
- 現有需求缺少明確的 FR、ERR、AC、NFR 或範圍外項目。
- `skill-router` 將任務導向 PRD 階段。

小型、低風險且目標與驗收方式都明確的 personal micro-task，依 router 直接進入實作，不啟動本技能。

## Inputs and Outputs

輸入：使用者描述、`.agent/project-manifest.md`、manifest 指向的專案知識，以及同一 work item 的既有 artifacts。

輸出：

- `<work_root>/<slug>/prd.md`
- `<work_root>/<slug>/meta.yml` 的 PRD artifact 紀錄
- `prd-interview` execution checklist

PRD 結構使用 [PRD template](../prd-template.md)。欄位判斷規則見
[PRD field guide](references/prd-field-guide.md)；完整 Gate 1 規則見 [Gate 1 reference](references/gate-1.md)。

## Active Inquiry and Follow-ups

一次只問一個會改變產品行為、範圍或驗收方式的問題；先說明為何重要，再提供具體選項與推薦。
可從現有文件確定的事不重問。答案產生新風險或矛盾時，立即追問，不等到最後補洞。

尚未決定的事項記為 FU。FU 的欄位、狀態、選項與決策格式只定義在
[PRD template](../prd-template.md) 與 [PRD field guide](references/prd-field-guide.md)；
阻擋型 FU 未關閉前不得交付 spec。

## Phase 1: Context

1. 讀取 `skill-router/SKILL.md` 與 `.agent/project-manifest.md`，取得 `work_root`、Git Workflow、
   四個 Stack capability flags、`architecture_map`、`knowledge_boundary` 和 domain skills。
2. 若 manifest 指向可讀的 architecture map，讀取與需求相關區段；缺失或過時則記錄風險，不猜測架構。
3. 讀取同一 slug 的 `meta.yml`、既有 PRD 與決策紀錄，避免重複或互相衝突。
4. 套用 Knowledge Boundary：Hard boundary 衝突時停止；Soft boundary 衝突建立阻擋型 FU。
5. 需要確認遠端差異時只執行 `git fetch <remote> <base>`，再用
   `git rev-list --left-right --count HEAD...<remote>/<base>` 回報 ahead/behind。
   不改動工作樹；只有使用者明確要求同步時才交給 `sync-work`。

輸出一段 Context Summary：目標、目前系統、已知限制、知識缺口、ahead/behind 狀態。

## Phase 2: 風險與範圍

1. 寫出至少 1 個真實風險與緩解方式，不為湊數製造風險。優先檢查資料、UX、商業與相容性。
2. 估算 Story 大小，檢查 INVEST。若無法獨立驗收或明顯過大，提出垂直切分方案並取得確認。
3. 明列 in scope、out of scope、依賴與 breaking change；範圍外項目不得藏在備註。
4. 只有新領域或外部 UI pattern 需要證據時才搜尋外部資料。內部小改動記錄
   `Skipped：低新穎度，現有專案慣例足夠`。
5. 只有 manifest 的 Git Workflow 明確設定 `sprint_tracking: true` 才詢問並記錄 Sprint；
   否則 PRD 寫 `Sprint: N/A`。

## Phase 3: 訪談

以 5W2H + 1F 檢查需求，但只問尚未回答且會影響決策的問題：

- Who：角色、權限、受影響者。
- What：行為、資料、成功與錯誤結果。
- Why：使用者價值與商業目標。
- When：觸發、時序、生命週期。
- Where：入口、平台、系統邊界。
- How：使用流程、既有能力、操作限制。
- How much：規模、效能、成功指標。
- Failure：失敗方式、復原策略與不可接受結果。

將已確認答案直接寫入對應 FR、ERR、AC 或 NFR；未確認事項依 Active Inquiry 規則建立 FU。
資料來源、權限與錯誤恢復路徑不得留空。

## Phase 4: 產出

1. 依 [ARTIFACTS contract](../ARTIFACTS.md) 建立或更新 `<work_root>/<slug>/prd.md`，並使用 PRD template。
2. 每個 FR 都要有輸入、輸出、資料來源、權限與邊界條件；每個錯誤情境有 ERR。
3. 每個 AC 使用 Given-When-Then，Given 包含可執行的前置條件，且單行不超過 250 字元。
4. 不確定 Flow、AC、UI evidence 或外部證據是否適用時，讀取 PRD field guide；不要把教學文字寫進 PRD。
5. NFR 填入可驗證目標；不適用時寫理由，不留空白。
6. 讀取 manifest `has_ui`。`false` 時 UI 欄位一律記為 `N/A (has_ui=false)`；`true` 時再依 Story
   是否變更介面填 UI states、互動流程、design token 與 mockup evidence。
7. 更新 `meta.yml` 的 artifact、版本、狀態與 handoff，保留既有歷史。

## Phase 5: Gate 1 自檢

交付前先檢查八個核心項目：

- [ ] 每個 FR 都有可追溯的使用者價值與資料來源。
- [ ] 每個 AC 都符合 Given-When-Then，且可以實際驗證。
- [ ] ERR 涵蓋主要失敗與復原路徑。
- [ ] 範圍外、依賴與 breaking change 已明列。
- [ ] 沒有「快速」「適當」「友善」等未量化模糊詞。
- [ ] 阻擋型 FU 已全部關閉；非阻擋型 FU 有 owner 與關閉時點。
- [ ] NFR 有可驗證目標或具體不適用理由。
- [ ] PM、RD、User、QA 與條件式 UI 角色視角沒有矛盾。

接著執行機器形狀 gate（確定性，不等待人工核可，FAIL 修正後重跑）：

```bash
python3 <shared_skills_root>/scripts/check-prd.py --prd "<work_root>/<slug>/prd.md" --tier team
```

再依 [Gate 1 reference](references/gate-1.md) 執行完整檢查。任一核心項目或機器 gate 失敗就回到對應階段，
不得宣告 PRD 完成。

## Handoff

Gate 1 自檢通過後：

1. 填寫 [execution checklist](references/execution-checklist.md)。
2. 依 [`../GATE-PACKAGE.md`](../GATE-PACKAGE.md) 整理變更、證據、風險與具體決策選項。
3. 在 `meta.yml` 將 PRD stage 標記為 `awaiting-approval`，呈現 PRD 核可選項並停止。
4. 收到具體核可後改為 `approved` 並記錄 decision evidence；要求修改時維持 active 並回到對應 Phase。
5. 回報 PRD 路徑與決定；核可後才建議下一步使用 `spec`，不要自行開始實作。
