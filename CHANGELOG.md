# Changelog

本檔依 Keep a Changelog 格式記錄使用者可感知的技能、契約與 Gate 變更。版本遵循 Semantic Versioning。

## [Unreleased]

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
