# Implementation Constraints

這份 skill 的 scripts 只負責 deterministic 工作，避免把語意判斷硬塞進同步腳本。

## P0 Decisions

1. `sync_tasks.py` 不做 LLM 呼叫。
2. `Ixx` 與 `Txx` 都需要穩定識別，不能只靠標題文字。
3. `tasks.md` 只允許以下狀態：
   - `pending`
   - `in_progress`
   - `blocked`
   - `done`
   - `needs_review`
   - `superseded`
4. `notes.md` 的 snapshot 固定欄位、固定行數，不可長成第二份 implementation。

## 寫入順序

所有會改檔的流程都遵守：

1. acquire lock
2. read current files
3. update `implementation.md`（若需要）
4. sync `tasks.md`
5. append event log
6. refresh snapshot
7. run consistency validation
8. atomic replace
9. release lock

## Snapshot Contract

Snapshot 僅保留現在執行仍需要的資訊：

- `Active Intent`
- `Current Decisions`
- `Current Scope`
- `Open Risks`
- `Next Action`
- `Last Updated`

每欄位維持單行，列表內容以 `;` 串接，避免越寫越長。

## State Transition Guardrails

- source section 內容改動：task 至少轉 `needs_review`
- source section 消失：task 轉 `superseded`
- task 完成後若 implementation 再變：允許 `done -> needs_review`
- `superseded` 不自動恢復為 `done`

## Non-goals

這個 skill 不嘗試：

- 自動理解語意正確性
- 自動做產品決策
- 從任意自由格式 markdown 中推導正確結構

因此，template 與欄位命名必須固定。
