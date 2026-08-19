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
3. 執行 `AGENTS.md` 列出的完整 Verify chain，包含 profiles、artifact、work-item、plan、journey harness、machine gate、release convergence 與 bootstrap。
4. 新增根目錄文件時同步加入 README 文件連結。
5. Commit、tag、push 與 PR 依 repository guardrails 執行；未經明確授權不 push。

## 發版清單

先分清 tag 類型。`v<next>-rc.N` 是供 dev review 的 prerelease；`v<next>` 才是
final release。兩者共用同一棵「已 commit、無額外檔案」的候選樹，但只有 final
release 會宣告公開版本已發布。

### 所有 tag

1. Tag 訊息只列相對上一個公開版本的新差異；不可把上一版已存在的契約重列為新變更。
2. 先 commit 候選內容，再以 `git status --short` 確認工作樹為空；若同一工作目錄仍有
   未追蹤或不屬於候選的檔案，在乾淨 checkout 驗證該 commit，不以 dirty worktree
   的結果宣稱「evidence on this tree」。
3. 在精確候選 commit 上執行 `bash tests/verify.sh`；改過 skill source 時另跑
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
