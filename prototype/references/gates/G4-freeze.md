# G4：Freeze

Freeze 是可重現的版本切點。先完成 map、需求對照與場景初始資料，再產生 bundle。

## 覆蓋與決策

比對 `planning/prd-ac-master-list.md` 與 map AC，把 PRD ID → map AC ID、缺口與原因存入
`planning/coverage.md`。`coverageRate` 是有映射的 PRD AC 數／PRD AC 總數，重複映射只計一次；
無 AC 時記明不適用，不能用 0/0 宣稱 100%。此語意映射目前由模型／reviewer 判斷，
map checker 只檢查百分比範圍，沒有驗證 PRD 完整性。

- 已覆蓋且符合既有授權：驗證後凍結並繼續。
- 缺口可在原 scope 補足：補受影響 pages／AC，再驗證。
- 需要接受缺口、變更 scope 或解決需求衝突：先準備具體決策，取得必要確認。
- 重試沒有進展時回報原因與選項；重試次數不代表同意接受缺口。

只有使用者實際接受的缺口才寫入 `meta.gaps` 的 acknowledgedBy。Coverage 100%、
frozenAt、acknowledgedBy 都不等於可驗證的人工批准。

## 版本產物

- `data/prototype-map-v{N}.json`：填 frozenAt；createdAt 保留建立時間，並記 prdVersion。
- `planning/scenario-state-v{N}.json`：每個 route 一個初始資料 object；可無資料 `{}`。
- `planning/coverage.md`：需求映射、推導與已決定的缺口。

執行 `bash <skill-dir>/scripts/validate-map.sh <map.json> --json`。有錯先修草稿；
通過後把這個版本提供 G5。Approval 若依 router／team 模式需要，依實際決定記錄，
不因 freeze 自動將 prototype stage 設為 approved。

## 需求或版本變動

更新受影響的需求映射、map 與 state，另存 v{N+1}，保留舊版本。已授權的明確變更
直接執行；未解的新決策才詢問。重新產生機械外殼並驗證，再測受影響互動。
Hash／內容比對只證明版本一致；本 skill 沒有宿主身分驗證或不可繞過的 approval store。
