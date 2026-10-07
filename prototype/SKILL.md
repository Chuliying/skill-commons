---
name: prototype
description: 從 PRD 建立或微調可互動的灰階 lo-fi prototype，產出 HTML、assets 與版本化 JSON map。適用 wireframe／流程原型；正式產品元件開發依專案前端慣例處理。
source_kind: original
stage: design
output: <work_root>/<slug>/prototype/index.html
---

# Prototype

把需求變成可點擊、可對照驗收條件的灰階原型。JSON map 描述場景、頁面與 AC；
程式產生固定外殼和衍生資料，模型負責需求解讀與 frame 實作。

## 輸入與完成條件

讀使用者指定 PRD、相關元件庫，以及存在時的 `.agent/project-manifest.md`
`Prototype Config`。`component_library` 指向 HTML 或 CSS；`prototype_input`
提供預設 PRD 位置；`prototype_sitemap` 是可選的現有頁面拓樸。
使用者已給的路徑與 repo evidence 足夠時可直接開始，不為缺少 manifest 另加等待。
只有缺失會改變需求、來源或可用元件時才詢問。

成果放在 `<work_root>/<slug>/prototype/index.html`，資料與 assets 放在同一 bundle，
工作項根目錄的 `meta.yml` 記錄狀態，遵循 [ARTIFACTS](../ARTIFACTS.md)。完成產生、機械驗證、適用的瀏覽器操作
檢查，記錄實際證據與未解缺口。結構 PASS 不代表需求完整、互動正確或已獲人核可。

## 決策與授權

G0–G6 是產物依賴，不是每一步都要停等的批准流程。依既有需求和授權完成草稿、
產生、驗證與局部修正。需要人決定的是：未解的需求／來源衝突、接受未覆蓋的需求、
超出已授權範圍的變更，以及 router 所要求的 team 設計或發布批准。

G1 / G4 / G6 可作為 review 時點；使用者已明確指定 routes、scope 或修正方向時，
不重複請求相同批准。需要決策時先準備完整 [Gate Package](../GATE-PACKAGE.md)。
`frozenAt` 只表示版本切點，`approved` 只記錄已實際發生的決定；腳本不能證明批准者身分。
最終 click walkthrough 可作為使用者 review；單純要求產出可驗證草稿時，不強制先取得
walkthrough approval 才交付。未發生的核可不得寫成 `approved`。

## 依目前工作載入

已有中間產物時從受影響處繼續；不必重讀所有階段文件。

| 工作 | Reference |
|---|---|
| PRD 摘要、保留需求來源 | [G0](references/gates/G0-prd-input.md) |
| 場景與路由 | [G1](references/gates/G1-route-map.md) |
| 頁面、元件映射 | [G2](references/gates/G2-page-inventory.md) |
| 可觀察的驗收條件 | [G3](references/gates/G3-ac-extraction.md) |
| 覆蓋缺口、版本切點 | [G4](references/gates/G4-freeze.md) |
| JSON 介面 | [Map contract](references/prototype-map-schema.md) |
| 產出 bundle | [G5](references/gates/G5-html-output.md) |
| 結構與互動檢查 | [G6](references/gates/G6-verification.md) |
| 已有 prototype 的局部修改 | [Tuning](references/tuning.md) |

## 程式入口

`<skill-dir>` 從本檔位置解析。Python 3.10+，無額外套件。

- `bash <skill-dir>/scripts/validate-map.sh <map.json> [--json]`：欄位、版本、引用與範圍。
- `python3 <skill-dir>/scripts/prototype_bundle.py --map <map.json> --state <state.json> --frames <frames.js> --library <library.html-or-css> --output <artifact-dir>`：產生外殼、資料與固定 assets。
- `python3 <skill-dir>/scripts/verify-freeze.py --map <map.json> --html <artifact-dir>/index.html`：比對完整 shell/data 與固定模板。

修正目前失敗涉及的範圍後重驗；新的變更或失敗才擴大檢查。Frozen map 改動另存新版本。
JSON 欄位修復可用 [bounded repair checker](references/tuning.md#json-欄位修復)。

`frames.js` 仍是可執行 JavaScript，並非受限 UI 語言。固定模板比對不提供 sandbox、
網路／操作授權或 tenant 隔離；沿用宿主權限，在 synthetic data 上驗證原型互動。
