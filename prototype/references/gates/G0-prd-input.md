# G0：PRD Input

讀取使用者指定 PRD，保留功能、角色、資料來源與驗收條件的來源。若內容已在對話中，
把後續需要引用的內容落檔；不要求使用者為已提供的資訊重新填表。

- `Prototype Config.component_library` 或使用者指定路徑提供元件庫 HTML/CSS。
- `prototype_input` 只是預設 PRD 目錄；已知 PRD 路徑時不構成前置門檻。
- `prototype_sitemap` 若有，供 G2 比對現有拓樸。
- `{artifact_dir}/planning/prd-ac-master-list.md` 保存 AC ID、描述與來源章節，供覆蓋比對。
- Map meta 記錄 projectName、prdVersion、shellType；草稿存 planning，避免只依賴 context。

Shell 選 standard（Web）或 flow（窄螢幕／行動流程），依需求與現有專案選擇。
只詢問會實質改變產出的缺漏；可從已知內容恢復的文件或目錄，直接補齊。
