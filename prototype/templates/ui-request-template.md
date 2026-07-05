# Prototype Tuning Request Template (UI)

複製以下格式後填寫：

```text
[Prototype Tuning Request]
範圍: frame(frame-login)
現況: 
目標: 
限制: 
驗收: 
目標檔案: /abs/path/to/index.html
```

## 範圍寫法

- `global`
- `frame(frame-id)`
- `scenario(route-id)`
- `scenario(route-id) page(page-id)`

## 範例

```text
[Prototype Tuning Request]
範圍: frame(frame-login)
現況: 登入卡片太寬，視覺重心偏下
目標: max-width 520px，水平置中
限制: 不改 global css，不改其他 frame
驗收: 僅 s1/login 變更；s2/s3/s4 不變
目標檔案: <prototype 輸出 HTML 路徑，依 manifest 解析；例：<project_root>/design/prototype/output/index.html>
```
