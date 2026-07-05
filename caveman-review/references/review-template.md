# Code Review Handoff

Review the change for production risk. Return findings first. Keep comments terse unless the risk needs context.

## Scope

- Implemented: `{WHAT_WAS_IMPLEMENTED}`
- Requirement / plan: `{PLAN_OR_REQUIREMENTS}`
- Base: `{BASE_SHA}`
- Head: `{HEAD_SHA}`

```bash
git diff --stat {BASE_SHA}..{HEAD_SHA}
git diff {BASE_SHA}..{HEAD_SHA}
```

## Check

- Behavior matches the requirement.
- Important edge cases and recovery paths are covered.
- Tests prove the behavior rather than mocks only.
- Capability-specific contracts are respected: API, UI, typed contracts, E2E.
- Security, data loss, migrations, and compatibility risks are called out.
- No unrelated scope creep.

## Output Format

### Issues

#### Critical

Use for broken behavior, security exposure, data loss, migration breakage, or failed required evidence.

#### Important

Use for missing required behavior, fragile architecture, meaningful test gaps, or incomplete error handling.

#### Minor

Use for low-risk cleanup. Omit this section if empty.

For each issue:

```text
<file>:L<line>: <severity>: <problem>. <fix>.
```

### Open Questions

Only include questions that block a correct verdict.

### Assessment

Ready to merge: Yes / No / With fixes

Reason: one or two sentences.

## Rules

- Findings only; omit empty sections.
- Do not approve merge or request changes on behalf of the user.
- Do not comment on files outside the review scope.
- Verify severity against actual risk.
- If there are no issues, say `No findings.` and mention any test gap that remains.
