# G2：Page Inventory

> 盤點每個 route 的頁面、分配 frameRef、選配積木元件。

---

## 目錄

- [前置依賴](#sec-deps)
- [Pre-flight Checklist](#sec-preflight)
- [Source of Truth 優先序](#sec-sot)
- [Input](#sec-input)
- [Output](#sec-output)
- [frameRef 命名慣例](#sec-frameref)
- [Frame 重複分析](#sec-dup)
- [Component Mapping Table 格式](#sec-cmt-format)
- [Component Mapping Table](#sec-cmt)
- [積木選配規則](#sec-blocks)
- [Hybrid 複用預判](#sec-hybrid)
- [Definition of Done](#sec-dod)

---

<a id="sec-deps"></a>
## 前置依賴

G1 通過。

---

<a id="sec-preflight"></a>
## Pre-flight Checklist（進入此 Gate 前必須全部通過）

| # | 檢查項 | 檢查方式 | 失敗動作 |
|---|--------|---------|---------|
| PF-1 | `component-library.html` 存在且含可用樣式 | 讀取 manifest `component_library` 路徑指向的檔案，確認包含 `<style>` 區塊或 CSS class 定義 | STOP: 回報 component-library 不存在或為空，無法進行元件選配 |
| PF-2 | G1 routes 結構在 context 中 | 確認 `map.routes{}` 存在且至少有 1 個 route | STOP: G1 尚未完成或 context 已遺失，請重新執行 G1 |
| PF-3 | PRD 頁面描述可存取 | 確認 PRD 完整內容在 context 中或可重新讀取 | STOP: PRD 不可讀，請重新提供 |

> **Iron Rule**: 任一項 FAIL → 立即停止，向使用者列出失敗項目與建議修復步驟。禁止以「猜測」「跳過」「稍後補」方式繼續。

---

<a id="sec-sot"></a>
## Source of Truth 優先序

G2 在盤點 route / page 結構時，必須遵循以下優先序：

1. **manifest 宣告的 sitemap / page graph**（若 `project-manifest.md` 中 `prototype_sitemap` 已宣告）：優先採信其 route / page 關係與導航拓樸
2. **PRD**：補充 page intent、flow 定義、AC；若 manifest 未宣告 sitemap，才由 PRD 推導 route / page 結構（需標記為推導結果）
3. **frame-seed**（若存在）：僅補充 `frameRef`、`type`、`flowId`、`frames{}`，不可覆蓋上述兩層已決定的 route / page 存在性

若三者衝突，以 manifest sitemap > PRD > frame-seed 為準；記錄 diff，集中放入 G4 Gate Package，不在 G2 停等人工。

---

<a id="sec-input"></a>
## Input

| 項目 | 來源 | 必填 |
|------|------|:---:|
| `map.routes{}` | G1 產出 |  |
| PRD 中的頁面/畫面描述 | G0 PRD |  |
| manifest 宣告的 sitemap / page graph | `project-manifest.md` → `prototype_sitemap` | 若已宣告則必讀 |
| component-library.html | manifest 路徑 |  |

<a id="sec-output"></a>
## Output

| 產出物 | 格式 | 存放位置 |
|--------|------|----------|
| `map.pages{}` | JSON 區塊（label + frameRef） | 記憶體暫存 |
| Frame 重複分析 | Markdown 表格 | 顯示在對話中 |
| 積木選配清單 | Markdown checklist | 顯示在對話中 |
| **Component Mapping Table** | Markdown 表格 | **落檔**：`{artifact_dir}/planning/component-mapping.md` |

> **重要**：Component Mapping Table **必須落檔**，不可只存記憶體。G2→G5 可能跨越多個 session，context 會截斷記憶體中的暫存資料。G5 的 FRAME_REGISTRY render function 依賴此表決定每個 frame 該使用哪些 component-library class。

---

<a id="sec-frameref"></a>
## frameRef 命名慣例

- 格式：`frame-{描述性名稱}`
- 範例：`frame-settings-page`, `frame-topup-home`, `frame-topup-confirm`
- 多個 page 共用同一畫面時使用相同 frameRef

---

<a id="sec-dup"></a>
## Frame 重複分析

盤點哪些 frameRef 被多個 page 引用，識別差異點：

```markdown
| frameRef | 引用 pages | 差異點數 | 差異說明 |
|----------|-----------|:-------:|---------|
| frame-settings-page | s1-step-1, s2-step-1, s3-step-1 | 3 | sid, balance, onclick |
| frame-topup-home | s1-step-2, s2-step-2 | 2 | balance, hasRecords |
| frame-topup-select | s1-step-3 | 0 | 僅出現一次 |
```

---

<a id="sec-cmt-format"></a>
## Component Mapping Table 格式

G2 完成積木選配後，必須產出以下表格並落檔至 `{artifact_dir}/planning/component-mapping.md`：

<a id="sec-cmt"></a>
```markdown
## Component Mapping Table

> 由 G2 產出。G5 FRAME_REGISTRY render function 必須參照此表使用 CSS class。

| pageId | frameRef | 使用元件 | CSS Classes | 來源 | 備註 |
|--------|----------|---------|-------------|------|------|
| cpo-list | frame-cpo-list | KPI Card ×4, Data Table, Pagination | c-kpi-card, c-table, c-pagination | component-library | |
| cpo-detail | frame-cpo-detail | Description List, Status Tag, Tabs | c-descriptions, c-status-tag, c-tabs | component-library | |
| login | frame-login | Button, Input | c-btn, c-input | component-library | 需置中容器 |
```

規則：
- **CSS Classes** 欄必須列出該 page 會用到的所有 `c-*` class
- **來源**欄標記 `component-library`（已有）或 `需新建`（library 中不存在）
- 同一 frameRef 被多個 page 引用時，只需列一次

---

<a id="sec-blocks"></a>
## 積木選配規則

1. 若畫面包含 lofi-00 定義的組合 Pattern（A~F），優先整組引用
2. 所有選配元件必須對應 component-library.html 中已存在的實體
3. 若不存在，標記「需新建」

---

<a id="sec-hybrid"></a>
## Hybrid 複用預判

根據 Frame 重複分析，預判每個 frame 的複用策略：

| 條件 | 策略 |
|------|------|
| 差異 ≤ 3 且無條件分支 | Option A（template clone） |
| 差異 > 3 或有條件分支 | Option C（render function） |
| 僅出現一次 | Option C（render function，保持一致） |

> 這是建議值，G5 執行時可能依實際 frame 差異點重新決定最終策略。

---

<a id="sec-dod"></a>
## Definition of Done

1. 每個 route 引用的 pageId 都存在於 `pages{}` 中（外鍵完整性）
2. 每個 page 有 `label`（step panel 顯示名稱）
3. 每個 page 有 `frameRef`（對應的 frame template ID）
4. 同一 `frameRef` 被多個 page 引用時，已識別差異點數量
5. 已對照 component-library 列出積木選配清單
6. 若有元件不在 library 中，已標記「需新建」
7. 已根據 Hybrid 規則預判每個 frame 的複用策略（A 或 C）
8. **Component Mapping Table 已落檔**至 `{artifact_dir}/planning/component-mapping.md`
