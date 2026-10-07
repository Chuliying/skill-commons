# G5：HTML Output

模型撰寫 frame 畫面與互動；產生程式負責導航、頁面容器、JSON 嵌入及固定 assets。

## 需要的輸入

- G4 map、對應版本的 scenario-state JSON、component mapping 與元件庫。
- `planning/frames.js`：定義 `var FRAME_REGISTRY = { 'frame-home': function(ctx) { ... } };`。
  每個 map frameRef 都需有 render function，回傳 HTML 字串。ctx 含 sid、stepId、
  backStep、nextStep 與該場景資料；互動可呼叫既有 engine 的 goTo／nextStep。
- 使用元件庫的 classes。以灰階呈現資訊；不要在 lo-fi 範圍內自動改成品牌視覺設計。

## 產生

```bash
python3 <skill-dir>/scripts/prototype_bundle.py \
  --map <artifact-dir>/data/prototype-map-v1.json \
  --state <artifact-dir>/planning/scenario-state-v1.json \
  --frames <artifact-dir>/planning/frames.js \
  --library <component-library.html-or-css> \
  --output <artifact-dir>
```

此程式依 map 選 standard／flow shell，從 library HTML 抽取 style（或直接使用 CSS），
複製固定模板。輸出會更新 index.html、已知 assets 與 data/scenario-state.json；
不刪除 map 歷史或其他檔案。Map 不合法時不寫入輸出。

`runtime-data.js` 從純 JSON 建立 SCENARIO_TITLES、NAV_PATH、STEPS、STEPPER_LABELS、
PANEL_MAP、AC_DATA；不要手寫這些衍生資料或修改產生的 shell。

`frames.js` 保留彈性，也保留任意 JavaScript 的風險。產生程式不執行、不證明其安全性；
在宿主允許的 synthetic-data 環境做 G6 行為檢查。缺少 frame function 或 JS 語法錯誤
要由實際載入檢查發現，不能把結構驗證當作 runtime 測試。
