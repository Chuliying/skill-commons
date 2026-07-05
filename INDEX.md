# Skill Index

Top-level skill folders are the source of truth. `(ext)` marks vendored skills tracked in [SOURCES.md](SOURCES.md); profile membership is defined only by [`profiles/`](profiles/).

## Profiles

| Layer | Count | Skills |
|---|:---:|---|
| core | 14 | router、探索/規劃、implement、review、驗證、安全、Git 與 onboarding 基礎 |
| team overlay | 5 | `prd-interview` · `spec` · `qa` · `prototype` · `domain-modeling` |
| personal overlay | 2 | `design-taste-frontend` · `ponytail` |
| optional utilities | 4 | `markdown` · `codebase-understanding` · `subagent-driven-development` · `humanizer` |

`team-sprint` = 19、`personal` = 16。未指定 PROFILE 時 fan-out 25 個 workflow skills；`skill-creator` 保留 top-level 給維護者，不 fan-out 到 consuming repo。

## Pipeline

| Stage | Skills | Purpose |
|---|---|---|
| skill | `skill-router` · `skill-creator`（maintainer-only） | 任務分發、技能維護 |
| plan | `grilling` (ext) · `plan-sync` · `domain-modeling` (ext, team) | 壓測決策、外部記憶、domain 語言 |
| docs | `brainstorming` · `to-prd` (ext) · `prd-interview` (team) · `spec` (team) · `markdown` (optional) · `humanizer` (optional) | 意圖到技術契約、文件轉換、文字風格修訂 |
| design | `prototype` (team) · `design-taste-frontend` (ext, personal) | lo-fi 原型與前端設計 |
| implement | `implement` · `ponytail` (ext, personal) · `reducing-entropy` (ext) | RED-GREEN-REFACTOR 與範圍控制 |
| qa | `qa` (team) | 測試方案、traceability、驗收 |
| review | `caveman-review` (ext) | 精簡 review 與 fresh-context 派發 |

## Infrastructure

- Core: `systematic-debugging` · `verification-before-completion` · `sync-work` · `finishing-a-development-branch` · `security` · `shared-skill-onboarder`
- Optional: `codebase-understanding` · `subagent-driven-development`

## Five flows

```text
探索 → 建造 → 發布
        ↑
修錯 ──┘
理解（read-only / optional utility）
```

實際派發、Execution Mode 與三個人工判斷點見 [`skill-router/SKILL.md`](skill-router/SKILL.md)。

## Archived

`_archive/` 保留可回復歷史（private development repository only；public export 會排除）。本輪收斂：

- `tdd` → 併入 `implement`
- `grill-me`、`grill-with-docs` → 併入 `grilling` durable docs mode
- `requesting-code-review` → 併入 `caveman-review`
- `rollback` → 併入 `finishing-a-development-branch` Recovery Mode

更早期的合併與裁減決策見 [decisions.md](docs/skills-reorg/decisions.md)。
