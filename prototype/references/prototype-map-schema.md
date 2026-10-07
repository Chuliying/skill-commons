# PrototypeMap contract

JSON 是場景／頁面／AC 的中間表示。可執行契約在
[`prototype_contract.py`](../scripts/prototype_contract.py)，由 validate-map、bundle generator
與 freeze verifier 共用；本文件提供作者介面，不是第二份 validator。

## 版本與欄位

`meta.schemaVersion` 只接受整數 1、2；省略視為 legacy v1。新產物使用 2。
V2 拒絕下表以外的欄位；v1 保留額外欄位相容性，但仍驗證已知共通欄位。
這不是任意 UI AST：map 沒有封閉元件／action catalog，frame 行為另由 JavaScript 實作。

| Object | 欄位 |
|---|---|
| root | meta、routes、pages；frames 可選 |
| meta 必填 | projectName、prdVersion（非空字串）、shellType（standard／flow）、frozenAt（含時區 ISO timestamp） |
| meta 可選 | schemaVersion、subtitle（字串）、createdAt（含時區 timestamp）、coverageRate（0–100 數值）、gaps、backfillRound（非負整數）、frameSeedRef（字串）、prdHistory |
| routes[id] | name（非空字串）、pages（非空且不重複的 page ID 陣列）；group 可選 |
| pages[id] | label、frameRef（非空字串）、acs（陣列）；type、flowId、backStep、nextStep 可選 |
| acs[] | id、text（非空字串）；prd、src（非空字串）、isHint（布林）可選 |
| frames[id] | shell（非空字串）、sections（非空陣列） |
| sections[] | row（非負整數，同 frame 唯一）、label（非空字串）、span（整數 1–12）；count（正整數）、notes（字串）可選 |
| gaps[] | prdAcId、description、reason、acknowledgedBy（非空字串） |
| prdHistory[] | version、summary（非空字串）、mapVersion（正整數）、changedAt（含時區 timestamp） |

Route／page／frame IDs 使用 `[a-zA-Z0-9_-]+`，排除 JS 特殊 property 名。
Route ID 使用 s1 等命名，拒絕全數字 ID，避免 JavaScript object key 枚舉重排導覽。
每個 page 必須被 route 引用；frame catalog 存在時，frameRef 必須存在於其中。
AC ID 用於需求追蹤；同一需求可對應多個頁面。
重複 JSON key、非 JSON 數值、布林冒充整數皆拒絕。

V2 `type` 為 surface（省略時預設）或 flow-step。Flow-step 有非空 flowId，
同 flowId 的所有 pages 都在同一 route；surface 不帶 flowId。
backStep／nextStep 若提供則引用既有 page。Routes 的 insertion order 與各 route 的
pages 陣列決定導覽順序；不要為 canonicalization 排序 route keys。

## 最小 v2 範例

```json
{
  "meta": {
    "schemaVersion": 2,
    "projectName": "申請原型",
    "prdVersion": "v1",
    "shellType": "standard",
    "frozenAt": "2026-09-15T10:00:00+08:00"
  },
  "routes": {"s1": {"name": "申請", "pages": ["application"]}},
  "pages": {
    "application": {
      "label": "申請頁", "frameRef": "frame-application", "type": "surface",
      "acs": [{"id": "AC-001", "text": "顯示可填寫的申請表"}]
    }
  }
}
```

## 場景狀態與衍生資料

Scenario-state JSON 的 keys 必須等於 routes keys；每個值為 object，欄位值使用
具體 string／number／boolean。無場景資料可使用 `{}`，不為滿足檢查虛構業務資料。
推導的初始資料要在需求對照中揭露。

```json
{"s1": {"isLoggedIn": false}}
```

產生程式把 map 與 state 安全嵌入 application/json script；固定 runtime-data.js
建立 SCENARIO_TITLES、NAV_PATH、STEPS、STEPPER_LABELS、PANEL_MAP、AC_DATA。
AC_DATA 直接引用 map pages 的 acs。模型只編寫 FRAME_REGISTRY，不重寫這些 projection。

## 驗證邊界與遷移

- Coverage 只做數值範圍檢查；PRD → AC 語意映射仍在 G4 的 coverage.md。
- Frozen JSON 只記版本；acknowledgedBy／frozenAt 不是身分或批准證據。
- Frames.js、component-library CSS 是可變輸入；固定模板完整性不證明這些輸入安全或正確。
- 舊的手寫 shell／DATA_JS 需先保留原來源，再抽出 frames.js 與 state，使用 G5 產生程式。
  只遷移當前正在維護的 bundle，不掃描改寫歷史原型。

```text
<artifact-dir>/
  index.html
  assets/engine.js、runtime-data.js、frames.js、shell-*.css、component-library.css、print-report.css
  data/prototype-map-vN.json、scenario-state.json
  planning/frames.js、scenario-state-vN.json、prd-ac-master-list.md、component-mapping.md、coverage.md
```
