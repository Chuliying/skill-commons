# Changelog

本檔依 Keep a Changelog 格式記錄使用者可感知的技能、契約與 Gate 變更。版本遵循 Semantic Versioning。

## [Unreleased]

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
