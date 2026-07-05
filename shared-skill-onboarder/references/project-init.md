---
name: shared-skill-onboarder-project-init
description: |
  新專案接入 shared skills 時的初始化流程。自動掃描路由結構產生 sitemap.json，
  設定 project-manifest.md，建立必要目錄與 gitignore 規則。
  觸發時機: 新專案首次使用 shared skills、或使用者提到 onboarding、初始化、sitemap 掃描。
  適用範圍: React / Next.js 專案。
stage: infra
---

# Project Onboarding

> 新專案接入 shared skills 的一次性初始化。

---

## When to Use

- 新專案首次使用 shared skills
- 使用者說「初始化」「onboarding」「掃描 sitemap」
- `project-manifest.md` 缺少 `prototype_sitemap` 或指向不存在的檔案

---

## 流程

```
S1 偵測框架 → S2 掃描路由 → S3 交叉比對 Menu → S4 產出 sitemap.json → S5 更新 Manifest
```

所有步驟自動執行，無人工確認點。完成後呈現摘要供使用者 review。

---

## S1: 偵測框架

依序檢查，命中即停：

| 優先序 | 條件 | 框架 |
|:------:|------|------|
| 1 | `app/` 目錄存在且含 `page.tsx` / `page.jsx` | Next.js App Router |
| 2 | `pages/` 目錄存在且含 `*.tsx` / `*.jsx`（排除 `_app`、`_document`） | Next.js Pages Router |
| 3 | `package.json` 含 `react-router` 依賴 | React Router |
| 4 | 以上皆無 | 回報無法自動偵測，請使用者指定 |

---

## S2: 掃描路由結構

### Next.js App Router

```
掃描 app/ 下所有 page.tsx / page.jsx
├─ 目錄路徑 → 路由路徑
├─ [...slug] → isDynamic: true, dynamicType: "catch-all"
├─ [param]  → isDynamic: true, dynamicType: "param"
├─ (group)  → 不產生 URL segment，標記 routeGroup
└─ layout.tsx 存在 → hasLayout: true
```

### Next.js Pages Router

```
掃描 pages/ 下所有 *.tsx / *.jsx
├─ 排除 _app, _document, _error, api/
├─ 檔名 → 路由路徑（index.tsx → /）
├─ [param].tsx → isDynamic: true
└─ [...slug].tsx → isDynamic: true, dynamicType: "catch-all"
```

### React Router

```
掃描 src/ 下含 createBrowserRouter / <Route / useRoutes 的檔案
├─ 提取 path 定義（正則匹配 path: "..." 或 path="..."）
├─ 巢狀結構 → 組成樹
└─ :param → isDynamic: true
```

---

## S3: 交叉比對 Menu / Navigation

掃描專案中的 menu 定義並與路由交叉比對：

1. **找 menu 來源檔案**（優先序）：
   - 檔名為 `getMenu.ts` / `menu.ts`（最常見慣例）
   - 含 `menuData` + 陣列字面量的檔案
   - 含 `navigation = [` 的檔案
   - 排除：type 定義、page consumers、test、API routes
2. **提取 tree 結構**：用 Node.js bracket-counting + `Function()` eval 解析 TS/JS 陣列字面量
3. **提取 id 列表**：grep `id: '...'` pattern（macOS 相容）
4. **從 tree 建立 id→label 對照表**：回填到 routes
5. **比對 S2 的路由**：
   -  精確命中靜態路由 → `inMenu: true` + 回填 label
   -  catch-all 路由覆蓋 → 新增 virtual route（`dynamicType: "resolved-by-catch-all"`）
   -  有路由無選單 → `inMenu: false`（auth 頁、工具頁等，正常）
   -  有選單無路由 → `orphanMenuEntry` warning

**已知限制**：
- menu 必須以靜態陣列字面量定義在原始碼中（從 API 動態取得的無法提取）
- id key 必須叫 `id`（用 `key` 或 `path` 的專案需手動調整）
- React Router 巢狀路由只能提取第一層 path

---

## S4: 產出 sitemap.json

寫入 `.agent/knowledge/sitemap.json`，格式：

```json
{
  "meta": {
    "framework": "nextjs-app-router",
    "scannedAt": "2026-04-10",
    "entryDir": "app/",
    "menuSource": "src/lib/server/getMenu.ts"
  },
  "routes": [
    {
      "path": "/acme/dashboard/sales/overview",
      "isDynamic": true,
      "hasLayout": true,
      "inMenu": true,
      "label": "銷售概覽"
    }
  ],
  "tree": [
    {
      "id": "acme/dashboard",
      "label": "分析服務",
      "children": []
    }
  ],
  "warnings": [
    { "type": "orphanMenuEntry", "id": "some/removed/page", "label": "已移除頁面" }
  ]
}
```

### Schema 契約（最小欄位）

**meta**（必填）：
- `framework`: string — 偵測到的框架
- `scannedAt`: string — ISO 日期
- `entryDir`: string — 掃描的根目錄

**routes[]**（扁平列表，必填）：
- `path`: string — URL 路徑
- `isDynamic`: boolean

**tree[]**（階層結構，合併 menu 後產出）：
- `id`: string
- `label`: string
- `children?`: 同結構陣列
- `href?`: string

---

## S5: 更新 Manifest

讀取 `project-manifest.md`，確保 `Prototype Config` 包含：

```markdown
- `prototype_sitemap`: `.agent/knowledge/sitemap.json`
```

若欄位已存在但指向不同路徑，提示使用者確認是否覆蓋。

---

## 自動化腳本

掃描邏輯的核心實作（S1~S4）：

```
scripts/scan-sitemap.sh <project-root>
```

- 輸入：專案根目錄
- 輸出：JSON 到 stdout（AI 接收後寫入 `.agent/knowledge/sitemap.json`）
- 摘要資訊輸出到 stderr
- **不修改任何檔案**，純讀取 + 分析
- 依賴：`jq`、`node`

S5（寫入 sitemap.json + 更新 manifest）由 AI 執行，不在腳本內。

---

## 完成摘要格式

```
=== Project Onboarding Complete ===
Framework: Next.js App Router
Routes scanned: 24
Menu entries matched: 20
Orphan menu entries: 0
Unmapped routes: 4 (auth pages, API routes)
Sitemap: .agent/knowledge/sitemap.json
Manifest: updated prototype_sitemap pointer
```
