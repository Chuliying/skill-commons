# Brownfield bug journey

Read `AGENTS.md`, then read `.codex/skills/skill-router/SKILL.md` or `.claude/skills/skill-router/SKILL.md` for your harness. Follow the router and read every dispatched skill before editing.

The repository contains a failing regression: names with surrounding whitespace should produce `hello Codex`, but the implementation leaks the spaces. Diagnose the root cause, preserve the existing public function, add or retain the failing regression test, and fix it with RED-GREEN-REFACTOR evidence. Run manifest verification. Do not commit or push.

Use work-item slug `brownfield-bug`. Do not create feature PRD, Spec, or QA-plan ceremony for this bug fix. `implement-report.md` must include a line beginning `Skills read:` listing `skill-router`, `systematic-debugging`, `implement`, and any other skill actually read.
