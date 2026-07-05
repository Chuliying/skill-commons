# G6：Verification — machine compare + human click walkthrough

G6 先用 frozen map 做機械比對，再把互動體驗交給人判斷。人不手動核對 JSON、AC、frame、asset 或 CSS 路徑。

## Input

- `{artifact_dir}/index.html`
- `{artifact_dir}/assets/`
- `{artifact_dir}/data/prototype-map-v{N}.json`
- G4 Gate Package

## Machine gate

```bash
python3 <prototype-skill-dir>/scripts/verify-freeze.py \
  --map "{artifact_dir}/data/prototype-map-v{N}.json" \
  --html "{artifact_dir}/index.html"
```

Script 以 frozen JSON 為 source of truth，覆蓋原 18 項 checklist 的機械部分：

1. HTML 存在且可讀。
2. frozen map 是合法 JSON object。
3. `meta`、`routes`、`pages` 結構合法。
4. runtime engine asset 存在。
5. common shell CSS 存在。
6. frozen shell 對應 CSS 存在。
7. component library CSS 存在。
8. print CSS 存在。
9. HTML 載入 component library。
10. 每個 route 有 scenario panel。
11. route 只引用存在的 pages。
12. 每個 route/page 有 DOM container。
13. 每個 page 有可解析的 `frameRef`。
14. HTML 含所有 frozen frame references。
15. 每個 frozen AC ID 出現在 HTML data。
16. acknowledged gap ID 有對應標記。
17. asset 不是空檔。
18. routes、pages、AC 數量可由報告重算。

任一 FAIL 時修 HTML 或回到 G4 建新 frozen version；不得要求人忽略 machine failure。

## Human Gate：click walkthrough

Machine gate PASS 後，提供 [GATE-PACKAGE.md](../../../GATE-PACKAGE.md) 四段內容，請使用者做 click walkthrough，只判斷：

- 場景與步驟順序是否符合工作方式；
- 上一步、下一步、重新開始與主要互動是否可理解；
- loading / empty / error 等狀態是否讓人知道下一步；
- 文案、資訊層級與整體操作成本是否可接受。

使用者可選：approve、列出具體修改、或停止。核可後把 prototype stage 從 `awaiting-approval` 改為 `approved`。

## Definition of Done

1. `verify-freeze.py` fresh run exit 0，輸出 routes/pages/AC counts。
2. Machine report 已存入 prototype report 或 implement report。
3. 使用者完成 click walkthrough 並作出具體決定。
4. `meta.yml` 記錄 approval state；只有 conversation 文字不算完成。
