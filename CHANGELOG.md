# Changelog

本檔依 Keep a Changelog 格式記錄使用者可感知的技能、契約與 Gate 變更。版本遵循 Semantic Versioning。

## [Unreleased]

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
