---
name: plan-sync
description: |
  實作前規劃控制器。Use when: (1) 開始實作前需要先產出可執行且可追溯的計劃, (2) 需要把完整規劃同步成任務清單, (3) 需要在多輪對話中持續追蹤需求漂移與決策變更, (4) 需要讓弱模型或新 session 能靠檔案恢復上下文。
  觸發關鍵字: plan-sync, plan sync, implementation, tasks, notes, drift check, 實作前規劃, 對齊意圖, 需求漂移
source_kind: original
stage: plan
output: <work_root>/<slug>/plan/{implementation,tasks,notes}.md
---

# Plan Sync

建立並維護三份規劃產物，讓人和模型都能對齊現在要做什麼、為什麼做、做到哪裡：

- `implementation.md`：當前有效版本的 source of truth
- `tasks.md`：由 implementation 派生出的可執行任務契約
- `notes.md`：外部記憶，包含短 snapshot 與 append-only event log

> **Announce at start:** 「我正在使用 plan-sync 來建立或維護 planning artifacts。」

輸出根目錄：`<work_root>/<slug>/plan/`，並更新工作項根目錄的 `meta.yml`，遵循 [`../ARTIFACTS.md`](../ARTIFACTS.md)。

---

## 與其他 planning skills 的分工

- 需要長期維護 `implementation/tasks/notes` 三件式規劃、跨多輪追蹤 drift → 本 skill
- 只需要一次性的技術規格與實作步驟，不需長期外部記憶 → `spec`
- 需求中途變更，需回補文件本身 → `prd-interview`（PRD）/ `spec`（Spec）/ `qa`（TC）

規劃完成後，交給 `subagent-driven-development`（多任務）或 `implement`（單一 story）執行。

---

## Iron Laws

1. `implementation.md` 只保留目前有效版本，不記歷史。
2. `tasks.md` 只能由 `implementation.md` 導出，不可獨立發散。
3. `notes.md` 承擔歷史與外部記憶；每次重要變更都必須留下痕跡。
4. 每次寫入順序固定：`implementation -> tasks -> note -> snapshot -> validate`
5. Snapshot 必須短，不可長成第二份 implementation。
6. 發現需求漂移時，先改 `implementation.md`，再同步其餘檔案。

---

## 目錄契約

```text
<work_root>/<slug>/plan/
├── implementation.md
├── tasks.md
├── notes.md
└── .plan.lock

<work_root>/<slug>/meta.yml
```

模板請看：

- `templates/implementation.md`
- `templates/tasks.md`
- `templates/notes.md`

實作邊界請看：

- `references/implementation-constraints.md`
- `references/update-matrix.md`

---

## 4 種模式

每次執行只選一種模式。

### `create`

適用：planning artifacts 尚不存在。

步驟：

1. 確認 `plan-name` 與目錄。
2. 建第一版 `implementation.md`。
3. 依 implementation sections 導出 `tasks.md`。
4. 建 `notes.md`，寫入第一版 snapshot 與第一條 event log。
5. 跑 consistency validation。

### `refresh`

適用：artifacts 已存在，但新資訊改變或補強了目前規劃。

步驟：

1. 先讀 `notes.md` 的 snapshot。
2. 再讀 `implementation.md`。
3. 判斷新資訊是否影響：
   - intent
   - scope
   - logic
   - validation
   - dependencies
4. 有影響時，更新 implementation，然後同步 tasks / note / snapshot。
5. 無影響時，只在這個資訊未來仍重要時 append note。

### `drift-check`

適用：重要對話、執行回饋、task 狀態轉換後，檢查規劃是否漂移。

事件觸發：

- `implementation.md` 被改動
- 任一 task 轉為 `done` / `blocked` / `needs_review` / `superseded`
- 使用者加入影響 scope / logic / validation 的新決策
- session 準備 handoff 或結束

詳細規則 → `references/update-matrix.md`

### `resume`

適用：新 session、弱模型接手、或上下文不足時。

讀取順序：

1. 先讀 `notes.md` 的 snapshot
2. 再讀 `implementation.md`
3. 最後只讀與目前目標有關的 `tasks.md` 段落

不要先一口氣讀完整個 event log。只有當目前狀態仍有歧義時，才回頭查 log。

---

## Lite 模式（單檔 plan.md）

適用：個人專案、快速迭代、不需跨多輪追蹤 drift 時。以單檔取代三件式：

```text
<work_root>/<slug>/plan/plan.md
```

規則：

1. 由 `templates/plan.md` 起稿；`plan.md` 內含 `## Plan`（intent / scope / 不做什麼）、`## Tasks` 與 `## Change Log`。
2. 每個 task 仍保留 `Txx` / `Intent` / `Expected Result` / `Verification` / `Status`（狀態沿用 tasks.md 的六種）——因此 lite plan 直接滿足 `subagent-driven-development` 的 plan 輸入契約（controller 可逐 task 提取完整文字派發 subagent）。
3. 不用 `.plan.lock` 或 snapshot；變更直接改 `plan.md`，並在檔尾 append 一行變更紀錄。交付前仍以 `validate_consistency.py` 驗證。
4. 需求開始漂移或要跨多 session 長期維護時，升級為三件式（用 `create` 模式，以 `plan.md` 內容起底）。
5. `meta.yml` 的 plan stage 指向 `plan/plan.md`；Lite 與三件式不可並存。

---

## Artifact Rules

### `implementation.md`

每個 implementation section 都必須有：

- `Ixx`
- `Key`
- `Intent`
- `Logic`
- `Impact Areas`
- `Validation`

穩定識別規則：

- 標題可改，`Key` 不應隨意改
- 語意大改、拆分、合併時，建立新的 `Ixx`
- 舊 `Ixx` 不重用

### `tasks.md`

每個 task 都必須有：

- `Txx`
- `Source IDs`
- `Source Fingerprints`
- `Intent`
- `Expected Result`
- `Execution Checklist`
- `Definition of Done`
- `Verification`
- `Status`

允許的狀態只有：

- `pending`
- `in_progress`
- `blocked`
- `done`
- `needs_review`
- `superseded`

### `notes.md`

只允許兩區：

1. `Current State Snapshot`
2. `Event Log`

Snapshot 限制：

- 固定欄位，不新增自訂小節
- 單行摘要，不寫歷史沿革
- 只保留當前執行仍受影響的資訊

Event Log 規則：

- append-only
- 每條只寫一句
- 必須包含：`note id` / `timestamp` / `type` / `impact ids` / `message`

---

## Script Responsibilities

這個 skill 內建的 scripts 只負責 deterministic 工作，不做語意判斷：

- `scripts/init_plan.py`
- `scripts/sync_tasks.py`
- `scripts/append_note.py`
- `scripts/refresh_snapshot.py`
- `scripts/validate_consistency.py`

使用方式範例（腳本路徑以實際找到的 plan-sync skill 目錄為基準解析，此處以 `<plan-sync-dir>` 代稱；`--root`/`--slug` 必須建立上方契約的 `plan/` 子目錄，`init_plan.py` 的 default root 是 `plans`，**不要**省略參數）：

```bash
WORK_ROOT="<manifest paths.work_root; default: docs/work>"
SLUG="<stable-work-item-slug>"
PLAN_DIR="$WORK_ROOT/$SLUG/plan"
python <plan-sync-dir>/scripts/init_plan.py --root "$WORK_ROOT/$SLUG" --name "artifact governance" --slug plan
python <plan-sync-dir>/scripts/sync_tasks.py --plan-dir "$PLAN_DIR" --write
python <plan-sync-dir>/scripts/append_note.py --plan-dir "$PLAN_DIR" --type decision --impact I02,T02 --message "將 Story ID 改為先自動抽取、失敗才系統配號。"
python <plan-sync-dir>/scripts/refresh_snapshot.py --plan-dir "$PLAN_DIR" --write
python <plan-sync-dir>/scripts/validate_consistency.py --plan-dir "$PLAN_DIR" # tracked 或 Lite
```

語意判斷責任仍在 workflow 本身，不在 scripts 內：

- 是否真的算 scope change
- 哪個決策需要回寫 implementation
- task 狀態是否該降級為 `needs_review`

這些判斷先由 AI 根據 `references/update-matrix.md` 做，再用 scripts 完成結構同步。

---

## Recommended Flow

### 建立第一版

1. 先用 `create` 產出第一版三份檔案
2. 自檢是否能回答：
   - 我們要做什麼？
   - 不做什麼？
   - 現在最優先的 task 是什麼？
   - 如果換模型接手，是否能靠檔案恢復？

### 中途收到新需求

1. 跑 `drift-check`
2. 若命中 scope / logic / validation change：
   - 先改 `implementation.md`
   - 再跑 `sync_tasks.py`
   - append note
   - refresh snapshot

### 新 session 接手

1. 跑 `resume`
2. 只讀 snapshot + 相關 sections/tasks
3. 確認目前 active intent 與 next action

---

## Machine handoff check：交接前必須全部通過

> `subagent-driven-development` 或 `implement` 不得在 consistency validation FAIL 的情況下開始動工。這是 machine gate，不等待人工核可。

- `implementation.md` 已反映最新有效 intent
- `tasks.md` 與 implementation sections 對齊
- `notes.md` 有最新 snapshot
- 最近一次重要變更已有 event log
- `validate_consistency.py` 通過（唯一客觀證據；其餘四項為人工核對）

任一項 FAIL → 先修正對應檔案、重跑 `validate_consistency.py`，不可帶著 FAIL 交接給 implement。

## Completion Checklist

此 skill 完成時，必須確認以上 machine handoff checks 全部通過。

---

## Final Response Template

```text
Planning artifacts updated.

Mode: {create|refresh|drift-check|resume}
Plan directory: <work_root>/<slug>/plan/

Updated:
- implementation.md
- tasks.md
- notes.md

Key change:
- {one-line summary}

Validation:
- consistency check {passed|failed}
```
