# G5：HTML Output

> 讀取凍結 map + 元件庫 + 共用模板，產出可互動的 Prototype HTML。

---

## 目錄

- [前置依賴](#sec-deps)
- [Pre-flight Checklist](#sec-preflight)
- [Input](#sec-input)
- [Output](#sec-output)
- [執行流程（三步驟）](#sec-flow)
  - [Step 1：建立目錄與複製資源](#sec-flow-1)
  - [Step 2：載入凍結策略](#sec-flow-2)
  - [Step 3：AI 填入 3 個區塊](#sec-flow-3)
- [兩段式確認流程](#sec-confirm)
  - [凍結內容](#sec-stage1)
  - [產出完整 HTML](#sec-stage2)
- [AI 填入格式規範](#sec-format)
- [Component Library → Render Function 映射指引](#sec-mapping)
- [AI 禁止事項](#sec-forbidden)
- [Shell 選擇規則](#sec-shell)
- [CSS class 前綴系統](#sec-css)
- [灰階規範](#sec-gray)
- [Frame 複用規則](#sec-reuse)
- [Definition of Done](#sec-dod)

---

<a id="sec-deps"></a>
## 前置依賴

G4 通過（map 已凍結）。

---

<a id="sec-preflight"></a>
## Pre-flight Checklist（進入此 Gate 前必須全部通過）

| # | 檢查項 | 檢查方式 | 失敗動作 |
|---|--------|---------|---------|
| PF-1 | Frozen map JSON 存在且可讀 | 讀取 `{artifact_dir}/data/prototype-map-v{N}.json` | STOP: 凍結 map 不存在，請先完成 G4 |
| PF-2 | Scaffold template 存在 | 讀取 `{shared_skills_root}/prototype/templates/scaffold-standard.html` | STOP: scaffold 不存在，檢查 shared skill 安裝 |
| PF-3 | Component library 存在且非空 | 讀取 manifest `component_library` 路徑，確認檔案存在且包含 `<style>` 或 CSS | STOP: component library 不存在或為空 |
| PF-4 | Component Mapping Table 存在 | 讀取 `{artifact_dir}/planning/component-mapping.md`。若不存在 → **must 重讀 component-library.html 並重建此表** | STOP: 無法重建 Component Mapping，請重新執行 G2 |
| PF-5 | Templates CSS/JS 資源齊全 | 確認 `engine.js`、`shell-common.css`、`shell-standard.css`、`shell-flow.css`、`print-report.css` 都存在於 templates/ | STOP: 列出缺失的 template 資源 |

> **Iron Rule**: 任一項 FAIL → 立即停止，向使用者列出失敗項目與建議修復步驟。禁止以「猜測」「跳過」「稍後補」方式繼續。

---

<a id="sec-input"></a>
## Input

| 項目 | 來源 | 必填 | 備註 |
|------|------|:---:|------|
| `{artifact_dir}/data/prototype-map-v{N}.json` | G4 凍結檔案 |  | |
| component-library.html | manifest 路徑 |  | 若同 session 已在 G2 讀取，可復用元件精簡摘要。**若 context 中無摘要，must 重讀整份 library** |
| `scaffold-standard.html` | shared templates/ |  | standard/flow 共用 scaffold |
| `engine.js` | shared templates/ |  | **READONLY — 不得修改** |
| `shell-common.css` + `shell-{type}.css` | shared templates/ |  | **直接複製，不得修改** |
| `component-library.html` 或對應 CSS | manifest 路徑 |  | **必須產出 `assets/component-library.css` 供 HTML 載入** |
| `print-report.css` | shared templates/ |  | **直接複製，不得修改** |
| `frame-reuse-spec.md` | shared references/ |  | |
| **Component Mapping Table** | `{artifact_dir}/planning/component-mapping.md`（G2 落檔） |  | **跨 session 必讀**。決定每個 frame 的 render function 使用哪些 component-library class |
| G4 Gap Report | 對話 context / 落檔 |  | 確認哪些 AC 已覆蓋 / 帶缺口凍結 |

<a id="sec-output"></a>
## Output

| 產出物 | 格式 | 存放位置 |
|--------|------|----------|
| `index.html` | HTML | `{artifact_dir}/` |
| `engine.js` | JS（從 templates 複製） | `{artifact_dir}/assets/` |
| `shell-common.css` | CSS（從 templates 複製） | `{artifact_dir}/assets/` |
| `shell-standard.css` | CSS（從 templates 複製） | `{artifact_dir}/assets/` |
| `shell-flow.css` | CSS（從 templates 複製） | `{artifact_dir}/assets/` |
| `component-library.css` | CSS（從 component library 抽取或複製） | `{artifact_dir}/assets/` |
| `print-report.css` | CSS（從 templates 複製） | `{artifact_dir}/assets/` |

---

<a id="sec-flow"></a>
## 執行流程（三步驟）

<a id="sec-flow-1"></a>
### Step 1：建立目錄與複製資源（shell command，零 AI output token）

```bash
# 取得 templates 路徑（從 project-manifest.md 的 shared_skills_root 解析）
TEMPLATES="{shared_skills_root}/prototype/templates"
OUT_DIR="{artifact_dir}"
COMPONENT_LIBRARY="{component_library}"

# 建立專屬目錄結構
mkdir -p "$OUT_DIR/assets"
mkdir -p "$OUT_DIR/data"

# 複製依賴檔到 assets
cp "$TEMPLATES/engine.js"          "$OUT_DIR/assets/"
cp "$TEMPLATES/shell-common.css"   "$OUT_DIR/assets/"
cp "$TEMPLATES/shell-standard.css" "$OUT_DIR/assets/"
cp "$TEMPLATES/shell-flow.css"     "$OUT_DIR/assets/"
cp "$TEMPLATES/print-report.css"   "$OUT_DIR/assets/"

# 將 component library 轉成 output 可直接載入的 CSS
if grep -q "<style" "$COMPONENT_LIBRARY"; then
  awk '
    /<style[^>]*>/ { in_style=1; sub(/^.*<style[^>]*>/, ""); if (length) print; next }
    /<\/style>/    { sub(/<\/style>.*$/, ""); if (length) print; in_style=0; next }
    in_style       { print }
  ' "$COMPONENT_LIBRARY" > "$OUT_DIR/assets/component-library.css"
else
  cp "$COMPONENT_LIBRARY" "$OUT_DIR/assets/component-library.css"
fi

# 複製 scaffold 到根目錄並更名為 index.html
cp "$TEMPLATES/scaffold-standard.html" "$OUT_DIR/index.html"
```

> **AI 不輸出這些檔案的內容，用 cp 複製即可。**
> 兩個 shell CSS 都複製，避免遺漏。HTML 中的 `<link>` 引用哪個由 shellType 決定（見下方 Shell 選擇規則）。
> 若 `component-library.css` 產出為空檔，G5 必須停止並回報 library 缺少可載入樣式，禁止默默跳過。

<a id="sec-flow-2"></a>
### Step 2：載入 G4 已核可的 frame strategy 與 SCENARIO_STATE

直接使用 frozen map 與 G4 Gate Package；不得在 G5 再要求人工確認。

<a id="sec-flow-3"></a>
### Step 3：AI 填入 3 個區塊

修改 `$OUT_DIR/index.html`，在 `AI_FILL:` 標記之間填入內容：

| 區塊 | 標記 | 內容 | AI 判斷量 |
|------|------|------|:--------:|
| ① NAV_HTML | `NAV_HTML_START` ~ `NAV_HTML_END` | 左欄 `<li>` 列表 | 零（機械轉換 routes） |
| ② PANELS_HTML | `PANELS_HTML_START` ~ `PANELS_HTML_END` | 右欄 scenario panel + frame `<div>` | 零（每個 route 一個固定結構） |
| ③ DATA_JS | `DATA_JS_START` ~ `DATA_JS_END` | 資料變數 + FRAME_REGISTRY | 低（只有 frame render 需要創意） |

---

<a id="sec-confirm"></a>
## 凍結策略使用方式

<a id="sec-stage1"></a>
### 凍結內容

G4 已核可的內容應包含：

```markdown
## Frame 清單

| Frame ID | 出現在 Scenario | 差異點數 | 策略 | SCENARIO_STATE 初始值 |
|---------|----------------|:------:|------|---------------------|
| frame-home | s1-step-1, s2-step-1 | 1 | A（template clone） | s1: balance=$0; s2: balance=$500 |
| frame-topup-select | s1-step-2 | — | FRAME_REGISTRY | s1: selectedAmount=null |

AI 推導的初始值（已於 G4 核可）：
- s1.balance: "$0"（推導自 PRD「首次儲值」情境）
```

若凍結內容缺少策略或初始值，回到 G4 更新版本；不可在 G5 臨時補問。

<a id="sec-stage2"></a>
### 產出完整 HTML

依確認的 Frame 清單和策略，修改 `$OUT_DIR/index.html` 中的 3 個 AI_FILL 區塊。

---

<a id="sec-format"></a>
## AI 填入格式規範

### ① NAV_HTML 格式

```html
<li class="c-nav-group-label" data-scope="後台">合作 CPO 管理</li>
<li class="c-nav-link-item is-active" onclick="switchScenario('s1', this)">CPO 管理</li>
<li class="c-nav-group-label" data-scope="後台">分潤方案管理</li>
<li class="c-nav-link-item" onclick="switchScenario('s2', this)">分潤方案管理</li>
<li class="c-nav-group-label" data-scope="LIFF">外部站點充電</li>
<li class="c-nav-link-item" onclick="switchScenario('s3', this)">LIFF 外部 CPO 充電流程</li>
```

規則：
- 每個 `route.group` 一個 `c-nav-group-label`
- 若 `route.group` 為 `{scope}：{name}` 格式（分隔字元接受「：」或「:」），拆分為：
  - `data-scope="{scope}"`（例：`後台`、`LIFF`）→ CSS 以 chip 呈現
  - `label` 本體只放 `{name}`（例：`合作 CPO 管理`）→ 去掉前綴
- 若 `route.group` 不含分隔字元，省略 `data-scope` attribute，label 原樣填入（向下相容）
- 第一個 `c-nav-link-item` 加 `is-active`
- onclick 格式固定：`switchScenario('{routeId}', this)`
- `c-nav-group-label` 與後方 `c-nav-link-item` 的對映關係要連續（group 在前、link-item 緊接），engine.js 會依 DOM 相鄰性同步 `is-parent-active`

### ② PANELS_HTML 格式（Standard Shell）

> **結構變更**：Prototype Map ID Bar 已提升為「全域 dev 標籤」，掛在 `<main class="l-preview-area">` 最上方，由 scaffold 模板固定提供（PANELS_HTML 不含、也不需輸出此元素）。`c-standard-shell` 不再有 `__header`；每個 scenario panel 內只負責 mock UI。

```html
<div id="scenario-s1" class="l-scenario-panel is-active">
  <div class="c-standard-shell">
    <div class="c-standard-shell__content" style="background:#f0f2f5; padding: 24px;">
      <div id="s1-cpo-list" class="c-flow-frame"></div>
      <div id="s1-cpo-detail" class="c-flow-frame"></div>
    </div>
  </div>
</div>

<div id="scenario-s2" class="l-scenario-panel">
  <div class="c-standard-shell">
    <div class="c-standard-shell__content" style="background:#f0f2f5; padding: 24px;">
      <div id="s2-revenue-list" class="c-flow-frame"></div>
      <div id="s2-revenue-new" class="c-flow-frame"></div>
    </div>
  </div>
</div>
```

規則：
- panel id：`scenario-{routeId}`
- 第一個 panel 加 `is-active`
- frame div id：`{routeId}-{pageId}`
- 每個 page 一個 `c-flow-frame` div（內容由 FRAME_REGISTRY 動態渲染）
- **c-standard-shell 不得輸出 `__header` 或任何 `c-shell-id-bar`**：ID Bar 只保留一份，由 scaffold 模板放在 `<main class="l-preview-area">` 最上方；engine.js 的 `updateShellIdBar(sid, stepId)` 會於每次 `goTo` 時更新該全域 bar。
- **禁止在 scenario shell 內加任何「頁面 header / 品牌 / 系統名稱」等展示性元素**：這類 mock UI header（如後台的 header bar、頁籤列）應由 frame 內容自行繪製，不得與 Prototype Map ID Bar 混淆。

### ③ DATA_JS 格式

```javascript
var PROTOTYPE_MAP = {
  "meta": {
    "projectName": "專案名稱",
    "prdVersion": "v1.0",
    "shellType": "standard",
    "createdAt": "2026-01-01T00:00:00Z",
    "frozenAt": "2026-01-01T00:00:00Z",
    "coverageRate": 100,
    "gaps": []
  },
  "routes": {                          //  必須是 Object，禁止 Array
    "s1": { "name": "場景名", "group": "群組", "pages": ["pageId1"] }
  },
  "pages": {                           //  必須是 Object，禁止 Array
    "pageId1": {
      "label": "步驟名",
      "frameRef": "frame-xxx",
      "acs": [{ "id": "1-1-1", "text": "AC 描述", "prd": "PRD 原文", "src": "來源" }]
    }
  }
};

var SCENARIO_TITLES = { "s1": "場景名" };
var NAV_PATH = { "s1": ["pageId1"] };
var STEPS = { "s1": [{ "id": "pageId1", "label": "步驟名", "dotIdx": 0 }] };
var STEPPER_LABELS = { "s1": ["步驟名"] };
var PANEL_MAP = { "s1": "scenario-s1" };
var AC_DATA = { "s1": { "pageId1": PROTOTYPE_MAP.pages["pageId1"].acs } };
var SCENARIO_STATE = { "s1": {} };

var FRAME_REGISTRY = {
  // 後台列表頁範例：使用 component-library 的真實 class
  'frame-list-page': function(ctx) {
    return '<div class="c-library-layout">' +
      '<section class="c-library-section">' +
        '<h3 class="c-library-section__title">重點概覽</h3>' +
        '<div class="c-library-grid">' +
          '<div class="c-kpi-card"><div class="c-kpi-card__label">總數</div><div class="c-kpi-card__value">128</div></div>' +
          '<div class="c-kpi-card"><div class="c-kpi-card__label">本月新增</div><div class="c-kpi-card__value">12</div></div>' +
        '</div>' +
      '</section>' +
      '<section class="c-library-section">' +
        '<table class="c-table"><thead><tr><th>名稱</th><th>狀態</th></tr></thead>' +
        '<tbody><tr><td>項目 A</td><td><span class="c-status-tag c-status-tag--success">啟用</span></td></tr></tbody></table>' +
        '<div class="c-pagination"><span class="c-pagination__item is-active">1</span><span class="c-pagination__item">2</span></div>' +
      '</section>' +
    '</div>';
  },
  // Mobile flow-step 頁範例
  'frame-mobile-step': function(ctx) {
    return '<div class="c-library-layout">' +
      '<section class="c-library-section">' +
        '<div class="c-form-grid">' +
          '<div><label>欄位名</label><input class="c-input" disabled placeholder="請輸入"></div>' +
        '</div>' +
      '</section>' +
      '<div><button class="c-btn c-btn--primary" style="width:100%">確認送出</button></div>' +
    '</div>';
  }
};
```

> ** 範例中的每個 CSS class（`c-library-layout`、`c-kpi-card`、`c-table`、`c-btn` 等）都來自 component-library.css 或 shell-*.css。禁止使用不存在的 class。**

UI 規範補充（根源模板行為）：
- AC 備註按鈕使用**單一 comment icon**，`is-has-note` 只改藍色 active 狀態，不切換第二個 icon。
- 登入/授權 frame 使用置中容器（flex 水平與垂直置中），避免卡片貼齊左上。
- schemaVersion 2 map 的每個 page 都應保留 `type`；若 `type='flow-step'`，對應 `flowId` 必須原樣帶入，不可在 G5 丟失。

---

<a id="sec-mapping"></a>
## Component Library → Render Function 映射指引

FRAME_REGISTRY 的每個 render function **必須**：

1. **讀取 Component Mapping Table**（`{artifact_dir}/planning/component-mapping.md`），確認該 frame 對應的 CSS class 清單
2. 使用 `c-library-layout` 作為頁面內容的根容器
3. 使用 `c-library-section` 包裝每個內容區塊（KPI、表格、表單等）
4. 使用 `c-library-grid` 做多欄佈局（KPI 卡片、篩選條件等）
5. 使用 component-library.css 中定義的具體元件 class：
   - 資料卡片 → `c-kpi-card`（含 `__label` / `__value` / `__hint`）
   - 表格 → `c-table`（含 `th` / `td`）
   - 按鈕 → `c-btn`（含 `--primary` / `--secondary`）
   - 表單 → `c-input` / `c-select` / `c-textarea` / `c-form-grid`
   - 狀態標籤 → `c-status-tag`（含 `--success` / `--warning` / `--danger`）
   - 分頁 → `c-pagination`（含 `__item`）
   - 描述列表 → `c-descriptions`（含 `__item`）
   - 頁籤 → `c-tabs`（含 `__item`）
   - 提示 → `c-alert`（含 `--info` / `--warning` / `--danger`）
   - 彈窗 → `c-modal`（含 `__title` / `__actions`）
   - 麵包屑 → `c-breadcrumb`
6. 佈局微調允許使用 inline `style`（如 `padding`、`min-height`），但**不可用 inline style 取代已有的 component class**

若 Component Mapping Table 中有標記「需新建」的元件，而 G4 未核可 → 回到 G4 更新 Gate Package。

---

<a id="sec-forbidden"></a>
## AI 禁止事項

1. **禁止 `<style>` 區塊**：CSS 必須用 `<link>` 引用，不可 `<style>` 嵌入。佈局微調（如 `padding`、`margin-top`、`width:100%`）允許使用 inline `style` attribute，但不可用 inline style 取代已有的 component class
2. **禁止修改 engine.js**：runtime 邏輯是 READONLY 的，用 `cp` 複製
3. **禁止自創 CSS class**：只能使用 `shell-*.css` 與 `component-library.css` 中已定義的 class（參照映射指引）
4. **禁止修改 scaffold 結構**：只能在 AI_FILL 標記之間填入內容
5. **禁止 PROTOTYPE_MAP 用 Array**：routes 和 pages 必須是 `{[key]: {...}}` Object
6. **禁止保留 scaffold 填入指示**：產出後移除 `AI_FILL:` 註解
7. **禁止重寫衍生變數的計算邏輯**：AC_DATA 應引用 `PROTOTYPE_MAP.pages`
8. **禁止輸出 CSS/JS 檔案內容**：用 `cp` 複製，節省 token
9. **禁止忽略 page 類型**：schemaVersion 2 的 `pages[].type` 不可遺漏；`flow-step` 的 `flowId` 不可清空

---

<a id="sec-shell"></a>
## Shell 選擇規則

| shellType | 適用場景 | scaffold | CSS |
|-----------|---------|----------|-----|
| `standard` | 儀表板、Web 後台、多步驟頁面 | scaffold-standard.html | shell-standard.css |
| `flow` | Mobile LIFF、App 原型 | scaffold-standard.html | shell-flow.css |

---

<a id="sec-css"></a>
## CSS class 前綴系統

| 前綴 | 用途 | 範例 |
|------|------|------|
| `c-` | Component | `c-btn`, `c-modal`, `c-ac-item` |
| `l-` | Layout | `l-page-container`, `l-scenario-nav`, `l-step-panel` |
| `is-` | State | `is-active`, `is-checked`, `is-disabled` |
| `u-` | Utility | `u-sr-only`, `u-truncate` |

所有 class 必須使用前綴，禁止裸名（如 `.modal`）。

---

<a id="sec-gray"></a>
## 灰階規範

- 核心排版以灰階為主
- 僅 `#2196F3` 藍作為互動色（Primary Button、Active Tab、Active Nav）
- 嚴禁品牌色、真實圖片、紅綠狀態色
- 錯誤/負向狀態用深灰/黑色 + 加粗/底線

---

<a id="sec-reuse"></a>
## Frame 複用規則

→ 見 `references/frame-reuse-spec.md`

---

<a id="sec-dod"></a>
## Definition of Done

0. **G4 frozen map 與 Gate Package 已包含 frame strategy + SCENARIO_STATE**
1. **資源檔案已複製**：engine.js、shell CSS、`component-library.css`、print CSS 都在 output 目錄
2. HTML 可直接在瀏覽器 `file://` 打開並正常運作
3. CSS 以 `<link>` 引用（非 inline `<style>`）
4. 左欄 Scenario Nav 正確渲染所有 routes + groups
   - `c-nav-group-label` 若來源為 `{scope}：{name}` 格式，已拆出 `data-scope` attribute，label 本體只留 `{name}`
5. 中欄 Step Panel 正確顯示 stepper + AC checklist + 導航按鈕
6. 右欄 Preview Area 正確顯示對應 frame
   - `<main class="l-preview-area">` 第一個子元素為**唯一一個** `c-shell-id-bar`（`__label="MAP"` + `__route` + `__sep="/"` + `__page` + `__frame` 五個 span），由 scaffold 模板固定提供
   - `c-standard-shell` 內**不得**再出現 `__header` 或任何 `c-shell-id-bar`
   - 切換 scenario / step 時 id-bar 的 `__route` / `__page` / `__frame` 會同步更新（engine.js 的 `updateShellIdBar`）；使用者可直接選取/複製 ID 交給 `prototype` tune mode
   - scenario shell 內禁止出現「頁面 header / 品牌 / 系統名稱」等展示性元素（若 mock UI 需要 header，由 frame 內容自行繪製）
7. AC 勾選狀態正確讀寫 `localStorage.ac_checked`
8. AC 備註功能正確讀寫 `localStorage.ac_notes`
9. PRD popover（ⓘ icon）正確展開/收合，同時只開一個
10. 步驟導航功能正常（上一步/下一步/重新開始/圓點跳轉）
11. Hybrid 複用：差異 ≤3 用 template clone；>3 或條件分支用 render function
12. 所有 CSS class 使用前綴系統
13. 灰階規範：主色灰階、僅互動藍、禁品牌色
14. 「 匯出確認報告」按鈕存在且功能正常
15. 匯出報告包含 /⬜ + 備註 + 統計 + 簽核欄
16. **PROTOTYPE_MAP 嵌入後，與原始 JSON 對比確認欄位數、AC 項數一致**
17. **HTML 檔案不包含 `<style>` 標籤**
18. **HTML 檔案不包含 engine 函式定義**（goTo、switchScenario、updateShellIdBar、updateNavParentActive 等）
