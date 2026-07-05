# Team feature journey

Read `AGENTS.md`, then read `.codex/skills/skill-router/SKILL.md` or `.claude/skills/skill-router/SKILL.md` for your harness. Follow the router and read every dispatched skill before editing.

Add an optional `prefix` argument to `src/greet.py:greet`. Default behavior remains `hello Codex`; `greet("Codex", prefix="welcome")` returns `welcome Codex`. The product requirement, PRD approval, and team design approval are granted if the default is backward compatible, the function remains CLI-only, and tests cover both paths. Manifest capabilities are authoritative: do not invent UI, API, typed-contract, or E2E assets.

Use work-item slug `team-feature`. Complete the formal local team artifact chain through QA validation, using real RED-GREEN-REFACTOR evidence. Do not commit or push. `implement-report.md` must include a line beginning `Skills read:` and list `skill-router` plus every dispatched skill actually read.
