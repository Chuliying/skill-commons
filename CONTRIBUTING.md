# Contributing to skill-commons

本文件給 skill-commons 維護者使用，定義技能從提案、成熟、修改到淘汰的固定軌道。Top-level 技能資料夾是唯一 source of truth；生成目錄不得直接編輯。

## 新增門檻

每個新技能提案必須回答：

- 服務 README 的哪一個公開 contract 或已觀察使用情境。
- 與現有技能的能力差異，避免同一能力出現多個包裝入口。
- 主要操作者是工程角色或非工程角色。
- 哪些風險需要人工判斷，哪些可由現有 machine gate 驗證。
- 為何新增技能比擴充既有技能更合適。

## 成熟度標記

Frontmatter 的 `maturity` 只有 `experimental` 或 `stable`。既有技能缺少欄位時視為 `stable`，維持向後相容。

Experimental 技能不進 `profiles/core`，不承諾輸入輸出契約穩定，且 CHANGELOG 必須標示實驗性。升為 stable 前，對應 journey eval 必須有可重複的 PASS 證據。

## 新增檢查表

新增或收錄技能時使用 [skill-creator/references/new-skill-checklist.md](skill-creator/references/new-skill-checklist.md)。最低要求包含：

- Frontmatter 的 name、description、stage、output、maturity、source_kind 與必要 provenance。
- 符合 STYLE.md。
- 同步 INDEX、profiles 與 README 速查表。
- 有 artifact 產出的技能接上 ARTIFACTS 契約。
- `bootstrap/generate.sh` 與 `AGENTS.md` 的完整 Verify chain 全部通過。

## 修改門檻

輸入、輸出、handoff 或 Gate 契約變更屬 breaking change，必須更新 CHANGELOG 並依 semver 升版。只調整不影響行為的文字不算 breaking change。

外部技能依 `source_kind` 處理：vendored 內容保留 upstream，必要本地 patch 記入 SOURCES；adapted 技能更新前以 pinned commit 做 diff，保留本地契約。

## 淘汰路徑

技能先在 description 標記 `deprecated` 一個 minor 版本，並在 CHANGELOG 說明替代入口。下一個允許移除的版本才移到 `_archive/`，同步更新 INDEX、profiles、router 與 tests。舊名稱可保留一個 minor 的 migration alias。

## 健檢節奏

每次 `npx skills update` 後，或至少每季一次，檢查觸發詞衝突、能力重疊、SKILL.md 行數與 STYLE 違規。結果落在 `docs/skills-reorg/`，附日期、檢查範圍與處置。

## 開發與驗證

1. 先改 top-level source。
2. 執行 `PROFILE=all bash bootstrap/generate.sh`。
3. 小修改先跑受影響的 suite（例如 `python3 -m unittest tests.py.integration.test_verify_contract`）。較完整的本地檢查可用 `bash tests/verify.sh --scope source`；確認公開 payload 用 `bash tests/verify-public.sh`。無參數的 `bash tests/verify.sh` 與舊 `tests/run-all.sh` 執行完整 source 與 public 檢查，本機 public 結果可依相同內容／toolchain 重用。正式 release 用 `bash tests/verify.sh --release`，強制獨立執行 source 與 fresh clean-public 兩邊。
4. 整合多個 shared contract 的變更，或準備 merge／release 時，再執行 `AGENTS.md` 列出的完整 Verify chain，包含 profiles、artifact、work-item、plan、journey harness、machine gate、release convergence 與 bootstrap。一般編輯迭代以受影響的 focused suite 為準；同一版本已通過的完整檢查，只有後續變更、失敗或未解疑慮才需要重跑。
5. 新增根目錄文件時同步加入 README 文件連結。
6. Commit、tag、push 與 PR 依 repository guardrails 執行；未經明確授權不 push。

每筆 runner failure 會在系統 temporary 目錄留下獨立 run log，保留 stdout、stderr、完整失敗輸出 與 per-entry retry command；成功 run 會清理該目錄。CI 的 source 與 public jobs 都從 fresh checkout 執行，public job 會重新 export、generate 並建立 temporary commit，不讀取本地 verdict cache。

`sync-work` 在準備 push 或建立 PR 前會主動詢問一次，是否啟用
[Pre-PR Brief](sync-work/references/pre-pr-brief.md) 的「專案摘要＋理解測驗」。
同意才執行；已選擇啟用或跳過時不重問，未回答不視為同意，也不新增交付 gate。
也可直接要求：

```text
用 sync-work，在 push／PR 前先給我變更摘要清單、visual roadmap，
加上可作答、計分、逐題解析與重試的理解測驗。
```

Roadmap 先呈現專案全貌，再標出本次 PR 對應的章節。優先沿用 README、既有專案
摘要與 roadmap；缺少足夠的專案摘要時，才依 repository 文件慣例補上精簡、有來源
依據的版本。PR 章節說明本次變更的原因、影響、證據與實際交付狀態，連回專案摘要；
避免每個 PR 重建整份專案文件或把未知方向寫成已承諾里程碑。

理解測驗使用有來源的情境題，檢查專案、改動與證據限制。網頁提供作答與送出介面，
聊天則先收答案再評分；不預選、不把空白算答對，區分首次作答與看過解析後的重試。
分數只描述受測觀念，不代表已全面理解或同意 Git 交付。只要求摘要時可不含測驗。

需要來源追溯或線上預覽時，按需讀取
[Grounded Overview](sync-work/references/grounded-overview.md)，沿用
[摘要範本](sync-work/assets/project-brief-template.md)。關鍵敘述對應來源段落與
revision；dirty 內容記錄實際 hash。網頁由選定來源產生，發布範圍與存取對象須符合
既有授權。維護此 flow 時可用 [eval cases](sync-work/references/pre-pr-brief-evals.md)
檢查來源衝突、缺件、私有預覽與過期證據；一般 PR 不因此新增模型評測。

此 flow 沿用同一候選版本的驗證證據與 Gate Package，按需載入，不新增 mode、
必填 artifact 或測試 gate，也不需要加裝 optional capability pack。理解確認與 Git
交付授權分開處理；既有授權持續有效，會影響正確性、範圍或交付安全的未決答案才
阻擋相依動作。一般補充說明問題不額外阻擋已授權的交付。

## 發版清單

先分清 tag 類型。`v<next>-rc.N` 是供 dev review 的 prerelease；`v<next>` 才是
final release。兩者共用同一棵「已 commit、無額外檔案」的候選樹，但只有 final
release 會宣告公開版本已發布。

### 所有 tag

1. Tag 訊息只列相對上一個公開版本的新差異；不可把上一版已存在的契約重列為新變更。
2. 先 commit 候選內容，再以 `git status --short` 確認工作樹為空；若同一工作目錄仍有
   未追蹤或不屬於候選的檔案，在乾淨 checkout 驗證該 commit，不以 dirty worktree
   的結果宣稱「evidence on this tree」。
3. 在精確候選 commit 上執行 `bash tests/verify.sh --release`；改過 skill source 時另跑
   `PROFILE=all bash bootstrap/generate.sh`，並確認 regenerate 後仍無 diff。
4. Annotated tag 必須指向剛驗證的 commit。已推送的 prerelease tag 不移動；修正後使用
   下一個 `-rc.N`。
5. 只推 tag 時使用 `git push origin refs/tags/<tag>`，不要連帶推 branch。未經明確授權
   不 push，公開 repo 另行取得發布授權。

### Prerelease

1. 若 RC 只存在 dev origin，`CHANGELOG.md` 保留 `## [Unreleased]`，README 與安裝文件
   繼續 pin 最新公開 final release；tag 訊息明確說明這兩點。
2. RC 不得被 README 或 CHANGELOG 描述成已發布版本。

### Final release

1. `CHANGELOG.md` 的 `## [Unreleased]` 改為 `## [<版本>] - <日期>`，並確認
   Breaking changes 只涵蓋相對上一個公開版本的新 fail-closed 變更。
2. 版本 pin 以搜尋結果為準，不維護容易失真的手算數量：
   `git grep -n '<舊版本>' -- README.md README.en.md bootstrap/README.md docs/`。
   更新所有安裝命令、相容性敘述與 upgrade guide，再重跑同一命令確認沒有遺漏。
3. 版號依 Semantic Versioning 與本專案 pre-1.0 慣例：0.x 的 breaking change 升 minor；
   向後相容的新能力升 minor；只有向後相容修正才升 patch。
4. 新增或移除頂層目錄時，確認它在 retained-roots 白名單內；不在白名單的路徑依契約
   屬於產品之外，不應在 README 被介紹為能力。
5. 完成版本切割後，重新走「所有 tag」的乾淨候選、fresh Verify、tag 與 push 步驟。
