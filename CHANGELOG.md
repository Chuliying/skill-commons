# Changelog

本檔依 Keep a Changelog 格式記錄使用者可感知的技能、契約與 Gate 變更。版本遵循 Semantic Versioning。

## [Unreleased]

## [0.13.1] - 2026-11-10

### Fixed

- `tests/test_project_status.sh` 的兩個 fixture 改以 `python3 -B` 執行測試。原本的寫法在 Linux 上會把測試產生的 `__pycache__` 一起 commit（已提交的快取依設計就是 scope violation），並且在同一秒內還原同樣大小的來源檔時沿用陳舊的 `.pyc`，造成 CI 失敗九項。產品行為沒有改變；受影響的只有測試本身。

### 更正

- v0.13.0 的 tag 訊息與公開快照 commit 訊息都寫「CI could not run for this candidate」。這對 dev repo 成立（Actions 被帳戶層級擋住），對公開 repo 不成立：推送 `bcf94fa` 觸發的 run 42733989322 確實執行並失敗。已推送的 tag 不移動，更正記於此。

## [0.13.0] - 2026-11-09

### Breaking changes

- Codex 副本移至 `.agents/skills/`。明確執行 onboard 時會驗證舊 ledger 與檔案，再移除舊副本。`.codex/config.toml` 與使用者自己的技能保留。有本地改動時請先移出檔案再重試。若 Git 追蹤舊副本，onboard 會提示提交其刪除。
- Claude Code 與 Codex 的技能副本改由 `.gitignore` 逐檔排除。初始化 submodule 後，`check.sh` 可依已提交的 manifest 與現有忽略規則補檔，只更新忽略中的副本與本地狀態。若 Git 仍追蹤副本，請用 onboard 或 `manage.sh doctor` 列出的 `git rm -r --cached` 指令。遷移時一併提交 submodule、`.gitignore` 與追蹤變更。隊友 pull 後須執行 `git submodule update --init`。見 `docs/skill-commons-submodule-bridge.md`。
- `approve` 不加 `--agent-reported` 時，只在互動終端機（`/dev/tty`）且沒有偵測到代理環境變數時執行，並要求輸入 `yes`；否則以 exit 2 拒絕，並印出給人執行的指令與 `--agent-reported --quote` 的指令。`approval.json` 升為 schema 2，新增 `confirmation`（`terminal`、`agent-reported`）與 `agent_env`；schema 1 的核准顯示為 `recorded before levels`。升級後寫入的核准需要每個 checkout 都更新 submodule 才能讀。`reaffirm` 改到核准過的段落時走相同的確認，`--evidence-only` 只改驗證證據。
- 產生到使用者 repo 的文字改為英文：`AGENTS.md` 指令卡、`CLAUDE.md` 引用說明、Cursor rule、guardrails 範本、`check.sh` 警告、PRD 範本本文。既有 repo 下次 onboard 時會換成英文，沒有中文指令卡的選項。
- `skill-router`、`implement`、`verification-before-completion`、`systematic-debugging`、`sync-work` 改為英文。router 的 flow 標題改為 `## Flow: Explore|Build|Fix|Release|Understand`，人工核可標籤改為 `Human gate: PRD approval` 等；`flows.json` 的 `router_heading`、`router_label` 同步。
- `verify.sh` 對無法辨識的參數回 exit 2；原本會忽略。`--skip-test` 的用法不變。
- `project-status` 的 JSON `schema_version` 由 2 升為 3，新增 `verification` 與 `verification_attention`。

- prototype map 的 `backStep`／`nextStep` 目標必須出現在包含該 page 的每個 route；
  跨 route 的引用改由 validator 拒絕，v1 與 v2 都適用。原本 frame 在缺少目標的 route
  用這個欄位換頁時，預覽區會空白。既有 frozen map 會在 `validate-map`、bundle 產生與
  `verify-freeze` 失敗，只重新產生 bundle 不能解決；依 G4 另存新 map 版本，把目標 page
  加進缺少它的 route、移除該欄位，或讓各 route 使用各自的 page。
- engine 的 `goTo` 找不到目標 frame 時丟出錯誤並保留目前畫面，不再無聲清空預覽。
- `runtime-data.js` 在 `frames.js` 載入前深度凍結 map 與衍生資料，全域名稱不能重新指定。
  Frame 直接改 AC 或 projection 時，sloppy mode 下改動無效，strict mode 與 `push` 等
  陣列方法會丟出 TypeError。`SCENARIO_STATE` 仍可寫。
- 固定模板 `engine.js` 與 `runtime-data.js` 有變動，既有 bundle 要用 `prototype_bundle.py`
  重新產生，`verify-freeze.py` 才會通過。
- `work-items check` 遇到本身含 `meta.yml` 的 work root 會以 exit 2 拒絕；原本回報
  `0 valid` 並通過。沒有任何工作項的 work root 照舊通過。

### Added

- 工作項目可在 `meta.yml` 選填 `allowed_paths`（T12）：`work-items.sh new` 記錄 `base_commit`（`start` 會更新），`verify.sh --work-item` 把範圍外的改動寫進 `verification.json`，`project-status` 讀取時重新計算並顯示為 attention（`--strict` 失敗）。排除已在預設分支上的 commit（在預設分支上工作時不排除，並註明）；base 不再是 HEAD 的祖先（rebase）時只檢查未提交改動；同一分支上有多個宣告 `allowed_paths` 的項目時只顯示、不給 attention；路徑以專案為準，專案可在 Git 頂層之下。工作根目錄與產生的代理目錄永遠允許；未提交的快取不算，已提交的快取一律列出。
- Quick Start 改為兩個指令：用 HTTPS 加入 submodule，再執行 `onboard.sh`。預設 manifest 包含 `optional`，新安裝即有 `to-prd`。
- `verify.sh --work-item <slug>` 在工作項目寫入 `verification.json`：結果與內容指紋（原始碼、測試與 manifest 檢查命令，含未 commit 內容）。只有測試實際執行且全部通過才是 pass。
- `project-status` 為每個工作項目回報 `verification`（current、covered、stale、failed、unknown、unbound、n/a），並列出 `verification_attention`；JSON `schema_version` 升為 3。`--strict` 在有待處理的驗證時回 3。只有一個進行中的項目（或指定進行中的 `--slug`）時，狀態仍為 attention，下一步仍指向該項目並附上待處理的驗證。
- `planctl check` 拒絕同一個觀察（外部證據，或命令沒有讀取的本機檔案）佐證不同任務的不同主張。階段報告（`implement-report.md`、`qa-report.md`、`gate-package.md`）每行記錄各自的執行，不受此限。
- 既有 manifest 缺少 `platforms` 或 `delivery_mode` 時，`onboard.sh` 與 `manage.sh` 一次列出所有缺少的欄位，並印出可直接貼上的行。
- `onboard.sh` 新建 manifest 時，從頂層目錄推導 `source_roots` 與 `tests_root` 寫入，並請使用者確認；既有 manifest 不修改，只印出建議的行。沒有這兩個欄位時，驗證指紋涵蓋整個 repo，改 README 也會讓完成的項目過期。
- 升級步驟最後加上 `project-status`：`doctor` 只檢查安裝，舊工作項目是否符合新版規則要由 `project-status` 檢查。
- `onboard.sh` 新建 manifest 時從專案檔案推導 `test_cmd`（`package.json` 的 test script、`go.mod`、`Cargo.toml`、pytest 設定、`test_*.py`、Makefile 的 `test`），第一次驗證不必先改 manifest；既有 manifest 只印出建議的行。
- 只有一份一般用途的 `AGENTS.md` 時不再推定為 Codex；`project-status.sh --ledger` 的文字與 Markdown 輸出列出每個 stage 的檔案。
- 新增工作狀態 `queued`（待辦）：`work-items.sh new <slug> --queued` 建立、`work-items.sh start <slug>` 開始；待辦不算 active，不觸發多個 active 的提示。
- 每個工作項目新增只增不改的 `activity.jsonl`：`new`、`start`、`complete`、`verify.sh --work-item`、`approve`、`reaffirm` 成功後各記一行（時間、事件、結果、偵測到的 AI 工具與 session；驗證另記開始時間）。子程序會繼承上層 agent 的變數，所以記錄所有偵測到的工具；`SKILL_COMMONS_SESSION=none` 不記 session id。
- `project-status.sh --ledger` 一項一列列出所有工作項目：stage、測試案例欄、最後一次驗證與核准、最後的活動與 session 數；`--json`、`--markdown` 另有兩種輸出。
- `complete` 拒絕非 active 的項目；對已完成的項目不再重寫。沒有 plan 的 active 項目驗證為 current 時，狀態不再是 unknown。
- 新增 `work-items.sh new <slug>`：產生通過檢查的 `meta.yml`、PRD 骨架（team-feature 為 team tier，其他為 core tier；未填寫前 `check-prd` 不通過）與實作報告，列出該模式完成前還需要的 stage；`--mode` 選執行模式，`--input` 記錄來源。
- 新增 `work-items.sh complete <slug> --na <理由>|--doc <文件>`：未完成的 stage 標為 done、`work_status: completed`、更新 `updated_at` 並記錄 `documentation_impact`；結果不通過檢查時拒絕並保留原檔。
- 自訂 `submodule_path` 時，`AGENTS.md`、`CLAUDE.md` 與 Cursor rule 的指令改用該路徑（原本固定寫 `.agent/skills/_shared`）。
- consumer directive 改為指令卡（開始工作、驗證、狀態、核准、完成），代理不必先讀 `ARTIFACTS.md` 與 PRD 範本；同時管理 `AGENTS.md` 時，`CLAUDE.md` 改為 `@AGENTS.md` 引用，不重複全文。Cursor 的入口預算依此調整並記錄理由。
- 新建 manifest 的平台依 repo 既有的 `.claude`、`.codex`、`.cursor` 判斷，都沒有時預設 Claude Code 與 Codex，不再預設 Cursor。既有 manifest 不變。
- `project-status` 對仍在進行中、但已有 `verification.json` 的項目也評估證據；項目停在 active 時，改了程式不再被忽略。
- 依 Fable 抽查修正：推導出的 `source_roots`／`tests_root` 必須涵蓋九成以上的程式檔才寫入 manifest，否則只印建議與涵蓋比例；驗收段落在同級或更高的標題才結束（小標題不再截斷），程式碼區塊裡的 ID 不算，`- [ ] AC-01` 這類 checkbox 算；標點改為斷字（`1.5` 與 `15` 不同）；預設綁定時，新增的驗收條件也會讓證據與核准過期；`approval.json` 的核准人不是 typed reference 時為 unknown；`approve` 在驗證不是 current 時提示；快取清單加入 `htmlcov`、`.hypothesis`、`coverage`、`test-results`、`playwright-report`、`target`、`.coverage.*`。指紋版本再升一級。
- `project-status` 的項目那一行：驗證或核准需要處理時，`state` 顯示 attention，不再在 `verify=stale` 旁邊顯示 `state=PASS`。
- 驗證指紋不再計入測試執行產生的快取（`__pycache__`、`.pytest_cache`、`node_modules` 等），repo 沒有忽略它們時也不會每跑一次測試就過期。指紋演算法版本升級，之前的證據需要重跑一次 `verify.sh`。
- 證據與核准綁定驗收條件：`verify.sh --work-item` 預設綁定 `prd.md`、`spec.md` 的 `AC-` 段落（`--covers` 可指定），改了段落證據就過期；`verification_evidence.py approve` 把核准綁在當下內容；`reaffirm` 記錄「意思沒變」的理由，只適用文件段落。`project-status` 新增 `approval` 與 `reaffirmed` 數。`planctl` 的證據行可加 `| covers: <file>#<ID>`，三段格式照舊。
- `spec` 缺少 `system_context` 時先從 repo 推導並標註來源，推導不足才詢問，不再直接停止。

- `work-items check --item <slug>` 只檢查單一工作項，`meta.yml` 不存在就失敗；
  prototype G6 的交接檢查改用這個形式。
- `check-repair.py --base-rev REV:PATH` 要求 base 與已提交的 blob 完全相同；checkout 有
  換行轉換時，用 `git cat-file blob REV:PATH` 取出的檔案當 base。

### Changed

- `check-repair.py` 拒絕修改 `/meta/frozenAt` 與 `/meta/gaps/*/acknowledgedBy` 這兩種決策欄位；
  `tuning.md` 改寫為程式實際保證的範圍。

## [0.12.0] - 2026-10-07

### Breaking changes

- `scripts/run-gate.sh` 不再 fan-out 給 consuming repo，並已移除；沒有任何技能引用它。
  既有安裝在下次 generate 時由 ownership ledger 自動移除受管副本；ledger 之前的舊版
  安裝在明確接管（`SKILL_COMMONS_ADOPT_LEGACY=1`）時一併移除。
- `sync-work` Scoped Save 改為先 stage 核可路徑、再跑 secret scan、最後 commit；
  scan 的 staged 檢查讀的是 index，舊順序下這一批尚未 stage，staged 檢查看不到它們。
- prototype map 驗證（`validate-map.sh`、`verify-freeze.py`、bundle）改由共用 JSON 契約
  執行，未標 `schemaVersion` 的 v1 map 也會檢查共通欄位：`meta.frozenAt`、`createdAt`、
  `prdHistory[].changedAt` 需含時區（例如結尾 `Z`），`pages[].frameRef` 必填，`acs[]`
  需有 `id` 與 `text`。v0.11.0 能通過但缺這些欄位的 map 會在 G4／G6 失敗；補上即可。
  驗證器改用 `python3`，不再需要 `jq`。

### Added

- `scripts/export-coauthors.sh`：公開 snapshot 匯出時收集自上次匯出以來的作者，
  產生 `Co-authored-by` trailers。
- prototype 改用 JSON 契約，新增 deterministic bundle、freeze 比對與 scalar repair
  checker（`prototype_contract.py`、`prototype_bundle.py`、`check-repair.py`）。

### Changed

- `to-prd` 移除 `disable-model-invocation`，router 派發 personal PRD 時模型可直接叫用；
  發布到 issue tracker 需使用者要求或同意。
- 專案層級術語與 ADR 統一放在 `domain-modeling` 維護的 `CONTEXT.md` 與 `docs/adr/`；
  ARTIFACTS 的 promotion 範例改為 `docs/adr/0012-...`，router 探索 flow 加入
  `grilling → domain-modeling`。
- `design-taste-frontend` 入口改為 70 行的本地精簡版（25,855 → 9,730 bytes），
  upstream 每一段與原始 preamble 原樣保存在 `references/`（hash 驗證不變）；
  衝突時以入口為準，不套用全域美學禁令、數字配額、dial 基準或額外核可。
  這是結構量測，不宣稱品質改善。
- `prototype` 入口精簡，gates 與設計細節改為按需讀取的 references。
- 依目前模型的使用建議調整技能文字：移除 `verification-before-completion` 的威脅語氣；
  統一 `systematic-debugging`、`implement` 的失敗門檻（3 次）與 Phase 4.5 命名；
  `spec`、`prd-interview` 的 `git fetch` 改為依 `sync-work` 取得同意；
  `spec` 不再要求虛構的時間估計；`subagent-driven-development` 的品質 gate 改讀
  manifest 宣告的檢查；縮窄過寬的觸發詞；移除「開頭先宣告」儀式。
- 測試套件依「抓得到哪個別處抓不到的失敗」整理：刪除測死碼、凍結的發版歷史、重複與
  恆真檢查，`tests/bootstrap/test_e2e.sh` 併入 `test_check.sh`。router byte 預算只由
  `test_context_budget` 擁有（6,747 bytes）。CI 的 source job timeout 15 → 25 分鐘。

### Fixed

- Fan-out 漏帶 `execution_modes.py`，consuming repo 的 `work_items.py`／`work-items.sh`
  一執行就 `ModuleNotFoundError`。
- `scan-secrets.sh` bootstrap 逾時後，忽略 TERM 的 runtime 行程會成為孤兒持續執行。
- `work-items check` 對含 lifecycle artifact 卻缺 `meta.yml` 的資料夾回報通過。
- `qa/scripts/run-qa.sh` 對打錯的 QA plan 路徑回報 PASSED；清單計數使用 ERE 不支援的
  `\d`。
- `verification-before-completion/scripts/verify.sh` 一項檢查都沒跑時仍印
  「Safe to commit」，現在印 `NO CHECKS EXECUTED`（exit code 維持 0）。
- `scripts/manifest-stack.sh` 讀取 onboarding 以反引號寫入的值（例如 `` `npm test` ``）時，
  會把值當成命令替換執行、再執行其輸出；`verify.sh`、`run-qa.sh`、`scan-secrets.sh`
  因此在依範本建立的 manifest 上失敗。現在剝除外圍一對反引號。
- `plan-sync`、`skill-creator` 的指令使用 stock macOS 沒有的 `python`；`markdown`、
  `shared-skill-onboarder` 寫死 submodule 掛載路徑。

## [0.11.0] - 2026-09-06

### Added

- `sync-work` 新增選用 [Pre-PR Brief](sync-work/references/pre-pr-brief.md)：
  push／PR 前沿用或補足專案摘要，在全專案 roadmap 標出本次 PR 章節，提供變更清單
  與可作答、計分、解析及重試的理解測驗。AI 主動詢問一次是否啟用，同意才執行，
  已選擇啟用或跳過時不重問。沿用既有驗證與
  交付授權，不新增 workflow owner、mode、必填 artifact 或額外測試 gate。
  附來源段落與 revision grounding、可改用的摘要範本、選用線上預覽指引與八個
  maintainer eval cases；網頁發布與存取驗證另依實際授權執行。
  來源衝突可依授權建立 issue，附修正建議與證據；跨 repo 契約文件也修正
  `lint-docs.sh` 會驗證連結的過度宣稱。
- 由 [`flows.json`](flows.json) 與 repository 機器來源生成的離線
  [`repo visual map`](docs/repo-visual.html)，包含產生器、可重現輸出與 drift gate。
- repo visual map 的公開部署 repo
  [`Chuliying/skill-commons-map`](https://github.com/Chuliying/skill-commons-map)
  與 [Vercel production 站](https://skill-commons-map.vercel.app)；部署頁沿用相同 model，
  source 出口指向公開 `skill-commons` repo。
- 本機 public gate 通過結果可依 public payload 與 toolchain digest 快取；只改
  export-ignored 內容時可重用，相同 payload／toolchain 以外一律 miss。目錄不可讀、
  digest 為空或 suite 失敗都不留下有效 verdict；CI 以
  `bash tests/verify.sh --release` 強制重跑，快取不作為發布證據。
- `tests/verify.sh` 現在把 source 與 clean-public 驗證分成可明確選擇的 scope；失敗的
  suite 會保留完整 stdout/stderr 記錄與可重跑命令，方便在不重跑整個 release gate 的
  情況下定位原因。

### Changed

- Frontend 技能入口由 87,327 縮為 25,855 bytes，移出的內容保留於七份按需讀取的
  references；新增 context meter。這是結構量測，不宣稱 token、品質或總時間改善。
- Maintainer source health 會檢查三套生成入口的一致性；project-status 優先顯示
  可執行的 canonical plan 下一步，並保留 attention 與 unknown 的差異。
- 整合既有 verification runtime 修正：timeout 驗證使用階段證據與獨立 watchdog，
  完整 stdout/stderr 在失敗時重播。local public verdict 快取移到獨立 public gate，
  不再由 reorganization suite 巢狀啟動另一輪完整驗證。

- repo map 首屏先說明適用對象、交付範圍與接手價值，並在安裝 lens 前比較
  personal 與 team-sprint；技能、契約、交付狀態及測試名單收進「工程細節」展開區。
- repo map 的五項待處理工作改用「要回答的問題、完成後可以回答、目前狀態」呈現，
  重播條件與評分術語保留在各項的「技術驗證方法」。
- repo map 將未完成的 evidence gaps 改列為五項待處理工作，每項附完成條件與目前狀態；
  已由確定性 suite 支援的契約一致性另列為完成基線，不再與待辦混在同一張表。
- repo map 的 profile 控制升為頁面級 sticky「以安裝內容檢視」lens；不在 bundle 的
  skill 以降低強調、虛線與「未安裝」第三態呈現，hero、flow 與技能目錄仍保留完整
  形狀，也仍可開啟細節。personal 因此會明確標示未安裝的 `spec` owner。
- delivery-mode lens 會依已安裝 producer 與 execution mode 的 required artifact 契約
  推導人工 Gate 適用性；personal 的 PRD／team 設計 Gate 以「不適用」第三態保留，
  發布 Gate 仍適用，team-sprint 則維持三個 Gate。capability pack 不被誤當完整執行模式。
- repo map 生成器可用 `render --source-base` 產生完整公開網站，沿用相同 model、CSS 與
  互動，並把細節出口改為 HTTPS 公開來源連結，而不是部署後失效的 checkout 相對路徑。
- repo map 細節改用 native modal dialog，並建立四級字體、雙主題對比與 reduced-motion
  邊界；頁首改放採用判斷，schema/build metadata 移到所屬契約區與頁尾。
- repo map 的「怎麼用」直接指出 `.agent/project-manifest.md`、`delivery_mode`、
  `capability_packs` 與 `bootstrap/onboard.sh`，讓安裝步驟可直接操作。
- 公開匯出邊界已由 `.gitattributes` 排除 `foundation/`、`orchestration/`、
  `productscope/` 與 22 個實際匯入它們的 Python 測試；私有原始碼、歷史與開發測試
  仍保留，v0.11.0 的公開 payload 不再包含上述私有模組；dev 來源仍保留。

### Fixed

- release boundary 測試以標準 `find` 列出 Python 測試，移除對額外安裝 `rg` 的依賴，
  讓乾淨的 GitHub runner 也能完整驗證 private test 排除名單。
- 本機 public 快取只重用 suite verdict；export、generate 與 Git init/add/commit
  每次都必須成功。setup 失敗會清除舊 verdict，避免 Git 環境故障仍因暖快取回報成功；
  新增三種 Git setup 故障的回歸檢查。正式 `--release` 仍強制完整重新驗證。
- repo map 在 640px 以下把安裝 lens 固定為單列橫向捲動，並替 section heading 保留
  sticky offset；待處理工作改為單欄卡片，避免標題被遮住及三欄內容逐字斷行。
- clean checkout 的 CI 會先生成受管 fan-out，再執行 canonical Verify chain。
- repo map 在 640px 以下會把 variant 名稱放在獨立列，後續流程序列從下一列開始；
  桌面維持名稱欄與流程欄的雙欄密度，避免名稱和第一個節點依字寬隨機併列。
- repo map hero 的意圖、設計、計畫、驗證與交付節點現在都連到真實 owner；移除測試的
  dead-handle 白名單，並要求每個 pointer-styled hero 節點都有可解析 handle。
- profile lens 不再以 `display:none` 移除所有 `[data-skill]` 命中項目，避免 flow 留下
  懸空箭頭或 hero 缺角。
- repo map 的測試 roster 依 `.gitattributes` `export-ignore` 邊界生成，使 private source
  與 public checkout 產生相同 model；drift gate 也會在測試寫入前先檢查 frozen page，
  不再以重新生成掩蓋 public export 漂移。

## [0.10.0] - 2026-08-20

> **升級前先讀本節的 Breaking changes。** 相對公開的 0.9.0，這個版本有兩項
> 新的 fail-closed 變更；觸發條件與處理方式如下。

### Breaking changes

- **2026-07-27 起更新並完成的 `work-item/v3` 必須宣告 `documentation_impact`。** 形式為
  `doc:<workspace 相對路徑>` 或 `n/a:<200 字以內理由>`；`doc:` 指向的檔案必須
  存在，且不得是 work root 底下任何一個 work item 的歷史檔（report、journal、plan）。
  規則是 forward-only；legacy metadata 仍維持 legacy schema，除非另行執行完整遷移。
- **每個 work-item stage 的 `skill` 必須對應樹上真實的技能目錄。** 未知 owner 在
  0.9.0 可通過基本 metadata 解析，0.10.0 起會 fail closed；升級時應改用現有技能名稱，
  或先移除／遷移無效 stage。

### Known issues

- dev/public payload 目前仍含 `foundation/`、`orchestration/` 與 `productscope/`，
  但三者都不在 retained-roots 產品白名單內。它們留在樹上是因為已核可契約的
  刪除／relocate 半部尚未另行授權；消費端不應建立相依。

### Added

- canonical-v2 Plan 新增 `- repo: <identifier>@<workspace 相對路徑>` participant source；
  後續 `local:` source 會在宣告的 participant 中解析，驗證證據仍留在 owning repo，
  `planctl status` 與 project status 會回報 participant identifier 與錯誤。
- [`docs/cross-repo-contract.md`](docs/cross-repo-contract.md)：說明機器契約
  （`protocol-registry.json`）、七項檢查各自保證什麼、以及執行方式。

### Changed

- 相對公開 v0.9.0，11 支技能的 `SKILL.md` 有變更（83 行新增、23 行刪除，淨增
  60 行）；不再宣稱未經量測的載入成本改善。

- 新增 canonical `tests/verify.sh`，從樹上動態探索既有 top-level 與 bootstrap suites，
  並納入新的 Python unit、integration、e2e 分層；`tests/run-all.sh` 降為相容 shim。
- 公開/私有測試邊界改為只宣告在 `.gitattributes`，不再由 runner 重算。
- secret 掃描的發現改為只輸出 `path:line` 與類別，不再輸出比對到的內容。
- 掃描結果結尾改為 scoped preflight 敘述，不再宣稱 comprehensive PASS。

### Fixed

- `bootstrap/onboard.sh --help` 不再把 `--help` 當成安裝目標並在其下寫入檔案。
- custom `submodule_path` 產生的 shim 會使用實際 mount，不再保留硬編的預設路徑。
- 未宣告 `source_roots` 的 repository 現在以整個 worktree（`.`）為保守 fallback；
  root-level 或非 `src/` layout 不再因虛構的缺失目錄而失敗，manifest/CLI 明確宣告的
  targets 仍逐一做存在性與 worktree boundary 驗證。
- secret assignment 會辨識直接傳給 `decrypt`、`unseal`、`unwrap` 的 quoted literal；
  placeholder suppression 與 `load_global_token()` 這類具名 accessor 的低誤報邊界維持不變。
- secret 偵測漏判：含 `os.environ` / `process.env` 的行整行被抑制，正好漏掉
  hard-coded fallback 這個最常見的實際洩漏形態；`# type: ignore` 也會使該行被抑制。
- secret 掃描把「用具名函式取得 secret」誤判為硬編值：`let token = load_global_token()?;`
  這類寫法中，長度 16 字元以上的函式名會被當成賦值過來的未引號 secret。誤判只在
  callee 名稱夠長時出現，因此同樣的寫法時報時不報，比穩定誤報更難建立對 gate 的信任。
  未引號值現在必須是完整 token 且後面不接 `(`。
- secret 掃描在 scope 為空時於 bash 3.2 崩潰（未保護的空陣列展開）。
- log 衛生規則把 `key` 當子字串比對，使每個 `sort_keys=True` 都產生警告。
- `implement`、`verification-before-completion`、`systematic-debugging` 的
  obra/superpowers MIT 標註被遺漏，已在 `SOURCES.md` 與 frontmatter 補回。
- 產物比對把 `__pycache__` 計入受管檔案集，使 source 與 fan-out 的一致性
  取決於執行順序。

## [0.9.0] - 2026-07-15

### Added

- Added a deterministic, read-only `project-status` entry that reports bootstrap,
  active work-item, canonical Plan, ambiguity, and next-action state without an LLM.

### Changed

- Reclassified model-run benchmark figures whose private replay artifacts were not
  preserved as unverified historical narrative rather than current release evidence.

### Fixed

- Secret preflight now detects hard-coded environment fallback values and retains
  staged `secret` and `token` name coverage while redacting candidate values.
- Bootstrap check now warns when a consuming shim lacks a managed stamp; project
  status also treats an active missing or unassessable Plan as `unknown` instead of PASS.
- Canonical Plan placeholder checks accept real generic and JSX syntax while still
  rejecting placeholder-shaped runnable values, and deterministic source gates use
  portable extended-regex alternation for test-file exclusions.
- QA, security, and final-verification runtime examples resolve from the actual
  skill location instead of assuming one fixed fan-out or submodule mount.

## [0.8.0] - 2026-07-14

### Added

- Added conditional Research for qualified implementation ambiguity and
  consent-gated Deep Wayfinding with bounded Destination, Fog, Frontier, resume,
  and durable-map contracts.
- Added Selected Seam records to Spec and QA so acceptance evidence names the
  closest stable repository boundary, its execution cost, and residual checks.
- Added vertical slices and expand-contract sequencing to Plan Sync feature
  decomposition, with explicit integration checkpoints for justified horizontal
  work.

### Changed

- Reduced the Router, Brainstorming, conditional discovery references, and Plan
  Sync context surfaces from 25,326 to 19,361 UTF-8 bytes while retaining their
  existing contract tests and progressive-loading boundaries.
- Reclassified the identity-bound 12-case GPT-5.5 low-reasoning classifier
  smoke as pre-T10 historical negative evidence. Its 0.8333 result is bound to
  the stored pre-compression payload, not the present payload; predicted loading
  and question counts remain informational.
- Retained the owner no-effectiveness-claim disposition without rerunning a paid
  smoke. The historical result remains below its frozen 0.9000 gate and remains
  FAIL; the release makes no runtime-loading, user-burden, cross-model accuracy,
  token-saving, or implementation-outcome claim.
- Made full documentation and public-payload scans follow Git and export-ignore
  boundaries, preventing a separately managed nested website from entering the
  root verification surface.
- Breaking: the v0.8.0 default core moves `brainstorming`, `grilling`, `to-prd`,
  `caveman-review`, and `shared-skill-onboarder` to the `optional` capability pack.
  Consuming repositories that need those skills must select `optional` before
  onboarding; the published v0.7.1 profile remains the legacy pin.
- Breaking: Plan loading is canonical-v2-only at `plan/plan.md`. Repositories that
  still use `implementation.md`, `tasks.md`, and `notes.md` must migrate first or
  remain pinned to v0.6.

### Removed

- Removed `finishing-a-development-branch` from source, profiles, generated ownership,
  and active metadata at the v0.8.0 boundary. `sync-work` is now the sole Git
  delivery interface; bootstrap migration still removes legacy generated copies.

## [0.7.1] - 2026-07-11

### Fixed

- Made secret-scan source-extension filtering consistent across GNU grep and
  BSD grep by applying include rules before named exclusions.
- Made bootstrap lifecycle mode and inode assertions validate portable BSD/GNU
  `stat` output before accepting it.

## [0.7.0] - 2026-07-11

### Added

- Declarative `protocol-registry.json` and conformance gate for execution modes,
  conditional artifacts, lifecycle evidence, profiles, and human decisions.
- Deterministic Repo Map `scan`/`status` with Git-private cache, Python AST
  imports, line-oriented JS/TS module-reference candidates, content freshness,
  linked-worktree/submodule fixtures, and explicit coverage states.
- Explicit `delivery_mode` plus composable `frontend`/`optional` capability
  packs, with platform-specific Claude Code/Codex/Cursor adapter boundaries.
- Strict local bootstrap management: read-only `doctor`, ownership-safe
  `update`, and all-target-preflighted `uninstall`.
- Journey grade evidence categories (`structural`, `behavioral`, `recorded`) and
  an executed harness-owned canonical secret preflight for the commit/release
  journey.

### Changed

- Replaced the always-on adapted `brainstorming` gate with project-specific
  bounded discovery: material-ambiguity qualification, Skip/Quick/Standard/Deep
  budgets, conditional artifacts, and an explicit true-agent evidence boundary.
- Breaking: Plan Sync accepts canonical-v2 `plan/plan.md` only. lite-v1 and the
  retired `implementation.md`/`tasks.md`/`notes.md` format must migrate, or the
  consuming repository must remain pinned to v0.6 until it can migrate.
- Breaking: `planctl.py check` and `planctl.py status` replace the removed
  `init_plan.py`, `sync_tasks.py`, `append_note.py`, and `refresh_snapshot.py`
  command surfaces. No compatibility wrappers are shipped; pin v0.6 until
  callers migrate.
- Breaking: consuming bootstrap selection is explicit. One `delivery_mode` is
  required; omitted selection no longer installs every workflow skill.
- Work-item lifecycle is now `work-item/v3`: `work_status` is separate from
  evidence-backed `delivery_status`; approval, PR, merge, and deployment states
  require their corresponding durable identifiers.
- Fan-out now records managed skill directories, shared fragments, and runtime
  helpers in a deterministic target-local ownership ledger. Existing
  pre-ledger roots with changed or retired generated content require one explicit
  `SKILL_COMMONS_ADOPT_LEGACY=1` migration run.
- `codebase-understanding` uses local Repo Map evidence by default.
  Understand-Anything is a pinned, explicit visualization-only reference and is
  not a freshness authority or release gate.
- Security language now distinguishes heuristic secret preflight, dependency
  audit, scoped auth review, and operation guards instead of one overall PASS.
- Plan Sync now states that it validates recorded evidence shape and references,
  but does not execute Verification or turn an authored PASS into behavioral
  proof.
- `design-taste-frontend` moved to the frontend pack for relevance;
  `reducing-entropy` moved to the optional pack, and the overlapping `ponytail`
  skill was removed from the active surface.
- README and platform documentation now position the project as a portable
  feature-delivery protocol/toolkit rather than a complete SDLC or equivalent
  host runtime.

### Fixed

- Bootstrap keeps project paths with spaces as one target, validates every
  target before mutation, rejects source/symlink/conflicting paths, and no
  longer clears entire Claude/Codex/generic skill roots or deletes foreign
  skills and helper files.
- Bootstrap now rejects selected adapter/submodule symlink escapes, ambiguous
  duplicate manifest keys, unowned Cursor rule collisions, and implicit
  platform shrink. Claude hook updates preserve foreign sibling hooks and use
  an explicit ownership marker.
- Bootstrap serializes project-wide mutation with a stable lock, keeps a losing
  contender from removing the winner's lock, compares doctor output to the
  exact desired ledger, and preflights every selected adapter before publication.
- Canonical Plan Sync local Sources, stable anchors, sibling metadata,
  dependencies, blockers, concurrency, and exact verification evidence now fail
  closed instead of allowing prose-only or unresolved completion.
- Completed work-item/v3 metadata now enforces required/absent mode artifacts
  and rejects stages left in active states; complex bug fixes may use an
  optional Plan.
- Journey grading no longer accepts bare review/security PASS prose, rewritten
  baseline history, malformed metadata, symlinked closeout artifacts, or a
  blocked PR attempt as delivery evidence.
- Journey secret grading pins the regular fixture manifest to the trusted
  baseline and ignores inherited manifest overrides that could narrow scope.
- Repo Map serializes full cache-generation publication and status reads with a
  no-follow Git-private lock, preventing mixed concurrent generations.
- Secret preflight constrains targets to the Git worktree, distinguishes tool
  errors from no findings, and redacts candidate values from output.

## [0.6.0] - 2026-07-09

### Added

- Deterministic PRD shape gate (`scripts/check-prd.py`) with a single canonical `prd-template.md` as the source of truth for PRD shape, enforced as both the producer postcondition (`to-prd`, `prd-interview`) and the `spec` consumer precondition; tier-aware (`--tier core|team`).
- Artifact contract documents a forward-only adoption stance: existing artifacts are grandfathered and a repository-wide gate sweep is opt-in.

### Changed

- `to-prd` no longer embeds its own PRD template; both PRD entry points reference the canonical `prd-template.md`, removing template drift.
- README leads with meaning (repeatable, reviewable, resumable) and condenses the design intent into three principle groups.

### Fixed

- Repository test suites now pass on the exported public payload: private-only
  documents are checked only in the private development repo and must be absent
  on the public surface. A payload self-test in `test_skills_reorg.sh` guards
  this end to end, including a hostile global-excludes commit simulation.
- Root `.gitignore` re-includes `.gitignore` files so repo and fixture ignore
  rules stay tracked when the public repository is created on a machine whose
  global excludes file ignores them.

## [0.5.0] - 2026-07-05

### Added

- Five repeatable fresh-agent journeys for personal feature、team feature、brownfield bug、refactor and commit+PR，with deterministic grading.
- Machine gates for QA AC traceability and frozen prototype output comparison.
- Gate Package convention and durable `awaiting-approval` / `approved` stage states.
- `humanizer` optional docs utility (experimental), adapted from `blader/humanizer`, for removing AI-sounding prose while preserving meaning and disclosure boundaries.

### Changed

- Breaking: `tdd` merged into `implement`; `grill-me` / `grill-with-docs` merged into `grilling`; `requesting-code-review` merged into `caveman-review`; `rollback` merged into branch finishing Recovery Mode.
- Router converged to five flows and three workflow human decisions: PRD approval、team design approval、release approval.
- Core profile reduced to 14 skills; heavy utilities moved to the optional profile; `skill-creator` no longer fans out to consuming repositories.
- Prototype keeps G1/G4/G6 human decisions while G2/G3 stay internal, G5 confirmation moves into G4, and G6 human work is limited to a click walkthrough.
- Public release docs now require a clean-history public `skill-commons` export
  instead of directly renaming the history-bearing development repo.

### Fixed

- Generated agent skill roots now include shared runtime helpers required by verify、QA、security and work-item scripts.

## [0.4.1] - 2026-07-04

### Fixed

- Fixture `.gitignore` files are explicitly published even when a maintainer has a global ignore rule for ignore files.

## [0.4.0] - 2026-07-04

### Added

- Manifest `has_ui`、`has_api`、`typed_contracts`、`has_e2e` capability flags，缺席時安全預設 false。
- Python CLI 與 TypeScript/Web fixture pipelines，覆蓋 verify、QA、deterministic gates、secret scan 與 onboarding scan。

### Changed

- Spec、QA、PRD、verification 與 security gates 只執行 capability 適用項，不適用時回報 N/A。
- Gate 與 secret scanner 從 manifest 讀 source roots、extensions、commands 與 package manager，不再假設單一語言。
- Spec/QA templates 改為 stack-neutral，Full onboarding 只要求 capability 對應的 API、type、UI 與 E2E 資產。

## [0.3.0] - 2026-07-04

### Added

- Work-item `list`、`stale` 與 schema/artifact-path `check` CLI。
- 正式 Lite plan template、validator coverage 與 archive retention contract。

### Changed

- Gate P1 現在拒絕未替換的模板 placeholder，並回報檔案與行號。
- Closeout promotion 以 `promoted-to:` 在原始 artifact 保留 provenance。

## [0.2.0] - 2026-07-04

### Changed

- Breaking：`dev-kickoff` 已更名為 `prd-interview`；trigger、profile 與 active 文件同步採用新名稱。
- PRD 訪談改為五階段流程；Sprint、外部搜尋與 UI 欄位依 manifest 與需求語意條件啟用。
- PRD 與 Spec 階段只檢查遠端 ahead/behind，不再自動改動工作樹。

## [0.1.0] - 2026-07-04

### Added

- Public CI、README design intent、profile onboarding 與文件治理規則。
- Personal micro-task direct path 與 fresh-repository bootstrap skeletons。
- Skill maturity lifecycle 與 provenance `source_kind` contract。

### Changed

- Implement inputs now follow explicit execution modes for team feature、personal feature、bug fix 與 refactor。
- External skill provenance now distinguishes original、adapted 與 vendored content。
