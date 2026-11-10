# Prototype Tuning

依使用者已給的頁面、frame、現況與目標定位修改；資訊足夠就直接做，不要求再填模板。
只有無法判斷目標檔案或變更範圍時才補問。單一 frame 的要求不擴展成全域 redesign。

- 畫面／互動：修改 `planning/frames.js` 對應 function，重新產生 bundle。Map 與衍生資料已凍結，
  frame 只讀取或先複製，步驟間的輸入寫進 `SCENARIO_STATE`（見 [G5](gates/G5-html-output.md)）。
- 初始資料：修改版本化 state 來源，再產生。
- Routes、AC、需求或 frame mapping：另存新 map 版本，同步需求對照，回 G4。
- 固定 engine／shell template：屬 skill/runtime 維護，不在一般原型微調中修改。

重新產生後執行 verify-freeze，測受影響互動。機械 shell 會重建；未涉及的 frame
來源不應改動。Frame JS 範圍目前依 diff review，沒有 AST 層級的強制修復器。

## JSON 欄位修復

`validate-map.sh --json` 回傳精確錯誤路徑。若只是既有 scalar 欄位型別／範圍修正，
保留 base，寫出 candidate，選取錯誤中要修的路徑。Base 是已提交的版本（例如 frozen map）
時要加上 `--base-rev <commit>:<path>`；path 相對 repository 根目錄，從該 repository 內執行：

```bash
python3 <skill-dir>/scripts/check-repair.py \
  --base <base.json> --candidate <candidate.json> \
  --base-sha256 <sha256-of-base-bytes> \
  --base-rev HEAD:<repo-path-of-base.json> \
  --allow /frames/frame-home/sections/0/span
```

Checkout 有換行轉換（例如 `core.autocrlf=true`）時，工作檔與 blob 不同，檢查會失敗。
先用 `git cat-file blob HEAD:<repo-path-of-base.json> > <base.json>` 取出 base，
再以這個檔案作為 `--base` 並計算 `--base-sha256`。

程式不修改檔案。通過時保證：

- 局部性（相對於傳入的 base）：只有指定且被 validator 指出的既有 scalar 欄位改變，
  candidate 重新驗證通過。容器重寫、加刪欄位、未選路徑改動、仍不合法的結果都拒絕，
  這些情況回到來源需求編修。
- Base 身分：base bytes 與 `--base-sha256` 相符。
- Base 來源：只有加上 `--base-rev` 才檢查，base bytes 須與該 commit 的 blob 完全相同。
  沒加時 base 由呼叫者提供，先在 base 改壞欄位再「修復」也會通過。
- 決策欄位：`/meta/frozenAt` 與 `/meta/gaps/<n>/acknowledgedBy` 一律拒絕；版本切點與
  使用者接受的缺口依 [G4](gates/G4-freeze.md) 的實際決定記錄。

通過不證明人授權或需求語意。Frozen map 即使只修一欄也另存新版本；
涉及新的需求決策時取得必要確認，既有明確授權內的修改直接繼續。
