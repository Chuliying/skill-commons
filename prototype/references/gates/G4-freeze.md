# G4：Freeze  人工確認

> 合併 G1~G3 產物、執行 AC 覆蓋比對、凍結 PrototypeMap。

---

## 目錄

- [前置依賴](#sec-deps)
- [Pre-flight Checklist](#sec-preflight)
- [Input](#sec-input)
- [Output](#sec-output)
- [AC 覆蓋比對機制](#sec-coverage)
- [AC 覆蓋比對報告](#sec-report)
- [路徑 A：凍結（承認缺口）](#sec-path-a)
- [路徑 B：回補](#sec-path-b)
- [PRD 變更管理](#sec-change)
- [Definition of Done](#sec-dod)

---

<a id="sec-deps"></a>
## 前置依賴

G3 通過。

---

<a id="sec-preflight"></a>
## Pre-flight Checklist（進入此 Gate 前必須全部通過）

| # | 檢查項 | 檢查方式 | 失敗動作 |
|---|--------|---------|---------|
| PF-1 | G1~G3 累積 map 在 context 中 | 確認 `meta`、`routes{}`、`pages{}` + `acs[]` 都存在 | STOP: 回報遺失的區塊，請重新執行對應 Gate |
| PF-2 | PRD AC Master List 落檔可讀 | 讀取 `{artifact_dir}/planning/prd-ac-master-list.md` | STOP: 落檔遺失，請重新執行 G0 |
| PF-3 | output data 目錄存在或可建立 | `mkdir -p {artifact_dir}/data` | STOP: 無法建立目錄 |

> **Iron Rule**: 任一項 FAIL → 立即停止，向使用者列出失敗項目與建議修復步驟。禁止以「猜測」「跳過」「稍後補」方式繼續。

<a id="sec-input"></a>
## Input

| 項目 | 來源 | 必填 |
|------|------|:---:|
| G1~G3 累積的完整 map | 記憶體暫存 |  |
| PRD AC Master List | `{artifact_dir}/planning/prd-ac-master-list.md`（G0 落檔） |  |

<a id="sec-output"></a>
## Output

| 產出物 | 格式 | 存放位置 |
|--------|------|----------|
| `prototype-map-v{N}.json` | JSON 檔案 | `{artifact_dir}/data/` |
| AC 覆蓋比對報告（Gap Report） | Markdown 表格 | 顯示在對話中 |
| 凍結確認摘要 | Markdown | 顯示在對話中 |
| Frame strategy + SCENARIO_STATE | 凍結 JSON / Gate Package | 納入同一次 G4 確認 |

G4 是 HTML 產出前最後一次結構確認。凍結前一併列出每個 `frameRef` 的複用策略、出現位置與 `SCENARIO_STATE` 初始值；AI 推導值必須標示。使用者在同一份 Gate Package 核可，不在 G5 再新增確認點。

---

<a id="sec-coverage"></a>
## AC 覆蓋比對機制

### Step 1：萃取兩份清單

```
PRD Master List（G0 落檔）      PrototypeMap AC（G3 產出）
┌─────────────────────┐        ┌─────────────────────┐
│ PM-AC-1  儲值金頁面  │        │ 1-1-1  → src: PM §1-1│
│ PM-AC-2  顯示餘額    │        │ 1-1-2  → src: PM §1-1│
│ PM-AC-5  上限檢查    │        │ （缺）              │
└─────────────────────┘        └─────────────────────┘
```

### Step 2：產出 Gap Report

```markdown
<a id="sec-report"></a>
## AC 覆蓋比對報告

| PRD AC ID | PRD AC 描述 | Map AC ID | 狀態 | 說明 |
|-----------|------------|-----------|------|------|
| PM-AC-1 | 顯示儲值金頁面 | 1-1-1 |  已覆蓋 | |
| PM-AC-5 | 金額上限檢查 | — |  未覆蓋 | 無對應 AC |

### 覆蓋率：5 / 6（83.3%）
```

### Step 3：使用者決定

- **覆蓋率 = 100%** → 自動通過 → 凍結
- **覆蓋率 < 100%** → 呈現 Gap Report → 使用者選擇路徑

---

<a id="sec-path-a"></a>
## 路徑 A：凍結（承認缺口）

在 `meta` 中記錄缺口：

```json
{
  "coverageRate": 83.3,
  "gaps": [
    {
      "prdAcId": "PM-AC-5",
      "description": "金額上限檢查",
      "reason": "需 PM 確認後端限額邏輯",
      "acknowledgedBy": "user"
    }
  ]
}
```

---

<a id="sec-path-b"></a>
## 路徑 B：回補

1. 使用者從 Gap Report 選擇要回補的項目
2. AI 判斷歸屬哪個 page：
   - page 已存在 → 直接新增 AC 到 `acs[]`（僅回 G3）
   - 需要新 page → 先回 G2 新增 page，再進 G3 補 AC
3. 補完後**重新執行 G4 比對**
4. **回補最多 2 輪；第 3 輪強制走路徑 A，禁止無限迴圈**

回補範圍控制——不影響的 gate 不重跑：
- G1 routes → 不重跑（結構不變）
- G2 pages → 僅新增缺少的 page（若需要）
- G3 acs → 僅補指定 page 的 AC
- G4 coverage → 重新比對（必做）

---

<a id="sec-change"></a>
## PRD 變更管理

### 場景 1：G0~G3 期間 PRD 變更（未凍結）

影響最小。差異比對 → 從最早受影響 gate 向下瀑布重跑。

| 已完成 Gate | 差異判斷 | 動作 |
|------------|---------|------|
| G0 | PRD 摘要是否影響 meta？ | 更新 `meta` |
| G1 | 是否有新/刪 scenario？ | 是 → 更新 `routes{}`；否 → 不動 |
| G2 | 是否有新/刪 page？ | 是 → 更新 `pages{}`；否 → 不動 |
| G3 | AC 是否變更？ | 是 → 僅更新受影響 page 的 `acs[]` |

### 場景 2：G4 已凍結、G5 未完成

1. 執行 PRD Diff 分析 → 使用者確認
2. 根據影響範圍決定重入點（G1/G2/G3）
3. 凍結新版本 `prototype-map-v{N+1}.json` 至 `{artifact_dir}/data/`
4. 舊版本保留

### 場景 3：G5~G6 已完成

1. PRD Diff 分析 + HTML 影響評估
2. 使用者選擇策略：
   - **Patch**：只重新產出受影響 frame（影響 ≤ 3 frame）
   - **Rebuild**：從 G5 完整重新產出 HTML（影響大）
3. 無論哪種：更新 map → 凍結 v{N+1} → G5 → G6

### 版本追蹤

```json
{
  "prdVersion": "v1.3",
  "prdHistory": [
    {
      "version": "v1.2",
      "mapVersion": 1,
      "changedAt": "2026-03-15T10:00:00Z",
      "summary": "初始版本"
    }
  ]
}
```

---

<a id="sec-dod"></a>
## Definition of Done

1. `meta.frozenAt` 已設定為當前 ISO 8601 時戳
2. `meta.createdAt` 已設定
3. JSON 檔案已寫入 `{artifact_dir}/data/`
4. `validate-map.sh` 驗證通過（schema + 外鍵 + prd 無縮寫引用）
5. AC 覆蓋比對已執行：PRD Master List vs PrototypeMap acs
6. 覆蓋率 = 100% → 自動通過
7. 覆蓋率 < 100% → Gap Report 已呈現，使用者已選擇路徑 A 或 B
8. 若路徑 A：`meta.gaps[]` + `meta.coverageRate` 已記錄
9. 若路徑 B：已重新執行 G3（局部）→ G4 比對。回補最多 2 輪
10. 凍結摘要已呈現：routes 數 × pages 數 × AC 總數 × 覆蓋率
11. 使用者已確認 map、frame strategy 與 SCENARIO_STATE，並同意凍結
12. 凍結後 G5 只讀此版本，任何修改必須建新版本
