# skill-commons

跨 Claude Code、Codex 與其他 agent 的共享工程 workflow skills；top-level
技能資料夾是唯一 source of truth。

## Hard Rules

- 每個任務先讀 `skill-router/SKILL.md`，再依 router 載入技能。
- 不直接編輯 `.claude/skills/`、`.codex/`、`.agents/`；它們由 generate fan-out。
- 新工作項產出遵循 [`ARTIFACTS.md`](ARTIFACTS.md)，集中在 `docs/work/<slug>/`。
- 外部 vendored 技能的本地補丁必須同步記錄於 [`SOURCES.md`](SOURCES.md)。

## Commands

- Generate: `DELIVERY_MODE=personal bash bootstrap/generate.sh`
- Verify: `bash tests/verify.sh`

`verify.sh` 是唯一 canonical runner：它從樹上**探索** suites（`tests/test_*.sh`
與 `tests/bootstrap/test_*.sh`）而非硬編清單，所以新增測試不會靜默不跑；python
分層也在同一入口。`tests/run-all.sh` 只是轉呼叫的相容 shim。
Maintainer 全量 fan-out：`PROFILE=all bash bootstrap/generate.sh`。

## Navigation

- Skill index: [`INDEX.md`](INDEX.md)
- Artifact contract: [`ARTIFACTS.md`](ARTIFACTS.md)
- 跨 repo 契約與檢查（含執行方式）：[`docs/cross-repo-contract.md`](docs/cross-repo-contract.md)
- Decisions: [`docs/skills-reorg/decisions.md`](docs/skills-reorg/decisions.md)
- Development status lives in `docs/STATUS.md` only in the private development repo
  and is intentionally excluded from public exports.
