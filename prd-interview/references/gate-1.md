# Gate 1：PRD 完整檢查

`prd-interview` 的 Phase 5 先跑主文件的八項核心檢查，再用本表確認細節。任何必填項失敗都要回到
對應階段修正；不可用備註繞過。

## 需求與驗收

- [ ] 每個 FR 有使用者價值、輸入、輸出、Data 來源、權限與邊界條件。
- [ ] 每個 FR 至少對應一個 AC；每個 AC 都使用 Given-When-Then。
- [ ] Given 包含可執行的前置條件，Then 是可觀察結果。
- [ ] 每個主要失敗模式有 ERR，包含觸發條件、預期行為與恢復策略。
- [ ] NFR 包含可驗證目標；不適用項目有具體理由。

## 範圍與語言

- [ ] In scope、範圍外、依賴與 breaking change 明確且互不矛盾。
- [ ] 成功指標有目標值與衡量方式。
- [ ] 沒有未量化的模糊詞，例如「快速」「適當」「容易」「友善」。
- [ ] 至少 1 個真實風險有觸發條件與緩解方式；不要求固定數量。
- [ ] 搜尋採用的證據可追溯，或已記錄 `Skipped：低新穎度`。

## 決策與條件欄位

- [ ] 阻擋型 FU 已全部關閉；非阻擋型 FU 有 owner 與關閉時點。
- [ ] `sprint_tracking: true` 時有 Sprint；其他情況為 `Sprint: N/A`。
- [ ] manifest `has_ui: false` 時記錄 `UI: N/A`；為 true 且 Story 變更介面時，有 mockup、互動狀態、
      token 與 Flow 證據，或具體 N/A 理由。
- [ ] PRD metadata 與 `meta.yml` artifact 紀錄一致。

## 角色視角

- [ ] PM：價值、範圍、成功指標與風險足以做優先順序決策。
- [ ] RD：資料來源、邊界、依賴與錯誤行為足以進入技術設計。
- [ ] User：主要路徑與失敗後的恢復方式清楚。
- [ ] QA：AC 與 ERR 可以形成獨立測試案例。
- [ ] UI：僅在 `has_ui: true` 時檢查互動狀態、流程、token 與 mockup。

## Gate 結果

```text
Gate 1: PASS/FAIL
Failed checks: [無，或列出項目]
Evidence: [PRD 路徑與版本]
Reviewed at: YYYY-MM-DD HH:MM
```
