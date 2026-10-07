# G3：AC Extraction

為 page 編寫可以觀察的驗收條件，例如「提交後顯示確認頁」，保留穩定 AC ID 與來源。

```json
{"id":"AC-001","text":"提交後顯示確認頁","prd":"提交成功後顯示申請編號。","src":"PRD §3"}
```

`id`、`text` 必填。`prd` 若提供就保留可獨立閱讀的原文，不用「同上」縮寫；`src`
指向真正來源。不要把推導或新增的需求標成 PRD 原文。

成功路徑與需求提到的狀態都要對應；loading／empty／error 依實際資料與互動適用性加入。
純樣式細節無須另造業務 AC。用 PRD Master List 對照 map AC，將映射與缺口交 G4。
Schema checker 可驗證 ID／文字存在，但不判斷語意是否覆蓋需求。
