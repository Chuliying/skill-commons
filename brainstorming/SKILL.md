---
name: brainstorming
description: |
  需求探索與設計精煉。在開始寫 code 之前使用：透過對話問問題、探索替代方案，最終提出設計方案並取得使用者確認。
  觸發關鍵字: 需求討論, 設計探索, 我想要, 感覺要做, 不確定從哪裡開始, brainstorm, explore requirements
source: obra/superpowers@d884ae04edebef577e82ff7c4e143debd0bbec99
source_kind: adapted
stage: docs
output: <work_root>/<slug>/brainstorm.md
---

# Brainstorming — 需求探索與設計精煉

> 改編自 [obra/superpowers](https://github.com/obra/superpowers)，融入本框架工作流程

## Overview

**在動任何程式碼之前**，透過自然對話將模糊想法轉化為清晰的設計方案。

> **Announce at start:** 「我正在使用 brainstorming skill 來探索這個需求。」

<HARD-GATE>
在取得使用者確認設計方案之前，**禁止**：
- 寫任何程式碼
- 調用任何實作相關 skill（prd-interview 除外，它是下一步）
- scaffold 任何專案結構
</HARD-GATE>

## 分流與 Handoff

- 還沒有方案、想法仍模糊 → 用本 skill（brainstorming）發散探索。
- 已有計劃/設計、要壓測找漏洞 → 用 `grilling`，不要重跑 brainstorming。
- 本 skill 止於「設計方案確認」；確認後 handoff → `prd-interview`（訪談式 PRD）或 `to-prd`（快照式 PRD），同一場對話不重複訪談。

---

## ⚠️ Anti-Pattern：「這個需求太簡單，不需要設計」

**所有需求都要經歷此流程**，無論大小。
簡單的功能恰好是隱藏假設最容易造成返工的地方。
設計文件可以很短（幾句話），但**必須呈現並取得確認**。

---

## 📋 流程

### Step 1: 了解專案背景

1. 查看相關檔案、既有功能、最近的 commits
2. 確認這個需求屬於**新功能**還是**擴充既有功能**
3. 確認影響範圍（哪些頁面、哪些元件）

### Step 2: 一次問一個問題

- **一次只問一個問題**，不要一次丟多個問題
- 優先用**選擇題**（比開放式問題更容易回答）
- 聚焦在：目的、限制、成功標準
- 範例問題：
  - 「這個功能主要解決什麼痛點？」
  - 「使用者看到這個功能時，期望的互動是 A 還是 B？」
  - 「是否有效能或瀏覽器相容性的限制？」

### Step 3: 提出 2-3 個方案

- 列出各方案的優缺點（Trade-offs）
- 給出你的推薦選項與理由
- 範例格式：

```
方案 A（推薦）：[描述]
優點：簡單、符合現有架構
缺點：缺少 X 彈性

方案 B：[描述]
優點：更靈活
缺點：實作複雜度高
```

### Step 4: 分段呈現設計，取得確認

- 按複雜度調整說明長度
- **每個段落後問確認**，不要一次塞完
- 涵蓋：架構、元件、資料流、錯誤處理、測試
- 如有不清楚的地方，回頭補充釐清

### Gate B1: 設計收斂檢查（移交 prd-interview 前必須通過）

> 使用者說「好像可以」不算通過。每一項都要有明確的肯定回應。

| 檢核項目 | 通過標準 |
|---------|----------|
| **問題定義** | 能用一句話描述要解決的問題，且使用者確認描述正確 |
| **範圍邊界** | 「做什麼」和「不做什麼」都有明確說明，使用者確認範圍 |
| **技術可行** | 無未解決的架構疑慮或技術阻礙（已在 Step 4 討論並有結論） |
| **使用者確認** | 設計方案已取得使用者明確 OK（不是「應該可以」） |

Gate B1 未通過 → 回到 Step 2 繼續釐清，禁止進入 Step 5

---

### Step 5: 儲存設計文件

```
<work_root>/<slug>/brainstorm.md
<work_root>/<slug>/meta.yml
```

輸出格式遵循 [`../ARTIFACTS.md`](../ARTIFACTS.md)。是否 commit 由使用者或專案 Git workflow 決定。

### Step 6: 移交 prd-interview

設計確認後，呼叫 prd-interview 產出正式 PRD：

```
/prd-interview [根據設計文件的需求描述]
```

---

## 🔑 核心原則

| 原則 | 說明 |
|------|------|
| 一次一問 | 避免讓使用者迷失 |
| 選擇題優先 | 降低回答門檻 |
| YAGNI 嚴格執行 | 從所有設計中移除不必要的功能 |
| 探索替代方案 | 先提 2-3 個選項，再定案 |
| 漸進確認 | 分段呈現設計，逐步取得 OK |

---

## 🔖 Execution Checklist（必填輸出）

> Checklist 格式慣例見 [CHECKLIST-CONVENTION.md](../CHECKLIST-CONVENTION.md)。

```
📋 Skill: brainstorming
📅 執行時間: YYYY-MM-DD HH:MM
📁 產出檔案: <work_root>/<slug>/brainstorm.md

Steps:
✅ Step 1: 了解專案背景 - [PASS/SKIP]
   └─ 發現: [現有相關功能/元件]
✅ Step 2: 釐清問題 (問了幾輪) - [X 輪]
   └─ 關鍵發現: [最重要的需求釐清]
✅ Step 3: 提出 2-3 方案 - [完成]
   └─ 推薦: [方案名稱] 原因: [...]
✅ Step 4: 設計確認 - [完成]
   └─ 使用者確認: [YES]
🚦 Gate B1: 設計收斂檢查 - [PASS/FAIL]
   □ 問題定義: [PASS/FAIL]
   □ 範圍邊界: [PASS/FAIL]
   □ 技術可行: [PASS/FAIL]
   □ 使用者確認: [PASS/FAIL]
✅ Step 5: 設計文件儲存 - [PASS/SKIP]
   └─ 路徑: [<work_root>/<slug>/brainstorm.md]
✅ Step 6: 移交 prd-interview - [完成]

📝 備註: [任何特殊情況]
```

**未輸出 Checklist = 未完成 Skill**

---

## Related Skills

| 觸發 | Skill |
|------|-------|
| 設計完成後 → 產出正式 PRD | `prd-interview` |
| PRD 完成後 → 技術規格 | `spec` |
| 有技術規格後 → 建立 Plan | `plan-sync` |
