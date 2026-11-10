---
name: verification-before-completion
description: Use before claiming work is complete, fixed or passing, and before commits or PRs. Runs the manifest-driven verify script and checks handoff checklists; overrides superpowers:verification-before-completion.
source: obra/superpowers@d884ae04edebef577e82ff7c4e143debd0bbec99
source_kind: adapted
stage: infra
---

# Verification Before Completion

> **Same name as `superpowers:verification-before-completion`**: this workflow uses this version (aligned with this repo's verify flow and guardrails). If the plugin version also loads, this wins.

## Overview

A completion claim needs verification output actually run after this change. Stale or partial evidence makes users think work is done,
and rework costs far more than one more run.

## Available Script

`<skill-dir>` = this file's absolute dir; never assume a fixed fan-out or submodule mount.

```bash
# Run type-check + lint + tests at once; print a structured summary
bash <skill-dir>/scripts/verify.sh

# Skip tests (quick check)
bash <skill-dir>/scripts/verify.sh --skip-test
```

For a work item add `--work-item <slug>`: the script writes the result and a content fingerprint to `<work_root>/<slug>/verification.json` (manifest `source_roots`, `tests_root`; if unset, files outside the work item dir and agent-generated dirs, uncommitted content included). Each run also logs one line to the item's `activity.jsonl` (start/end time, result, AI tool and session the environment reports), shown by `project-status.sh --ledger`; a queued item needs `work-items.sh start` first. The fingerprint includes the manifest's check commands, so weakening the test command also makes the evidence stale. If these files change, `project-status` marks the item stale; when a newer item passes on the same scope with no fewer files, the old one becomes covered: "current checks pass on current content", not that the original checks still hold. Pass means tests actually ran and all passed. Never hand-write or edit this file.

Evidence also binds to acceptance criteria: by default every `AC-` section in the item's `prd.md`, `spec.md`; `--covers prd.md#AC-002` binds only named sections. If those sections change (whitespace or punctuation only does not count), evidence goes stale.

```bash
# Approval: hand this to the person to run in their terminal; run by an agent it is refused and prints the fallback
python3 <skill-dir>/../scripts/verification_evidence.py approve --work-item <slug>
# Section changed, meaning did not: give the reason; only for acceptance criteria and approval, not code or tests
python3 <skill-dir>/../scripts/verification_evidence.py reaffirm --work-item <slug> --ref prd.md#AC-002 --reason "<reason>"
```

> Use the script instead of running commands by hand for consistent output each time.
> It reads capability flags and stack commands from the consuming repo's `.agent/project-manifest.md`;
> with `typed_contracts: false`, type-check is N/A; no package manager is assumed.

## Core Rule

Verification not run after the last code change cannot back a pass claim.

## The Gate Function

```
Before claiming any status:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the FULL command (fresh, complete)
3. READ: Full output, check exit code, count failures
4. VERIFY: Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. Make the claim, citing the command and result
```

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

## Key Patterns

- **Regression test:** write → run (pass) → revert fix → run (must fail) → restore → run (pass).
  A test that never failed has not been shown to catch the bug.
- **Delegated work:** a subagent's "success" is a claim, not evidence; check the diff and rerun
  the relevant command yourself.
- **Requirements:** re-read the plan or PRD and check each item; passing tests do not show
  that every requirement was implemented.
- **Hedged wording** ("should pass", "looks correct") is a signal that verification has not run yet.
  Run it, or report the status as unverified.

Apply this before commits, PRs, handing off, or moving to the next task.

---

## Execution Checklist verification

**When another skill hands off a durable artifact, verify its Execution Checklist:**

```
Verification items:
□ Does the artifact handoff include the Checklist? (missing = handoff incomplete)
□ Does every Step have evidence? (no evidence = not executed)
□ Do gate checks have actual run results? (no result = not verified)
□ Are notes reasonable? (question anything suspicious)
```

**Red Flags (follow up):**

- Every Step "done" with no evidence
- All gate checks PASS with no command output
- Notes are empty or too thin
- Timestamps are implausible (for example, in the future)

**When verification fails:**

```
Ask the AI to rerun the skill and output the full Checklist
```
