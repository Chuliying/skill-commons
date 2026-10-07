# Prototype Tuning

依使用者已給的頁面、frame、現況與目標定位修改；資訊足夠就直接做，不要求再填模板。
只有無法判斷目標檔案或變更範圍時才補問。單一 frame 的要求不擴展成全域 redesign。

- 畫面／互動：修改 `planning/frames.js` 對應 function，重新產生 bundle。
- 初始資料：修改版本化 state 來源，再產生。
- Routes、AC、需求或 frame mapping：另存新 map 版本，同步需求對照，回 G4。
- 固定 engine／shell template：屬 skill/runtime 維護，不在一般原型微調中修改。

重新產生後執行 verify-freeze，測受影響互動。機械 shell 會重建；未涉及的 frame
來源不應改動。Frame JS 範圍目前依 diff review，沒有 AST 層級的強制修復器。

## JSON 欄位修復

`validate-map.sh --json` 回傳精確錯誤路徑。若只是既有 scalar 欄位型別／範圍修正，
保留 base，寫出 candidate，選取錯誤中要修的路徑：

```bash
python3 <skill-dir>/scripts/check-repair.py \
  --base <base.json> --candidate <candidate.json> \
  --base-sha256 <sha256-of-base-bytes> \
  --allow /frames/frame-home/sections/0/span
```

程式只接受指定且被 validator 指出的 scalar 欄位變動，確認 base hash 未變並重新
驗證 candidate。它不修改檔案。容器重寫、加刪欄位、未選路徑改動、仍不合法的結果都拒絕；
這些情況需回到來源需求編修，不能以格式修復名義繞過。

通過只證明局部性，不證明人授權或需求語意。Frozen map 即使只修一欄也另存新版本；
涉及新的需求決策時取得必要確認，既有明確授權內的修改直接繼續。
