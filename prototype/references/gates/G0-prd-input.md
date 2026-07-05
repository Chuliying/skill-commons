# G0：PRD Input

> 讀取 PRD、解析 manifest、萃取結構化摘要與 AC Master List。

---

## 觸發方式

使用者提供 PRD 路徑或貼入 PRD 內容。

## 前置依賴

無（流程起點）。

---

## Pre-flight Checklist（進入此 Gate 前必須全部通過）

| # | 檢查項 | 檢查方式 | 失敗動作 |
|---|--------|---------|---------|
| PF-1 | `project-manifest.md` 存在 | 讀取檔案，確認 `Prototype Config` 區塊存在 | STOP: 回報 manifest 缺失，請使用者建立 |
| PF-2 | `Prototype Config` 必要輸入齊全 | 確認 `component_library`、`prototype_input` 有值；`prototype_sitemap` 可選 | STOP: 列出缺少的欄位 |
| PF-3 | `component_library` 檔案存在且非空 | 讀取檔案，確認包含 `<style>` 或有效 CSS 內容 | STOP: 回報檔案不存在或為空，無法產出帶樣式的 prototype |
| PF-4 | artifact output 與 planning 目錄存在或可建立 | `ls` 或 `mkdir -p` 確認 | STOP: 回報目錄無法建立 |

> **Iron Rule**: 任一項 FAIL → 立即停止，向使用者列出失敗項目與建議修復步驟。禁止以「猜測」「跳過」「稍後補」方式繼續。

## Input

| 項目 | 來源 | 必填 |
|------|------|:---:|
| PRD 文件路徑或內容 | 使用者提供 |  |
| project-manifest.md | 專案根目錄 |  |

## Output

| 產出物 | 格式 | 存放位置 |
|--------|------|----------|
| PRD 結構化摘要 | Markdown | 顯示在對話中（不落檔） |
| `map.meta` 初稿 | JSON 片段 | 記憶體暫存 |
| PRD AC Master List | Markdown 表格（ID + 描述 + 來源章節） | **落檔**：`{artifact_dir}/planning/prd-ac-master-list.md` |

> **重要**：PRD AC Master List **必須落檔**，不可只存記憶體。G0→G4 可能跨越數十個對話 turn，context compression 會截斷記憶體中的暫存資料，G4 的覆蓋比對依賴此檔案。

---

## Manifest 路徑解析

1. 讀取 `project-manifest.md` 的 `Prototype Config` 區塊
2. 取得輸入路徑：
   - `component_library` — 元件庫 HTML 路徑
   - `prototype_input` — PRD 存放目錄
3. 依 artifact contract 建立 `artifact_dir`：`<work_root>/<slug>/prototype`，其中 `planning/` 放中間產物，工作項根目錄維護共用 `meta.yml`
4. 若缺少必要輸入，**立即回報缺什麼，不猜測**

---

## Definition of Done

1. AI 已讀取完整 PRD 內容
2. 已從 manifest 取得 `component_library`，並依 artifact contract 建立 `artifact_dir`
3. 已萃取：功能描述、使用者角色、資料來源（或標記「待工程確認」）
4. 已判定 Shell 類型（`standard` / `flow`）
5. 已填寫 `meta.projectName`、`meta.prdVersion`、`meta.shellType`
6. **已萃取 PRD AC Master List** 並落檔至 `{artifact_dir}/planning/prd-ac-master-list.md`
7. 若 PRD 資訊不足（缺少功能描述或 AC 定義）：**立即暫停，向使用者列出缺漏清單，等待補充後才繼續**。不可帶著不完整的 PRD 進入 G1。
