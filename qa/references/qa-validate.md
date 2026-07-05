---
name: qa-validate-reference
description: |
  針對單一 Spec 進行驗收測試與規範檢查，確保該 Story 完成度。
  Use when: (1) Story 開發完成後, (2) 準備提交 PR 前, (3) 需要驗收單一功能時。
  觸發關鍵字: validate, 驗收, 驗證, QA, PR review
---

# QA Validator

針對單一 Spec 進行驗收測試，確保功能符合需求 (AC) 且程式碼符合規範。此 Skill 定義了 **Done Definition** (完成定義) 的最終閘門 (Gate)。

## Available Script

```bash
# 一鍵執行 CI + E2E + QA spec checklist（委託 verify.sh 跑基礎 CI）
bash .agent/skills/_shared/qa/scripts/run-qa.sh

# 指定 QA spec 檔案
WORK_ROOT="<manifest paths.work_root; default: docs/work>"
SLUG="<stable-work-item-slug>"
bash .agent/skills/_shared/qa/scripts/run-qa.sh "$WORK_ROOT/$SLUG/qa-plan.md"
```

> 腳本讀 manifest `stack.e2e_cmd`，並委託 `verify.sh` 執行 type-check / lint / test，避免重複維護。

---

## Core Principle (Single Source of Truth)

**驗收基準**：

1. **Project Manifest**：必須先讀 `.agent/project-manifest.md`，再依 manifest 核對文件與技能入口。
2. **架構地圖**：必須核對 manifest 中 `architecture_map` 指向的文件，確認檔案路徑與架構正確性。
3. **Acceptance Criteria**：必須 100% 滿足 PRD 中的 AC。
4. **測試通過**：所有適用層級必須通過；`typed_contracts` / `has_e2e` 為 false 時對應層級是 N/A。
5. **契約安全**：任何 Mock Data 必須符合 spec / API reference 定義的資料契約。

---

## The "Shift Left" Iron Law

**"Mocking without Type Validation is LYING to yourself."**

1. **Never Mock Blindly**: 在寫 mock fixture 前，**必須**先閱讀該 API / 外部服務的資料契約。
2. **Verify Contracts First**: 如果不確定結構，先讀 `.agent/project-manifest.md`，再查看 manifest 中 `types_entry` / `api_reference`，禁止猜測欄位。
3. **Mock E2E is Conditional**: 只有 `has_e2e: true` 時要求 E2E；涉及 UI/API 替身時，Mock Data 必須符合 spec 契約。

## 完成宣稱鐵律 → 見 `verification-before-completion`

通用「無新鮮證據不得宣稱完成」鐵律與禁止詞彙，統一由 `verification-before-completion` 定義，此處不複述。本技能只負責**這個 story 的 AC 逐條核對 + 該功能測試**。

---

## Process

### Step 1: 分析 Spec 範圍與測試資源

1. 讀取 Spec 的 `Files`（檔案清單）章節
2. 依 manifest `paths.tests_root` / `paths.test_glob` 識別 Unit/Integration 測試檔案
3. `has_e2e: true` 時依 repo 慣例與 manifest `stack.e2e_cmd` 識別相關 E2E 測試；false 記 N/A
4. 識別對應的 PRD AC
5. 讀取同一工作項的 `implement-report.md`，核對 RED/GREEN 歷程、實際測試指令與 gate evidence；可抽驗已證明項目，但 report 不取代獨立驗收

### Step 2: Pre-flight Checklist

**必須執行並看到結果**（`typed_contracts: true` 才要求 `typecheck_cmd`；`lint_cmd` 有設定就執行）。例：

<!-- example -->
```bash
<typecheck_cmd>  # 必須 0 errors
<lint_cmd>       # 必須 clean
```

 `[Run] → [See output] → [Report result with evidence]`
 `"Should be clean"` 沒執行就不算

### Step 3: 執行測試 (Test Execution)

**層級一：單元與整合測試 (Unit/Integration)**

指令讀 manifest `stack.test_cmd`（沒有就問使用者）。例：

<!-- example -->
```bash
<test_cmd> [測試檔案]
```

** Checkpoint**: 若單元/整合測試失敗，**必須立即停止**，修正後重測。**禁止**在單元測試失敗的情況下嘗試執行 E2E 測試。

**層級二：E2E 測試 (End-to-End)**

`has_e2e: true` 時必須執行對應 E2E（前提是層級一通過）；false 明確記錄 N/A。

```bash
<e2e_cmd> [E2E測試檔案]
```

**確認重點：**

- 測試結果：PASS / FAIL count
- E2E 必須在真實/模擬環境下成功執行

**截圖佐證（分兩級，避免每次都燒 vision token）：**

| 測試類型 | 截圖時機 | 設定方式 |
|---|---|---|
| 一般功能性 E2E | 只在**失敗**時存圖 | `stack.e2e_cmd` 對應工具的 config 層設定（多數 E2E 工具都有「僅失敗時截圖」選項），deterministic，不吃 LLM token |
| `qa-plan.md` 的「UI Mockup 視覺驗證」/ TC-V 系列 | **通過也要**存圖 | 因為這類測試本來就在主張「畫面正確」，pass/fail count 是弱證據 |

驗證「有沒有截圖」用 `test -f <path>`（deterministic 檔案存在檢查）即可，**不需要**用 vision 讀圖內容去確認。只有在測試失敗要除錯時，才交給 `systematic-debugging` 實際讀圖分析——這樣截圖成本只在真的需要時發生，不是每次驗收都要付。

### Step 4: AC 追溯性檢查

1. 掃描測試檔案中的註解或描述
2. 確認每個 AC ID 都有被提及 (e.g., `// AC-001`)

---

## Output (Validation Report)

驗收報告寫入 `<work_root>/<slug>/qa-report.md`，並更新工作項共用的
`meta.yml`。報告必須包含以下區塊，缺少任一項即視為格式不符。指令/路徑以實際 manifest `## Stack` / `## Paths` 為準；下方為格式範例：

<!-- example -->
```markdown
# [Story] 驗收報告

## 1. Pre-flight Checklist
- [x] Type/compile check: `<typecheck_cmd>` → 0 errors，或 `N/A (typed_contracts=false)`
- [x] Lint: `<lint_cmd>` → clean
- [ ] Coding Rules:  <component> 違反 <domain-rule>

## 2. 測試執行
### Unit / Integration
- 命令: `<test_cmd> <測試檔案>`
- 結果:  8 passed, 0 failed

### E2E (如果有)
- 命令: `<e2e 指令> <E2E 測試檔案>`
- 結果:  5 passed, 0 failed (或 N/A)
- Screenshot(s): [TC-V 系列的通過截圖路徑；一般測試僅列失敗截圖路徑，皆通過則寫「N/A（僅失敗才存圖）」]

## 3. AC 追溯
| AC ID | 測試檔案 | 狀態 |
|-------|---------|------|
| AC-001 | <test-file>:L45 |  |
| AC-002 | — |  未找到對應測試 |

## 結論
 驗收失敗，請修正上述問題。
```

若結論為 PASS，提示使用者可執行 work-item closeout：在 `prd.md` 追加
`## Delivery`、將 `meta.yml` 標記 `shipped`，並升級仍長期有效的 ADR／術語；
不要在未授權 branch 收尾時自行 merge 或 push。

---

## Red Flags - STOP

**遇到以下情況必須立即停止並標記為失敗 (Blocker)：**

1. **Pre-flight 失敗**：適用的 type/compile check 或 lint 報錯；capability false 的 N/A 不算失敗。
2. **測試失敗**：任何 Unit 或 E2E 測試紅燈。
3. **E2E 缺漏**：`has_e2e: true` 卻未執行，或缺少 `e2e_cmd`。
4. **AC 未覆蓋**：PRD 上的 AC 未在測試中體現。
5. **TC-V 缺截圖**：`qa-plan.md` 有 TC-V 系列（視覺/mockup 對齊測試）卻沒有對應的通過截圖路徑，或路徑指向的檔案不存在（`test -f` 檢查失敗）。

---

## Related Skills

| Trigger | Skill |
|---------|-------|
| 需要 Debug | `systematic-debugging` |
| 需要修正程式 | `implement` |
