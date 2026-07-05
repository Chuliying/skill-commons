# Prototype Workflow Implementation（v4）

> 目標：將 prototype 流程收斂為以 `prototype-map` 為主體的正式工作流，並把 `frame-seed` 降為可選的結構輔助層。
> 本文件是 implementation 主幹文件，重點在 artifact、流程、責任與邊界，不展開過細的 gate 內部實作。

---

## 目錄

- [1. 核心結論](#sec-1)
- [2. 這次要達到的效果](#sec-2)
- [3. Artifact 模型](#sec-3)
  - [3.1 PRD](#sec-3-1)
  - [3.2 manifest-declared sitemap / page graph](#sec-3-2)
  - [3.3 frame-seed](#sec-3-3)
  - [3.4 prototype-map](#sec-3-4)
  - [3.5 HTML Prototype](#sec-3-5)
  - [3.6 prototype tune mode](#sec-3-6)
- [4. 正式主鏈](#sec-4)
- [5. Optional Branch：frame-seed](#sec-5)
- [6. Source of Truth 規則](#sec-6)
- [7. page.type 的 Phase 1 範圍](#sec-7)
- [8. Freeze 與版本規則](#sec-8)
- [9. HTML Output 規則](#sec-9)
- [10. Verification 邊界](#sec-10)
- [11. prototype tune mode 的位置](#sec-11)
- [12. 角色責任](#sec-12)
- [13. Non-goals](#sec-13)
- [14. 本文件之後的 task 方向](#sec-14)
- [15. 結論](#sec-15)

---

<a id="sec-1"></a>
## 1. 核心結論

v4 只做一個關鍵收斂：

**主鏈是 `PRD -> manifest-declared sitemap/page graph -> prototype-map -> freeze -> HTML Prototype -> prototype tune mode`**

其中：

1. `PRD` 是唯一必備輸入
2. manifest 宣告的 `sitemap/page graph` 是優先採信的頁面拓樸來源
3. `prototype-map` 是正式整合資料
4. `frame-seed` 是可選結構層，只在需要穩定骨架時插入
5. `HTML Prototype` 是最終輸出
6. `prototype` tune mode 是尾端 patch 工具，不是主鏈重建工具

---

<a id="sec-2"></a>
## 2. 這次要達到的效果

1. 把 `prototype-map` 拉回 prototype 流程的主體位置
2. 把 manifest 宣告的 `sitemap/page graph` 納入正式結構輸入，優先於 AI 純推導
3. 讓沒有 `frame-seed` 的情況下，主鏈也能完整運作
4. 讓有 `frame-seed` 的情況下，結構資訊能穩定進入 `prototype-map`
5. 讓 G4 freeze 成為正式版本切點
6. 讓 G5 只讀 frozen `prototype-map`
7. 讓 `prototype` tune mode 正式成為尾端工作流的一部分
8. 讓 implementation、workflow、UI/PM 指南、gate 文件後續都能依同一模型對齊

---

<a id="sec-3"></a>
## 3. Artifact 模型

<a id="sec-3-1"></a>
### 3.1 PRD

`PRD` 是唯一必備輸入。

它負責定義：

1. epic 範圍
2. route / page / flow
3. 每頁目的與內容意圖
4. acceptance criteria

`PRD` 是需求與頁面存在性的唯一主來源，不能被 `frame-seed` 取代。

<a id="sec-3-2"></a>
### 3.2 manifest-declared sitemap / page graph

shared skill 不可假設專案內固定有某個函式、API 或檔案可直接代表 sitemap。

因此，只有在 `project-manifest.md` 明確宣告來源時，`sitemap` 或等價的 page graph 才能作為 route / page 關係與導航拓樸的正式輸入。

它負責提供：

1. route 與 page 的關係
2. 導航層級
3. page graph 的既有結構事實

若 manifest 已宣告 sitemap / page graph：

1. 應優先讀取 sitemap
2. 用 sitemap 確認 route / page 關係
3. 再由 PRD 補 page intent、flow 與 AC

若 manifest 未宣告 sitemap / page graph：

1. 才由 AI 根據 PRD 推導 route / page 結構
2. 且需明確標記為推導結果，而非既有事實

<a id="sec-3-3"></a>
### 3.3 frame-seed

`frame-seed.yaml` 是可選的結構稿。

它只負責：

1. 補充畫面骨架
2. 讓多個 page 共用同一個 `frameRef`
3. 提供 `frames{}` 的結構來源
4. 記錄 `warnings`、`UNMAPPED`、`low confidence`

它不負責：

1. 不定義需求
2. 不決定 route / page 是否存在
3. 不存 render function
4. 不直接作為 runtime code
5. 不作為所有 prototype 的必經前置條件

<a id="sec-3-4"></a>
### 3.4 prototype-map

`prototype-map` 是正式整合後的工作資料。

它整合：

1. `PRD` 的內容意圖、flow、AC、meta
2. manifest 宣告的 `sitemap/page graph` 的 route / page 結構（若存在）
3. `frame-seed` 的骨架資料（若存在）

freeze 前：

1. 它是正在建構中的整合資料
2. 允許補強與回補

freeze 後：

1. 它成為正式版本檔 `prototype-map-v{N}.json`
2. G5 只能讀 frozen map
3. 任意結構變更都必須走新版本

<a id="sec-3-5"></a>
### 3.5 HTML Prototype

HTML Prototype 是最終可互動原型。

它：

1. 由 frozen `prototype-map` 產出
2. 在 G5 生成 `FRAME_REGISTRY`、`SCENARIO_STATE` 與 HTML 結構
3. 不是 source of truth

<a id="sec-3-6"></a>
### 3.6 prototype tune mode

`prototype` tune mode 是尾端微調工具。

它：

1. 用在 HTML 已產出之後
2. 處理局部視覺與互動 patch
3. 不取代結構重建

---

<a id="sec-4"></a>
## 4. 正式主鏈

### Step 1：PRD Input

輸入：

1. `PRD`

輸出：

1. PRD 摘要
2. 初步 `meta`
3. AC basis

### Step 2：Resolve Sitemap / Page Graph

輸入：

1. `PRD`
2. manifest 宣告的 sitemap / page graph（若存在）

輸出：

1. route / page 結構基底
2. 導航拓樸基底

規則：

1. 若 manifest 已宣告 sitemap，優先採用該 sitemap 作為 route / page 關係基底
2. 若 manifest 未宣告 sitemap，才由 AI 根據 PRD 推導 page graph
3. AI 推導出的 graph 必須標示為推導結果

### Step 3：Build PrototypeMap Skeleton

輸入：

1. `PRD`
2. manifest-declared `sitemap/page graph`

輸出：

1. `routes{}`
2. `pages{}`
3. `pages[].acs[]`
4. `meta`

這一步在沒有 `frame-seed` 的情況下也必須可以完成。

### Step 4：Optional Structural Stabilization

這一步是 optional branch，不是主鏈強制步驟。

可選輸入：

1. 參考截圖
2. 現有畫面
3. `ui-scanner`

輸出：

1. `frame-seed.draft.yaml`
2. `warnings.md`
3. 確認後的 `frame-seed.yaml`

### Step 5：Merge Into PrototypeMap

若存在 `frame-seed`，在此步驟將其結構資料併入 `prototype-map`。

若不存在 `frame-seed`，此步驟直接略過，主鏈照常前進。

### Step 6：Freeze

輸出：

1. `prototype-map-v{N}.json`
2. gap / coverage 結果
3. freeze 摘要

freeze 後，G5 只讀此版本。

### Step 7：HTML Output

輸入：

1. frozen `prototype-map`

輸出：

1. HTML Prototype

### Step 8：Verification

驗證：

1. frozen map 是否完整
2. HTML 是否忠實反映 frozen map

### Step 9：Tuning

若只是局部視覺或互動修正，走 `prototype` tune mode。

若問題已涉及 route / flow / frame 結構，則不應只靠 tuner，而應回主鏈處理。

---

<a id="sec-5"></a>
## 5. Optional Branch：`frame-seed`

### 5.1 定位

`frame-seed` 是 G2 的 optional structural extension，不是獨立主鏈。

它沿用 PRD，讓結構更穩定且更容易審核。

### 5.2 何時建議啟用

1. 多個 page 共用同一種骨架，需要穩定 `frameRef`
2. 即使 manifest 已宣告 sitemap，頁面骨架仍複雜，單靠 PRD 與 sitemap 難以穩定推導
3. 有可用的現有畫面或參考截圖可作校正
4. 團隊希望在 HTML 產出前先審核結構層

### 5.3 何時可跳過

1. 頁面數少，骨架單純
2. PRD 已足夠清楚
3. 沒有參考材料，且不值得額外整理結構稿
4. 目前目標是先快速產出第一版 prototype

### 5.4 重要原則

1. 沒有 `frame-seed`，主鏈仍必須可跑通
2. 有 `frame-seed` 時，也不能讓它取代 PRD 成為主來源

---

<a id="sec-6"></a>
## 6. Source of Truth 規則

### 6.1 manifest-declared sitemap / page graph 決定的事

若 manifest 已宣告 sitemap 或等價 page graph，以下內容優先由其決定：

1. route 與 page 的對應關係
2. 導航層級與 page graph 結構
3. 既有頁面拓樸事實

### 6.2 PRD 決定的事

以下內容由 PRD 決定：

1. page 的業務意圖
2. flow 的存在與目的
3. acceptance criteria
4. 在 manifest 未宣告 sitemap 時，route/page 結構的推導依據

若 manifest 未宣告 sitemap，才由 AI 根據 PRD 模擬 route / page 結構。

### 6.3 frame-seed 可補的事

以下內容可由 `frame-seed` 補入：

1. `pages[].frameRef`
2. `pages[].type`
3. `pages[].flowId`
4. `frames{}`

### 6.4 frame-seed 不可覆蓋的事

以下內容不得由 `frame-seed` 覆蓋：

1. manifest 已宣告 sitemap 的 route/page 結構
2. PRD 定義的 page intent
3. AC 內容
4. PRD meta

### 6.5 衝突處理

若 `frame-seed` 與 PRD 或 manifest 宣告的 sitemap 衝突：

1. 以 manifest 宣告的 sitemap 為準決定既有 route / page 結構
2. 若 manifest 未宣告 sitemap，則以 PRD 為準決定 route / page / flow existence
3. `frame-seed` 僅保留為結構參考
4. 衝突必須顯示 diff，交由人工確認

---

<a id="sec-7"></a>
## 7. `page.type` 的 Phase 1 範圍

### 7.1 定義

`pages[pageId].type` 使用以下值：

1. `surface`
2. `flow-step`

### 7.2 規則

1. `surface`：獨立頁面
2. `flow-step`：流程中的一步，必須搭配 `flowId`
3. 同一個 `flowId` 的步驟順序，以其在 `route.pages[]` 中的出現順序為準
4. 同一個 `flowId` 的 pages 必須出現在同一個 route 中

### 7.3 Phase 1 邊界

這一版只做：

1. schema 表達
2. validation 規則
3. metadata 標註

這一版不做：

1. 新的 runtime mode
2. 新的 `engine.js` 行為分支
3. 額外的 stepper runtime 規則擴張

---

<a id="sec-8"></a>
## 8. Freeze 與版本規則

### 8.1 Freeze 的角色

G4 是正式版本切點。

freeze 之後：

1. map 進入版本化狀態
2. G5 只能讀 frozen map
3. 任何結構性調整都應建立新版本

### 8.2 Freeze 產出物

1. `prototype-map-v{N}.json`
2. gap / coverage 結果
3. freeze 摘要

### 8.3 Gap / Coverage / Backfill 骨架（draft）

freeze 前必須產出 gap report，包含以下欄位：

1. `meta.coverageRate`：已覆蓋 AC 數 / 總 AC 數（百分比，e.g. 83.3）
2. `meta.gaps[]`：未覆蓋項目列表，每項為 `GapItem { prdAcId, description, reason, acknowledgedBy }`
3. `meta.backfillRound`：當前回補輪次（從 0 開始）

決策規則：

1. `coverage = 100%`：直接進入 freeze
2. `coverage < 100%` 且 gap 可接受（人工確認）：標記 gap 後進入 freeze
3. `coverage < 100%` 且 gap 不可接受：回補後重新計算 coverage
4. 回補輪數上限：2 輪。超過 2 輪仍未達標，須退回 PRD 或結構層重新整理

### 8.4 後續版本原則

1. 若 PRD 在 freeze 前變更，從受影響的最早 gate 重入
2. 若 PRD 在 freeze 後變更，建立新版本 `v{N+1}`
3. 舊版本保留，不覆蓋

---

<a id="sec-9"></a>
## 9. HTML Output 規則

### 9.1 正式輸入

G5 的正式輸入是 frozen `prototype-map`。

### 9.2 `FRAME_REGISTRY` 的位置

`FRAME_REGISTRY`：

1. 不存在於 `frame-seed`
2. 不存在於 `prototype-map`
3. 只存在於 G5 產出的 HTML / runtime code

### 9.3 `map.frames` 的作用

若 `map.frames` 存在：

1. 它提供 frame 的結構來源
2. G5 依其生成 HTML 結構
3. 但 render function 仍由 G5 實際寫出

若 `map.frames` 不存在：

1. 走既有 builder 路徑
2. 維持向後相容

### 9.4 runtime 邊界

Phase 1 不修改 `engine.js`。

因此本次只做：

1. 結構來源可由 `map.frames` 驅動
2. HTML 中保留必要結構標記供驗證使用

不做：

1. 新 runtime mode
2. 新 shell engine 分支

---

<a id="sec-10"></a>
## 10. Verification 邊界

### 10.1 Phase 1 要驗的

1. `prototype-map` 欄位完整性
2. `frameRef` 外鍵完整性
3. `frames` schema 合法性
4. `flow-step` / `flowId` 規則正確
5. HTML 是否能對回 frozen map

### 10.2 Phase 1 不驗的

1. 同輸入重跑兩次是否完全一致
2. component-library 是否與 guide 零差異
3. cross-epic 治理是否完全統一
4. 新 runtime mode 行為

---

<a id="sec-11"></a>
## 11. prototype tune mode 的位置

### 11.1 角色

`prototype` tune mode 用於 HTML 已產出後的局部修正。

適合：

1. 寬度、間距、對齊
2. 局部位置與視覺權重
3. 特定 frame / page / scenario 的小範圍互動修正

不適合：

1. route / page / flow 關係錯誤
2. frame pattern 判斷錯誤
3. 需要重切結構

### 11.2 邊界

v4 先明確定義：

1. tuner 在 G6 之後使用
2. tuner 不是主鏈的一部分，但屬於正式尾端工作流
3. tuner 後是否回寫 `prototype-map` 或 `frame-seed`，需在後續 task 中補正式 sync 規則

---

<a id="sec-12"></a>
## 12. 角色責任

### 12.1 PM

1. 提供或確認 PRD
2. 若 manifest 已宣告相關欄位，提供或確認 sitemap / page graph 來源
3. 定義 route / page / flow 的業務意圖
4. 確認 acceptance criteria
5. 在關鍵人工確認點做決策

### 12.2 UI

1. 視需要提供現有畫面或參考截圖
2. 協助確認哪些 page 應共用骨架
3. review 結構稿是否合理
4. 在 HTML 產出後，若只是局部問題，使用 `prototype` tune mode

### 12.3 Builder / AI

1. 解析 PRD 與 manifest 宣告的 sitemap / page graph
2. 建立 `prototype-map`
3. 在需要時產生並併入 `frame-seed`
4. freeze map
5. 產出 HTML
6. 驗證與回補

---

<a id="sec-13"></a>
## 13. Non-goals

這一版不做：

1. 把 `frame-seed` 變成 mandatory prerequisite
2. 讓 screenshot 取代 PRD 成為主輸入
3. 發明新的 runtime mode
4. 修改 `engine.js`
5. 把 UI/PM 文件寫成工程 gate 細節文件
6. 一次做完所有治理、命名、重跑一致性與 cross-epic 規則

---

<a id="sec-14"></a>
## 14. 本文件之後的 task 方向

在 v4 主幹確立後，後續實作將依序補上：

1. `prototype-map` 生命週期細節
2. G2 的 source-of-truth 規則
3. Freeze / Gap / Backfill 規格
4. `frame-seed` 啟用與 merge 規則
5. `page.type` 的 validator / schema 對齊
6. `prototype` tune mode 的 artifact sync 規則
7. workflow、gate 文件、schema、validator 的一致性更新

---

<a id="sec-15"></a>
## 15. 結論

v4 的核心是重新排定層級，避免增加不必要的中介層：

1. `PRD` 是唯一必備輸入
2. `sitemap/page graph` 是優先採信的結構輸入
3. `prototype-map` 是正式主體
4. `frame-seed` 是可選結構層
5. frozen map 是 G5 的唯一正式輸入
6. `HTML Prototype` 是輸出結果
7. `prototype` tune mode 是尾端 patch 工具

後續所有文件與腳本，都應回到這個模型上對齊。
