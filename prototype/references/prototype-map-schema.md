# PrototypeMap 資料結構定義

> 所有 Gate 共同操作的單一資料結構（SSOT）。

---

## 目錄

- [核心 Schema](#sec-schema)
- [常見錯誤（禁止）](#sec-errors)
- [從 PrototypeMap 衍生的 JS 變數](#sec-derived)
- [SCENARIO_STATE 最小介面定義](#sec-scenario)
- [routeId 命名規則](#sec-routeid)
- [pageId 命名規則](#sec-pageid)
- [frameRef 命名規則](#sec-frameref)
- [PANEL_MAP 命名規則](#sec-panelmap)
- [檔案命名慣例](#sec-naming)

---

<a id="sec-schema"></a>
## 核心 Schema

```typescript
interface PrototypeMap {
  meta: {
    schemaVersion?: number     // 版本判斷用（v4 起為 2）；預設視為 1
    projectName: string        // G0 產出
    subtitle: string           // G0 產出
    prdVersion: string         // G0 產出
    shellType: 'standard' | 'flow'  // G0 判定
    createdAt: string          // G4 設定（ISO 8601）
    frozenAt?: string          // G4 設定（ISO 8601）
    coverageRate?: number      // G4 計算（e.g. 83.3）
    gaps?: GapItem[]           // G4 記錄（承認缺口時）
    backfillRound?: number     // 當前回補輪次（從 0 開始，上限 2）
    frameSeedRef?: string      // 若有使用 frame-seed，記錄其檔案路徑
    prdHistory?: PrdHistoryItem[]  // PRD 變更記錄
  }
  routes: {                    // G1 產出 —  必須是 Object，禁止 Array
    [routeId: string]: {
      name: string             // 場景顯示名稱
      group?: string           // nav 分組標籤
      pages: string[]          // 有序 pageId 陣列
    }
  }
  pages: {                     // G2 + G3 產出 —  必須是 Object，禁止 Array
    [pageId: string]: {
      label: string            // step panel 顯示名稱（G2 填入）
      frameRef?: string        // frame template ID（G2 填入）
      type?: 'surface' | 'flow-step'  // 頁面類型（v4 新增，預設 surface）
      flowId?: string          // flow-step 必填；同 flowId 的 pages 必須在同一 route 中
      acs: AcItem[]            // AC 驗收條件（G3 填入）
    }
  }
  frames?: {                   // v4 新增（可選）— frame-seed 整合後的骨架結構
    [frameId: string]: Frame
  }
}

// --- v4 新增 ---

interface Frame {
  shell: string                // e.g. "sidebar-left + topbar"
  sections: FrameSection[]     // 有序區塊列表
}

interface FrameSection {
  row: number                  // 同一 frame 內唯一
  label: string                // e.g. "主要 KPI 卡片區"
  span: number                 // 1-12（grid column span）
  count?: number               // 區塊內元素數量（正整數）
  notes?: string               // 補充說明
}

// --- 向後相容規則 ---
// 1. 舊 map（無 meta.schemaVersion）視為 schemaVersion=1，跳過 frames/type/flowId 驗證
// 2. schemaVersion=2 的 map：若 pages[].type='flow-step'，flowId 為必填
// 3. schemaVersion=2 的 map：若 frames{} 存在，所有 pages[].frameRef 必須對應 frames{} 的 key

interface AcItem {
  id: string                   // e.g. "1-1-1"（scenario-step-序號）
  text: string                 // AC 描述文字
  prd?: string                 // PRD 原文（完整，禁止縮寫引用）
  src?: string                 // 來源章節（e.g. "PM §1-1"）
}

interface GapItem {
  prdAcId: string              // e.g. "PM-AC-5"
  description: string          // e.g. "金額上限檢查"
  reason: string               // e.g. "需 PM 確認後端限額邏輯"
  acknowledgedBy: string       // "user"
}

interface PrdHistoryItem {
  version: string              // e.g. "v1.2"
  mapVersion: number           // 對應的 map 版本 e.g. 1
  changedAt: string            // ISO 8601
  summary: string              // 變更摘要
}
```

---

<a id="sec-errors"></a>
## 常見錯誤（禁止）

### 禁止：routes 用 Array

```javascript
//  錯誤 — 會導致 engine.js 查找失敗
"routes": [
  { "routeId": "s1", "name": "登入", "pages": ["login"] }
]
```

### 正確：routes 用 Object

```javascript
//  正確
"routes": {
  "s1": { "name": "登入", "group": "公開頁面", "pages": ["login"] }
}
```

### 禁止：pages 用 Array

```javascript
//  錯誤
"pages": [
  { "pageId": "login", "label": "登入頁", "acs": [...] }
]
```

### 正確：pages 用 Object

```javascript
//  正確
"pages": {
  "login": { "label": "登入頁", "frameRef": "frame-login", "acs": [...] }
}
```

---

<a id="sec-derived"></a>
## 從 PrototypeMap 衍生的 JS 變數（G5 產出）

```javascript
// 衍生自 routes — 直接從 Object 鍵值提取
var SCENARIO_TITLES = { "s1": "登入與基礎授權", "s2": "全球總覽" };
var NAV_PATH        = { "s1": ["login"], "s2": ["l1-global", "l1-tw"] };

// 衍生自 pages — 轉為 Array 格式供 stepper 使用
var STEPS           = { "s1": [{ id: "login", label: "登入頁", dotIdx: 0 }] };
var STEPPER_LABELS  = { "s1": ["登入頁"], "s2": ["全球總覽首頁", "台灣總覽頁"] };

// DOM 映射 — panel id 固定為 "scenario-{routeId}"
var PANEL_MAP       = { "s1": "scenario-s1", "s2": "scenario-s2" };

// 衍生自 pages[].acs — 直接引用（節省 token）
var AC_DATA = {
  "s1": { "login": PROTOTYPE_MAP.pages["login"].acs }
};
```

---

<a id="sec-scenario"></a>
## SCENARIO_STATE 最小介面定義

G5 產出 HTML 時，AI 需建立 `SCENARIO_STATE` 物件，定義各場景的初始資料狀態。

```typescript
interface ScenarioStateItem {
  [sid: string]: {
    // PRD 推導的資料狀態（AI 依 PRD 擴充）
    // 每個欄位必須有具體值，禁止空字串或 null
    [dataKey: string]: string | number | boolean
  }
}

// 範例
var SCENARIO_STATE = {
  s1: { userRole: 'investor', isLoggedIn: false },
  s2: { region: 'global', month: '2025-06' },
};
```

> **重要**：`SCENARIO_STATE` 不可留空值或 undefined。若 PRD 未定義初始狀態，AI 必須從情境描述推導合理預設值，並在 G4 Gate Package 標示「以下初始值為 AI 推導」。

---

<a id="sec-routeid"></a>
## routeId 命名規則

- 格式：`s{N}`（s1, s2, s3...）
- 按 scenario 順序編號

<a id="sec-pageid"></a>
## pageId 命名規則

- 格式：語義化名稱（如 `login`、`l1-global`、`l2-overview`）
- 使用小寫 + kebab-case
- 不使用 `step-{N}` 格式（除非語義上合理）

<a id="sec-frameref"></a>
## frameRef 命名規則

- 格式：`frame-{描述性名稱}`（e.g. `frame-login`, `frame-l1`, `frame-l2`）
- 多個 page 共用同一 frame 時使用相同 frameRef

<a id="sec-panelmap"></a>
## PANEL_MAP 命名規則

- 格式：`scenario-{routeId}`（e.g. `scenario-s1`, `scenario-s2`）
- 必須與 HTML 中 `<div id="scenario-{routeId}">` 一致

---

<a id="sec-naming"></a>
## 檔案命名慣例

```
output/{project}/{prototype-name}/
├── index.html                        ← AI 填寫的 HTML（從 scaffold 更名）
├── assets/                           ← 靜態資源檔（從 templates 複製）
│   ├── engine.js
│   ├── shell-common.css
│   ├── shell-{type}.css
│   ├── component-library.css
│   └── print-report.css
└── data/                             ← 版本資料
    ├── prototype-map-v1.json         ← G4 凍結 JSON
    └── prototype-map-v2.json         ← PRD v2.x 對應（若有變更）
```

> 不刪除舊版本。所有歷史版本保留供差異比對和回溯。
