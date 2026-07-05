# G3：AC Extraction

> 為每個 page 定義逐步驗收條件（Acceptance Criteria）。

---

## 目錄

- [前置依賴](#sec-deps)
- [Pre-flight Checklist](#sec-preflight)
- [Input](#sec-input)
- [Output](#sec-output)
- [AcItem 物件格式](#sec-acitem)
- [AC 撰寫規則](#sec-rules)
- [情境模板](#sec-templates)
- [AC 覆蓋預覽格式](#sec-preview-format)
- [AC 覆蓋預覽（初步比對）](#sec-preview)
- [Definition of Done](#sec-dod)

---

<a id="sec-deps"></a>
## 前置依賴

G2 通過。

---

<a id="sec-preflight"></a>
## Pre-flight Checklist（進入此 Gate 前必須全部通過）

| # | 檢查項 | 檢查方式 | 失敗動作 |
|---|--------|---------|---------|
| PF-1 | G2 已通過 | 確認 `map.pages{}` 在 context 中 | STOP: 回報 G2 尚未完成 |
| PF-2 | PRD AC Master List 已落檔 | 讀取 `{artifact_dir}/planning/prd-ac-master-list.md` 確認存在且可讀 | STOP: 落檔遺失，請重新執行 G0 產出 |
| PF-3 | PRD 完整內容在 context 中 | 確認 PRD 文件可讀 | STOP: PRD 不在 context 中，請重新提供 PRD 路徑 |

> **Iron Rule**: 任一項 FAIL → 立即停止，向使用者列出失敗項目與建議修復步驟。禁止以「猜測」「跳過」「稍後補」方式繼續。

<a id="sec-input"></a>
## Input

| 項目 | 來源 | 必填 |
|------|------|:---:|
| `map.pages{}` | G2 產出 |  |
| PRD 完整內容 | G0 PRD |  |
| PRD AC Master List | G0 落檔 |  |

<a id="sec-output"></a>
## Output

| 產出物 | 格式 | 存放位置 |
|--------|------|----------|
| `map.pages[].acs[]` | JSON 陣列（AcItem 物件） | 記憶體暫存 |
| 情境清單 | Markdown | 顯示在對話中 |
| AC 統計摘要 | 表格（route × step × AC 數） | 顯示在對話中 |
| AC 覆蓋預覽 | 與 PRD Master List 初步比對 | 顯示在對話中 |

---

<a id="sec-acitem"></a>
## AcItem 物件格式

```typescript
interface AcItem {
  id: string     // e.g. "1-1-1"（scenario-step-序號）
  text: string   // AC 描述文字（顯示在 Checklist 中）
  prd?: string   // PRD 原文（完整，出現在 ⓘ popover）
  src?: string   // 來源章節（e.g. "PM §1-1"）
}
```

---

<a id="sec-rules"></a>
## AC 撰寫規則

### 禁止引用縮寫

`prd` 欄位**嚴禁**使用「同 1-1-1」、「同 S1」等引用縮寫。若某 AC 的 PRD 依據與其他 Scenario 相同，**必須完整複製展開原文**，確保每條 AC 均可獨立閱讀。

### AC 粒度指引

| 粒度 | 判斷 | 範例 |
|------|------|------|
|  適中 | 描述具體可觀察的行為 | 「點擊儲值按鈕後跳轉至金額選擇頁」 |
|  過粗 | 太抽象，無法驗證 | 「頁面顯示正確」 |
|  過細 | 實作細節，非業務邏輯 | 「按鈕有 hover 效果」 |

### 正常流程 AC 包含微互動

Hover 顯示 Tooltip、點擊展開收合、開啟彈窗等正常操作行為，屬於 Happy Path AC 的一部分，不拆為獨立情境。

---

<a id="sec-templates"></a>
## 情境模板

每個 page 的 AC 應涵蓋以下情境（依適用性）：

| 情境類型 | 觸發條件 | AC 內容方向 |
|---------|---------|------------|
| Happy Path | 永遠需要 | 完整資料的預設畫面 + 正常微互動 |
| Empty State | 有資料列表時 | 空白狀態的 UI + 引導行動 |
| Loading State | 有資料請求時 | Skeleton 取代內容區 |
| Error State | 有 API 依賴時 | 錯誤提示 + 重試按鈕 |

---

<a id="sec-preview-format"></a>
## AC 覆蓋預覽格式

G3 完成後，初步比對 PRD AC Master List 與已定義的 AC：

```markdown
<a id="sec-preview"></a>
## AC 覆蓋預覽（初步比對）

| PRD AC ID | PRD AC 描述 | Map AC ID | 狀態 |
|-----------|------------|-----------|------|
| PM-AC-1 | 顯示儲值金頁面 | 1-1-1 |  已覆蓋 |
| PM-AC-5 | 金額上限檢查 | — |  可能未覆蓋 |

> 此為初步預覽，正式覆蓋比對在 G4 執行。
```

---

<a id="sec-dod"></a>
## Definition of Done

1. 每個 page 至少 1 條 AC
2. 每條 AC 有 `id`（追蹤用）和 `text`（顯示文字）
3. 每條 AC 的 `prd` 欄位完整引用 PRD 原文，嚴禁縮寫
4. 每條 AC 有 `src`（來源章節）
5. AC 可驗證：描述具體可觀察的行為
6. AC 粒度適中
7. Flow Shell：每個 step 的 AC 涵蓋該步驟的關鍵互動行為
8. 正常流程 AC 包含微互動，不拆為獨立情境
9. 已與 PRD AC Master List 做覆蓋預覽
