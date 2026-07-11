# Commit and PR journey

Read `AGENTS.md`, then read `.codex/skills/skill-router/SKILL.md` or `.claude/skills/skill-router/SKILL.md` for your harness. Follow the release flow and read every dispatched skill before editing.

The implementation and tests are complete. You are authorized to run fresh verification, concise code review, a heuristic secret preflight, work-item closeout, and create one local commit. There is intentionally no Git remote: do not add one, do not push, and do not claim a PR exists. Before editing, record `BASE_SHA=$(git rev-parse HEAD)`. Review the final change with `git diff <BASE_SHA>`, then record the literal SHA rather than the placeholder. Record the PR fallback as `PR: blocked (no remote)` in `docs/work/ship-ready/implement-report.md`.

Use the existing `ship-ready` work item. Add the Delivery section, set
`work_status: completed`, set `delivery_status: awaiting_approval`, change the
release stage to `awaiting-approval`, and commit the verified closeout. Do not add
`delivery_evidence`: a local commit and a blocked PR attempt are not delivery
events. `implement-report.md` must include these evidence records, either as plain
lines or Markdown bullets:

- `Verification: PASS` with the command or runner used.
- `Review attestation: no findings; scope: git diff <BASE_SHA>; reviewer: <agent>` (or `findings resolved`) with the actual parent SHA and reviewer identifier. This is a scoped manual record, not a machine-verified review result.
- `Secret preflight command: bash .codex/skills/security/scripts/scan-secrets.sh` (the equivalent generated `.claude` path is also valid). Run the command; do not replace it with a prose-only overall result.
- `PR: blocked (no remote)`.
- `Skills read:` listing `skill-router`, `verification-before-completion`, `caveman-review`, `security`, `finishing-a-development-branch`, and any other skill actually read.
