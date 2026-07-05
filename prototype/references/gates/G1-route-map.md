# G1：Route Map  人工確認

> 從 PRD 摘要建立 Scenario 路由結構。

---

## 前置依賴

G0 通過。

---

## Pre-flight Checklist（進入此 Gate 前必須全部通過）

| # | 檢查項 | 檢查方式 | 失敗動作 |
|---|--------|---------|---------|
| PF-1 | G0 已通過 | 確認 PRD 摘要與 meta 初稿在 context 中 | STOP: 回報 G0 尚未完成，請先完成 G0 |
| PF-2 | PRD AC Master List 已落檔 | 讀取 `{artifact_dir}/planning/prd-ac-master-list.md` 確認存在 | STOP: G0 未落檔 AC Master List，請先補齊 |

> **Iron Rule**: 任一項 FAIL → 立即停止，向使用者列出失敗項目與建議修復步驟。禁止以「猜測」「跳過」「稍後補」方式繼續。

## Input

| 項目 | 來源 | 必填 |
|------|------|:---:|
| PRD 結構化摘要 | G0 產出 |  |
| `meta` 初稿 | G0 產出 |  |

## Output

| 產出物 | 格式 | 存放位置 |
|--------|------|----------|
| `map.routes{}` | JSON 區塊 | 記憶體暫存 |
| `map.meta`（完成版） | JSON 區塊 | 記憶體暫存 |
| Scenario 概覽表 | Markdown 表格 | 顯示在對話中 |

---

## Routes 定義規則

- routeId 格式：`s1`, `s2`, `s3`...（按 scenario 順序）
- 每個 route 必含：
  - `name`：本案（prototype）scenario 名稱（如「首次儲值 Happy Path」）
  - `group`：本頁所屬的本業頁面標籤（至少一組，如「後台：合作 CPO 管理」「LIFF：外部站點充電」）
  - `pages[]`：有序 pageId 陣列（至少 1 個）

### `group` 的 `{scope}：{name}` 格式（推薦）

`group` 若採 `{scope}：{name}` 格式，G5 產出 HTML 時會自動拆分：

| 欄位 | 用途 | 範例 |
|------|------|------|
| `{scope}` | 平台/模組前綴，在左側 nav 轉為 `c-nav-group-label` 的 `data-scope` chip | `後台`、`LIFF`、`App`、`Ops` |
| `{name}` | 本業頁面名稱，顯示在 `c-nav-group-label` 的文字部分 | `合作 CPO 管理`、`外部站點充電` |

- 分隔字元接受**全形「：」或半形「:」**，兩者等價
- 若 `group` 不含分隔字元，scope 為空（chip 不顯示），整段字串會當成 name 原樣顯示（向下相容既有 prototype）
- scope 是純展示標籤，無需預先定義白名單；CSS 會自動以 chip 呈現
- 同一個 scope 可被多個 routes 共用（例：`s1`、`s2` 同屬「後台」）
- `group` 只影響左 nav；全域 Prototype Map ID Bar 顯示的是技術 ID（routeId / pageId → frameRef），不使用 `group`

---

## Scenario 概覽表格式

```markdown
| routeId | group | name | pages 數 |
|---------|-------|------|:--------:|
| s1 | 後台：合作 CPO 管理 | CPO 管理 | 2 |
| s2 | 後台：分潤方案管理 | 分潤方案管理 | 3 |
| s3 | LIFF：外部站點充電 | LIFF 外部 CPO 充電流程 | 8 |
```

---

## Definition of Done

1. 每個 scenario 有唯一 routeId（`s1`, `s2`, ...）
2. 每個 route 有 `name`（本案 scenario 名稱）
3. 每個 route 有 `group`（本頁所屬的本業頁面標籤，至少一組；推薦採 `{scope}：{name}` 格式）
4. 每個 route 有 `pages[]`（有序 pageId 陣列，至少 1 個）
5. Scenario 概覽表已呈現給使用者
6. ** 使用者已確認 routes 結構正確**
