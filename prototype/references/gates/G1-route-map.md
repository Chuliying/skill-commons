# G1：Route Map

從 PRD 與已宣告 sitemap 建立 `routes` object，並更新 planning 中的 map 草稿。
每個 route 的 `pages` 陣列記錄實際步驟順序；名稱是使用者看得懂的場景描述。

```json
{"s1":{"name":"建立申請","group":"後台：申請管理","pages":["application","confirmation"]}}
```

沿用既有 IDs；新 route 可用 s1、s2，page 用語意化名稱。Group 可選；`scope：name`
或 `scope:name` 由產生程式拆成導覽標籤。不需要模型另寫 NAV_HTML。

既有需求已決定流程時直接繼續 G2。來源衝突或替代流程會改變 scope 時，整理具體選項
供人決定；route 表本身不新增批准點。
