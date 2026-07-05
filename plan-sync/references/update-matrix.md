# Update Matrix

## Drift Check Matrix

| 變更類型 | 更新 Implementation | 更新 Tasks | Append Note | Refresh Snapshot |
|---|---|---|---|---|
| 純補充說明，不影響做法 | 否 | 否 | 可選 | 可選 |
| 新決策，影響邏輯或驗證 | 是 | 是 | 必須 | 必須 |
| Scope change | 是 | 是 | 必須 | 必須 |
| 執行回饋只影響 task 狀態 | 否 | 是 | 必須 | 必須 |
| 執行結果推翻原設計 | 是 | 是 | 必須 | 必須 |
| 單純完成某個 task | 否 | 是 | 建議 | 必須 |

## When To Mark `needs_review`

以下情況建議將 task 標為 `needs_review`：

- `Intent` 改了
- `Logic` 改了
- `Validation` 改了
- `Impact Areas` 改了
- 同一個 `Key` 仍存在，但其主要內容 hash 已改變

## When To Mark `superseded`

- 對應的 `Ixx` 被刪除
- 該 section 被新的 section 取代，舊 task 已不應繼續執行

## Event Types

建議使用以下 note 類型：

- `create`
- `decision`
- `scope_change`
- `execution_feedback`
- `status_change`
- `risk`
