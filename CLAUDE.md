# skill-commons

跨 Claude Code、Codex 與其他 agent 的共享工程 workflow skills；top-level
技能資料夾是唯一 source of truth。

## Hard Rules

- 每個任務先讀 `skill-router/SKILL.md`，再依 router 載入技能。
- 不直接編輯 `.claude/skills/`、`.codex/`、`.agents/`；它們由 generate fan-out。
- 新工作項產出遵循 [`ARTIFACTS.md`](ARTIFACTS.md)，集中在 `docs/work/<slug>/`。
- 外部 vendored 技能的本地補丁必須同步記錄於 [`SOURCES.md`](SOURCES.md)。

## Commands

- Generate (maintainer full fan-out): `PROFILE=all bash bootstrap/generate.sh`
- Verify: `bash tests/run-all.sh`

## Navigation

- Skill index: [`INDEX.md`](INDEX.md)
- Decisions: [`docs/skills-reorg/decisions.md`](docs/skills-reorg/decisions.md)
- Development status lives in `docs/STATUS.md` only in the private development repo
  and is intentionally excluded from public exports.
