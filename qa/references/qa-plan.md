---
name: qa-plan-reference
description: |
  從 PRD 和 spec 產出完整測試方案。Use when: (1) 技術規格完成後, (2) 需要設計測試案例, (3) 用戶說「產生測試」「QA 方案」。
  觸發關鍵字: QA, 測試方案, TC, 測試案例, test case
---

# QA Generator

從 PRD 和 spec.md 產出完整的 QA 方案，包含各層級測試案例。

## When to Use

- PRD 和 spec 都已完成
- 用戶說「產生測試」「QA 方案」
- 準備進入測試階段

## Trigger

```
/qa plan [PRD 路徑] [spec 路徑]
```

---

## TC 來源架構

```
PRD (What - 業務需求)
├── AC 驗收標準 ──────→ 可觀察的驗收測試（依 capability 選層級）
├── ERR 錯誤場景 ────→ 錯誤處理測試
└── 邊界條件推導 ────→ 邊界測試

spec.md (How - 技術實作)
├── 函式/模組設計 ───→ 單元測試 (L2)
├── 元件互動 ────────→ 元件測試 (L3)
└── API 整合 ────────→ `has_api` 時做整合測試；`has_e2e` 時可加 L5

## Verification Strategy (The Gate)
> [!IMPORTANT]
> READ `.agent/knowledge/system-context.md` first.
> **Rule 0**: NO E2E tests until Unit Tests pass.
> **Rule 1**: Verify Logic/Data Transformer via manifest `stack.test_cmd` 對應的 unit-test framework。
> **Rule 2**: API/外部服務整合方式讀 manifest 與 project domain skills，不假設固定工具。

| 層級 | 驗證目標 | 工具 | 執行時機 |
|------|---------|------|---------|
| **L2 (Unit)** | 核心邏輯 / 資料轉換 | manifest `stack.test_cmd` | **必做** (Gate 1) |
| **L4 (Int)** | API / 外部服務契約 | repo 整合測試慣例或 domain skill | `has_api: true` 或有外部整合時必做 |
| **L5 (E2E)** | 使用者流程/渲染 | manifest `stack.e2e_cmd` | `has_e2e: true` 時最後做；false 為 N/A |

> `has_api: true` 或有外部整合時 Gate L4 不可跳過；沒有該能力與依賴時記 N/A。

## API Strategy (Mock vs Real)

| 環境 | 策略 | 說明 |
|------|------|------|
| **L4 (Integration)** | **受控替身 / 測試環境** | 工具依 repo 慣例，確保可重現並驗證契約 |
| **L5 (Mock E2E)** | **受控替身** | 驗證 UI/流程狀態；Mock Data 必須符合 spec 的資料契約 |
| **L5 (Real E2E)** | **真實整合環境** | 認證與環境變數讀 manifest `environment_rules`，不得在 shared skill 寫死 |
```

---

## Process

### Challenge Spec（質疑 Spec）

> **Testability Check First.**

在開始設計測試前，先問：

1. 「這個 Spec 容易測試嗎？」
2. 「有沒有無法 Mock 的相依？」
3. 「邏輯是否過於複雜導致難以撰寫單元測試？」

如果 Spec 設計導致測試極度困難，**必須**退回要求 Spec 修改（為了可測試性重構）。

### Step 1：從 PRD 提取測試需求

| PRD 項目 | 測試類型 | 層級 |
|---------|---------|------|
| AC（驗收標準）| 驗收測試 | 可觀察行為所在層；`has_e2e` 時可用 L5 |
| ERR（錯誤場景）| 錯誤處理測試 | 適用層級 |
| FR 邊界條件 | 邊界測試 | L2-L3 |

### Step 2：從 spec 提取測試需求

| spec 項目 | 測試類型 | 層級 |
|---------|---------|------|
| 函式設計 | 單元測試 | L2 |
| Hook 設計 | Hook 測試 | L2-L3 |
| 元件設計 | 元件測試 | L3 |
| API 設計 | 整合測試 | L4 |

### UI Mockup 視覺驗證（`has_ui: true` 時條件式）

> **Visual Truth Source**: Mockup 是視覺需求的 SSOT，E2E 測試必須驗證實作與 mockup 一致。

1. 掃描 manifest `paths.mockup_root` 找最新設計稿目錄（沒有就問使用者；無設計稿則略）
2. 若存在，**讀取所有 PNG 圖檔**，從中提取視覺驗證點：

| Mockup 觀察 | 對應 TC-V 測試案例 |
|------------|-----------------|
| 桌面版表格欄位（欄數、欄名） | `TC-V01`: 驗證欄位標題存在且正確 |
| 手機版版面（卡片/列表切換） | `TC-V02`: 375px viewport 下正確渲染 |
| Badge / 狀態標籤樣式 | `TC-V03`: 特定文字 / data-testid 可見 |
| 下拉選單選項文字 | `TC-V04`: 選項標籤文字與 mockup 一致 |
| Sparkline / 圖表容器存在 | `TC-V05`: 圖表容器可見 |

3. 將 TC-V 系列加入 QA 方案的 L5 E2E 章節
4. TC-V 測試策略：使用 repo E2E 工具的語意化查詢驗證元素存在，不驗證像素層級

> `has_ui: false` 時本步驟為 N/A。為 true 且 mockup 存在但沒有 TC-V 時，QA 方案不完整。

### 測試策略研究 (QA Research)

> **Don't Guess. Search.**

使用 `search_web` 尋找最佳測試模式：

```text
search_web("testing [feature] with [manifest stack/framework E2E tool] best practices")
search_web("how to mock [complex scenario] in [manifest stack.framework test tool]")
```

**驗證重點**：

1. 針對此功能，業界推薦的測試層級分佈？
2. 是否有特殊的 Mock 技巧需要使用？
3. 常見的測試盲點是什麼？

### Step 3：建立 AC → TC 對照表

```markdown
| AC-ID | AC 描述 | TC-ID | TC 描述 | 層級 |
|-------|--------|-------|--------|------|
| AC-001 | ... | TC-001 | ... | [適用層級] |
```

**原則**：

- 1 個 AC = 至少 1 個 TC
- 每個邊界條件 = 1 個 TC
- 每個錯誤場景 = 1 個 TC

### Step 4：建立測試矩陣 (Gate Check)

**必須包含至少一個 L2 Unit Test 用於驗證核心邏輯或資料轉換。**

按測試層級組織：

1. **L2 (Unit)**: 放 manifest `paths.tests_root` 下，符合 `paths.test_glob`（邏輯驗證）
2. **L5 (E2E)**: 只在 `has_e2e: true` 時依 repo 慣例做 journey 驗證

> 如果只有 E2E，退回重寫。

### Step 5：推導邊界條件測試

從 AC 推導隱含的邊界條件

### Step 6：建立錯誤場景測試

從 ERR 產生錯誤測試

### Step 7：Machine Gate — AC traceability 與方案自檢

   > ** 禁止主觀判斷**：以下每一項都必須有客觀證據，特別是測試程式碼的編譯能力。

   | 檢核項目 | 通過標準（客觀證據） |
   |---------|--------------------|
   | **整合契約** | 已依 API reference / domain skill 執行 repo 定義的整合驗證 |
   | **AC 覆蓋** | PRD 中的每個 AC 都有對應的測試案例 |
   | **ERR 覆蓋** | PRD 中的每個 ERR 都有對應的測試案例 |
   | **Test 可執行** | 以 manifest `stack.test_cmd` 驗證代表性測試骨架或既有測試檔 |
   | **Mock 安全** | 測試中的 Mock Data 必須符合 Spec 中定義的 Interface |
   | **E2E 獨立性** | `has_e2e: true` 時 E2E 不依賴 runner 無法解析的 alias；false 為 N/A |
   | **L5 測試標配** | `has_e2e: true` 時 L5 包含未處理錯誤/主控台錯誤檢查；false 為 N/A |
   | **UI Mockup 覆蓋** | `has_ui: true` 且有 mockup 時必須有 TC-V；false 為 N/A |

    先執行：

    ```bash
    python3 <qa-skill-dir>/scripts/check-traceability.py --prd <prd.md> --qa-plan <qa-plan.md>
    ```

    任一項 FAIL → 修正 QA 方案 → 重跑 machine gate。這是機械比對，不等待人工核可。
    全部 PASS → 產生最終 QA 方案：`<work_root>/<slug>/qa-plan.md`

使用 `resources/qa-template.md` 模板

---

## Output

| 產出 | 路徑 |
|------|------|
| QA 方案 | `<work_root>/<slug>/qa-plan.md` |
| Metadata | `<work_root>/<slug>/meta.yml` |

使用 `resources/qa-template.md` 模板

---

## Next Step (銜接驗收)

1. **實作測試程式碼**：根據 QA 方案，於 manifest `paths.tests_root` 建立符合 `paths.test_glob` 的測試檔
2. **開發功能 (TDD)**：實作功能並通過測試
   - 先寫測試 (Red)
   - 實作功能 (Green)
   - 重構優化 (Refactor)
3. **執行驗收 (The Gate)**：
   - **Phase 1**: 跑 Unit Test（manifest `stack.test_cmd` + `paths.tests_root`）-> 通過
   - **Phase 2**: `has_e2e: true` 時跑 E2E Test；false 記 N/A
   - 使用 `/qa validate [spec路徑]` 進行最終確認

---

## 測試層級

| 層級 | 類型 | 工具 |
|------|------|------|
| L1 | 靜態分析 | `typed_contracts` 時用 typecheck；lint 依 manifest 設定 |
| L2 | 單元測試 | manifest `stack.framework` 對應工具 |
| L3 | 元件測試 | repo 既有 component-test 工具 |
| L4 | 整合測試 | repo 既有 integration-test 工具 |
| L5 | E2E 測試 | repo 既有 E2E 工具 |

---

## E2E 與整合測試通用規範

### Mock 隔離原則

1. Mock 測試不可意外連到真實外部服務。
2. Mock 資料必須符合 spec / API reference 的資料契約。
3. 攔截優先序、alias 支援與 fixture 位置依 repo 測試工具及 domain skill。
4. 真實整合測試的認證與環境規則讀 manifest `environment_rules`。

### 測試與實作同步

當實作程式碼變更時，**測試的斷言值也必須同步更新**：

| 實作變更 | 測試同步動作 |
|---------|-------------|
| 資料格式變更 | 更新 fixture、Mock 與斷言 |
| API / 外部服務契約變更 | 更新 Mock、整合測試與斷言 |
| 資料結構變更 | 更新 Mock 資料與型別驗證 |

> **Iron Law**: 實作與測試是一體的，修改實作必須同時檢視測試。

### Mock E2E 通過 ≠ 實際環境正確

> **Critical**: Mock E2E 測試通過只代表「應用邏輯在替身資料下正確」，不代表「與真實外部服務整合正確」。

**防護措施**：

1. 查閱 manifest 指向的 API reference / system context。
2. 除了 Mock E2E，也依風險執行真實整合測試。
3. Gate L4 的實際命令由 project domain skill 或 repo CI 慣例提供。

---

## Gate L4: API 連線驗證（絕對不可跳過）

### 為什麼 Gate L4 如此重要

| 跳過 Gate L4 的後果 | 實例 |
|------------------|------|
| 虛構 API 端點無法發現 | 實作引用了 API reference 中不存在的端點 |
| 錯誤契約無法發現 | 實作選到語意不同的查詢或操作 |
| Mock E2E 假通過 | Mock 攔截所有請求，包含不存在的端點 |

### Gate L4 失敗處理

如果 Gate L4 失敗：

1. **不要繼續執行 Mock E2E**
2. 檢查實作中的外部服務 / API 設定是否符合 spec。
3. 比對 manifest `api_reference` 與相關 domain skill。
4. 修正後重新執行 Gate L4

---

## Execution Checklist（必填輸出）

完成此 Skill 後，**必須**輸出以下 checklist：

```
Skill: qa plan
Executed At: YYYY-MM-DD HH:MM
Artifact: [QA 方案檔案路徑]

Steps:
Challenge Spec: 質疑 Spec - [PASS/SKIP]
   Evidence: [可測試性判斷與退回/接受理由]
Step 1: 從 PRD 提取測試需求 - [PASS/SKIP]
   Evidence: [AC 數量, ERR 數量]
測試策略研究 - [PASS/SKIP]
   Evidence: [搜尋關鍵字與發現摘要]
Step 2: 從 Spec 提取測試需求 - [PASS/SKIP]
   Evidence: [函式/Hook/元件數量]
UI Mockup 視覺驗證 - [PASS/SKIP/N/A]
   Evidence: [mockup 路徑, TC-V 數量, 驗證點摘要]
Step 3: 建立 AC → TC 對照表 - [PASS/SKIP]
   Evidence: [TC 總數]
Step 4: 建立測試矩陣 - [PASS/SKIP]
   Evidence: [L2: X, L3: X, L4: X, L5: X]
Step 5: 推導邊界條件測試 - [PASS/SKIP]
   Evidence: [邊界 TC 數量]
Step 6: 建立錯誤場景測試 - [PASS/SKIP]
   Evidence: [ERR TC 數量]
Step 7: Machine traceability gate - [PASS/SKIP]
   Evidence: [自檢結果: PASS/FAIL]

Machine gate 檢查:
   □ QC Research: [PASS/FAIL] (有搜尋紀錄)
   □ AC 覆蓋: [PASS/FAIL] (每個 AC 至少 1 TC)
   □ ERR 覆蓋: [PASS/FAIL] (每個 ERR 至少 1 TC)
   □ 邊界測試: [PASS/FAIL]
   □ L2 Unit Test: [PASS/FAIL] (至少 1 個)

Notes: [任何特殊情況或後續建議]
```

**未輸出 Checklist = 未完成 Skill**
