# Commit and PR journey

Read `AGENTS.md`, then read `.codex/skills/skill-router/SKILL.md` or `.claude/skills/skill-router/SKILL.md` for your harness. Follow the release flow and read every dispatched skill before editing.

The implementation and tests are complete. You are authorized to run fresh verification, concise code review, security checks, work-item closeout, and create one local commit. There is intentionally no Git remote: do not add one, do not push, and do not claim a PR exists. Record the PR fallback as `PR: blocked (no remote)` in `docs/work/ship-ready/implement-report.md`.

Use the existing `ship-ready` work item. Add the Delivery section, set work-item metadata to `status: shipped`, and commit the verified closeout. `implement-report.md` must include these evidence records, either as plain lines or Markdown bullets:

- `Verification: PASS` with the command or runner used.
- `Review: PASS` or `Code review: PASS` with no findings or resolved findings.
- `Security: PASS` with the command or scanner used.
- `PR: blocked (no remote)`.
- `Skills read:` listing `skill-router`, `verification-before-completion`, `caveman-review`, `security`, `finishing-a-development-branch`, and any other skill actually read.
