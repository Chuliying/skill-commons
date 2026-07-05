---
name: prototype-tuning-reference
description: |
  Prototype 輸出後微調專家。用於 UI 針對已產生的 prototype HTML 做小範圍視覺/互動修正，避免誤改全域模板。
  觸發時機: 「太寬/太窄/沒對齊/想微調」等 prototype 視覺修正需求。
  觸發關鍵字: prototype tuning, 微調, 視覺調整, frame-login, 對齊, 間距, 寬度
---

# Prototype Tuner

> 目標：用最小變更修正 prototype 輸出，不誤傷全域規則。

## 何時使用

- 已有 prototype 輸出（`index.html`）但 UI 觀感需要微調
- 只想改特定範圍（frame/scenario/page），不想動全域 CSS
- 希望用「可填模板」或「引導問答」快速表達需求

---

## 互動入口（給 UI）

### 入口 A：可填模板（優先）

先提供使用者以下模板，請對方直接填：

```text
[Prototype Tuning Request]
範圍: frame(frame-login)
現況: 登入卡片太寬，視覺重心偏下
目標: max-width 520px，水平置中
限制: 不改 global css，不改其他 frame
驗收: 僅 s1/login 變更；s2/s3/s4 不變
```

模板檔路徑：`../templates/ui-request-template.md`

### 入口 B：問答引導（資訊不足時）

若模板欄位不完整，改用一次一題補齊（最多 5 題）：

1. 這次要改 `global / frame / scenario / page` 哪一層？
2. 請給我具體目標（例如：寬度、間距、對齊、字級）
3. 有沒有不能動的範圍？
4. 驗收標準是什麼（怎樣算改好）？
5. 目標檔案路徑是什麼（若未提供）？

---

## 範圍語法（必填）

- `global`：全 prototype 共用（高風險，需明確同意）
- `frame(frame-id)`：只改某個 frame（預設推薦）
- `scenario(route-id)`：只改某個 scenario
- `scenario(route-id) page(page-id)`：只改某頁

未指定時，**預設視為 `frame(...)`**，並要求補 `frame-id`。

---

## 執行流程

### Step 0: 讀取 manifest 路徑

先讀 `.agent/project-manifest.md` 取得 `<work_root>`，再從使用者提供的路徑或最近的 `<work_root>/*/prototype/index.html` 定位 artifact。

### Step 1: 定位目標檔案

預設目標檔：

```
{artifact_dir}/index.html
```

`{name}` 推導規則（依序）：
1. 使用者在請求中明確提供（推薦）
2. 若未提供：列出 `<work_root>/*/prototype/index.html`，請使用者選一個
3. 若只有一個子目錄：可自動採用
4. 若有多個且無法判斷：暫停，要求使用者明確指定

若使用者已提供絕對路徑，優先使用使用者路徑。

### Step 2: 先做最小改動設計（不立即改）

輸出一個「最小變更計畫」：

| 項目 | 內容 |
|------|------|
| 影響範圍 | global/frame/scenario/page |
| 修改檔案 | `index.html` / `assets/shell-*.css` |
| 不會修改 | 明確列出不動的區塊 |
| 預估風險 | 低/中/高 |

### Step 3: 套用 patch（最小差異）

規則：
- 優先改 `FRAME_REGISTRY` 的局部樣式（frame-level）
- 非必要不改 `shell-common.css`（global）
- 若必改 global，先在回覆中明確說明原因

### Step 4: 驗證

- JS 語法檢查（`index.html` 內 `DATA_JS` + `assets/engine.js`）
- 目標 selector 存在檢查
- 非目標範圍未變更（抽樣比對）

### Step 5: 回報

回報固定包含：
1. 修改了哪些檔
2. 變更範圍是否符合要求
3. 驗收對照（逐條）

---

## 防呆規則

1. 使用者說「太寬/太窄」但沒指定範圍：先問範圍，不直接改 global。
2. 使用者只給截圖沒給目標：先引導填「目標 + 驗收」。
3. 若請求會影響全域：先警告，再等確認。
4. 同時有多個調整點：拆成編號 patch，逐項驗收。

---

## 變更分級與回寫邊界

tuner 的每次修改必須先判定屬於哪一級，再決定是否需要回寫上游 artifact。

### Level 1：HTML-only patch（預設）

- 只改 `index.html` 或 `assets/` 內的樣式
- 不影響 `prototype-map` 或 `frame-seed` 中的任何結構定義
- 無需回寫，直接完成

### Level 2：需回寫 prototype-map

- 修改涉及 `FRAME_REGISTRY` 中的 section 結構（新增/刪除/重排 section）
- 或修改涉及 `frameRef` 的對應關係
- 必須同步更新 `prototype-map` 中對應的 `frames{}` 或 `pages[].frameRef`
- 更新後 map 版本號 +1（建立 `v{N+1}`）

### Level 3：需回主鏈

- 修改涉及 route / page / flow 關係錯誤
- 或骨架本身判斷錯誤需重切
- **tuner 不處理**，必須回主鏈（從受影響的最早 gate 重入）

### 判斷規則

在 Step 2（最小變更計畫）中，必須標示本次修改屬於 Level 1/2/3。若為 Level 3，暫停並建議使用者回主鏈處理。

---

## Completion Checklist

```markdown
Skill: prototype (tune mode)
□ 已取得範圍（global/frame/scenario/page）
□ 已定義目標與限制
□ 只修改必要檔案（最小 patch）
□ 已完成語法/selector 驗證
□ 已提供驗收對照
```
