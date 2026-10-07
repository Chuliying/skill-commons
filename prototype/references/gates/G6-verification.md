# G6：Verification

## 機械檢查

```bash
python3 <skill-dir>/scripts/verify-freeze.py \
  --map <artifact-dir>/data/prototype-map-v1.json \
  --html <artifact-dir>/index.html
```

檢查 map 欄位／引用、純 JSON 與 frozen map 相等、完整 HTML 等於 deterministic shell、
固定 engine／runtime-data／shell CSS 與安裝模板逐位元相符、assets 與 state 位於 bundle 內。
JSON 欄位順序保留，route 的順序不由排序重寫。註解文字不能當作 DOM 或資料證據。

此入口適用產生程式輸出；舊的手寫 HTML 必須用相同 map／frame 來源重新產生，不會
默默視為合格。若只維護舊格式而未遷移，明確回報 freeze check 未通過。

FAIL 時修正來源再產生。Map 要變更則另存新版本；不要改 checker 來迎合輸出。

## 行為與體驗

在可用的瀏覽器檢查實際載入、console errors、每條 route 的主要步驟、前後導航與
本次變更涉及的互動；需要時檢查 AC 勾選／備註與匯出。工具缺席時揭露尚未驗證。
Frame JavaScript、畫面是否可見、操作是否正確，都不在 Python 結構 PASS 的保證範圍內。

需要人的體驗 review 時提供 click walkthrough：資訊層級、文案、流程理解與操作成本。
只有任務或 team 模式要求核可，才以實際決定更新 awaiting-approval／approved。
已授權的修改和機械修復直接完成，不為每次重跑新增 Gate。

報告分別記錄結構結果、行為結果、需求缺口與尚待人做的決定。

## 工作項交接

原型驗證完成可將 prototype stage 記為 `validated`；`work_status: completed` 仍須滿足
[Artifact contract](../../../ARTIFACTS.md) 中該 execution mode 的 required stages，否則維持 `active`。
用共用的 `python3 <skills-root>/scripts/work_items.py --work-root <work-root> check` 核對本工作項
metadata；`<skills-root>` 是本 skill 的父目錄。若共用 checker 未提供，揭露交接狀態尚未驗證。
