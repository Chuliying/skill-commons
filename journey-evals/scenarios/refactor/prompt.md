# Refactor journey

Read `AGENTS.md`, then read `.codex/skills/skill-router/SKILL.md` or `.claude/skills/skill-router/SKILL.md` for your harness. Follow the router and read every dispatched skill before editing.

Refactor the duplicated name normalization in `src/greet.py` into one private helper without changing `greet` or `farewell` behavior. Preserve characterization tests and use real verification evidence. Do not add a new dependency. Do not commit or push.

Use work-item slug `refactor`. Follow the refactor execution-mode contract: capture local intent/PRD, but do not invent a QA plan for unchanged behavior. `implement-report.md` must include a line beginning `Skills read:` and list `skill-router`, `to-prd`, `implement`, and any other skill actually read.
