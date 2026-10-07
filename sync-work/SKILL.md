---
name: sync-work
description: |
  Authoritative Git delivery interface for scoped save, integration, branch finish, and recovery. Preserves unrelated work and gates external or irreversible actions.
  觸發關鍵字: /sync-work, 保存進度, commit, push, merge, PR, 收尾, recovery
source_kind: original
stage: infra
---

# Sync Work

Git delivery has one current interface with four modes: Scoped Save, Integrate,
Finish, and Recovery. Branch-start capability is a subordinate setup step inside
Scoped Save; it is not a fifth workflow owner or mode.

## Common contract

1. Read `.agent/project-manifest.md` `Git Workflow`, guardrails, and any declared
   `project/git-workflow` domain skill. Missing values remain unknown; infer only
   from repository evidence or ask.
2. Inspect branch, remotes, status, staged/unstaged diff, and relevant commits.
   Separate task files from unrelated dirty work before proposing any mutation.
3. Require fresh verification for the exact candidate. Run `security` separately
   and record separate security evidence; a secret preflight is not overall
   verification or release approval.
4. Show the exact files, refs, command category, and impact before mutation. Obtain
   explicit approval before external or irreversible actions, including network,
   push/PR, merge/rebase, stash, discard, branch deletion, or remote changes.
5. Never use broad staging or cleanup. `git add .` and `git add -A` are forbidden;
   preserve every unrelated path and report it afterward.

## Optional pre-PR brief

Before a pending push/PR, offer once: "Enable the project overview and understanding
test before this push/PR, or skip it?" Honor an existing choice for this candidate;
do not re-ask after an explicit opt-in or skip. Only enable the
[pre-PR brief](references/pre-pr-brief.md) after the user opts in. A skip or no answer
leaves it untriggered and does not add a gate to already-authorized delivery.
Do not offer it during unrelated edits, local-only saves, or read-only work.

When enabled, prepare the brief and an answerable, source-grounded understanding
test with scoring, explanations and focused retry. A score is not delivery approval.
Honor a narrower request for a summary only. The brief can be a local draft
even when exact-candidate verification or separate security evidence is missing or
stale; label each gap and set readiness to unknown. Do not add tests or re-audit
merely to write that draft. Before any dependent push/PR or other delivery, the
Common contract still requires fresh exact-candidate verification and separate
security evidence; the brief never substitutes for those gates. When that evidence
is available, prepare the brief before the push/PR step. It reuses the report and
Gate Package without adding a stage or gate. Existing delivery authorization remains
valid; understanding questions pause dependent actions only when the answer affects
scope, correctness, or delivery safety. Keep any pending opt-in separate from
required delivery authorization, and continue independent work while awaiting it.

## Mode: Scoped Save

Use for subordinate branch setup, explicit staging, local commits, or an authorized
push.

1. Inspect `git status --short`, current branch, remotes, and scoped diffs. Confirm
   the task-owned file list and leave unrelated dirty work unstaged.
2. If branch setup is needed, resolve base and naming from manifest/repo evidence.
   Show how switching or creating the branch affects the dirty tree and obtain
   approval before the branch mutation.
3. Run fresh verification before a commit. Failures stop the mode.
4. Stage only approved paths with `git add -- <paths>` and review `git diff --cached`.
   Then run the applicable security evidence; the secret scan reads the index, so it
   must run after staging to cover this batch. A failure stops the mode with the
   batch still staged for the user to inspect.
5. Commit using the confirmed project convention.
6. Push only after separate explicit approval and a known remote/target. If there is
   no remote, stop without creating one. Record a commit SHA or push ref only after
   the actual event succeeds.

## Mode: Integrate

Use to compare or combine a confirmed source and target.

1. Resolve source, target, and integration policy from manifest/domain skill or ask.
   A missing remote, unknown base, or unsupported policy is a safe stop.
2. Inspect local refs first. Obtain approval before fetch or any other network
   access; only then refresh the named refs.
3. Show commits, diff stat, and ahead/behind counts. Stop on divergence that the
   declared policy does not resolve.
4. Obtain separate approval before merge or rebase. Never infer that fetch approval
   also authorizes integration.
5. On conflict, stop with the affected paths and preserve both sides; do not discard,
   auto-resolve, or continue. After a successful integration, rerun fresh
   verification and report the resulting ref without implying delivery.

## Mode: Finish

Use after implementation is complete to request and execute one closeout outcome.

1. Require fresh verification, review, and separate security evidence. Prepare a
   Gate Package with changes, evidence, risks, and four decision options. Code
   completion sets `work_status: completed`; before approval keep
   `delivery_status: awaiting_approval` and do not invent delivery evidence.
2. Present exactly these outcomes:

   1. Local merge
   2. Push and create PR
   3. Keep branch
   4. Discard work

3. Local merge requires release approval, then approval before any fetch and
   approval before merge or rebase. With no remote, use only confirmed local refs;
   with a remote, stop on non-fast-forward divergence. Run post-merge verification.
   Only after the actual event record `delivery_status: merged`, the durable
   `approval_ref`, and the full `merge_sha`.
4. Push and create PR requires release approval and separate approval for network
   actions. Record `delivery_status: approved` after approval; record
   `delivery_status: pr_created` plus `approval_ref` and `pr_url` only after the PR
   actually exists. A blocked push or predicted URL is not evidence.
5. Keep branch performs no merge, push, or deletion: set release stage: `done`, keep
   `work_status: completed`, and restore `delivery_status: not_requested` without
   PR/merge evidence.
6. Discard work uses discard double-confirmation: selecting outcome 4 is the first
   confirmation; then show the exact commits/files/branch that would be lost and
   require the literal `discard` as the second. Only afterward may deletion occur,
   with `work_status: abandoned` and `delivery_status: not_requested`.

Approval, PR, and merge evidence are actual-event-only. An approval never proves a
PR or merge, and a local commit never proves delivery.

## Mode: Recovery

Use to restore a verified stable state without erasing unrelated work.

1. Inspect and classify staged, uncommitted, unpushed, and published state, plus
   current refs, remotes, affected files, and the last known-good point.
2. Propose the smallest reversible action. Unstage only scoped paths; stash requires
   approval and must name its scope; preserve unrelated dirty work throughout.
3. Obtain approval before stash, discard, delete, or remote changes. For published
   commits, use a new `git revert` commit after approval rather than rewriting
   history. Stop when authorship, publication state, or impact is uncertain.
4. Never use `reset --hard`, force push, or whole-tree checkout as a recovery
   shortcut. Never broaden a path-scoped recovery to the whole repository.
5. Run fresh verification after recovery, inspect status/diff again, and record the
   resulting refs plus remaining unrelated changes. A failed verification leaves
   recovery incomplete.

## Completion report

```text
mode: scoped-save | integrate | finish | recovery
branch/source/target: <resolved values or N/A>
scoped files: <task-owned list>
remaining unrelated changes: <list or none>
verification: <command and result>
security evidence: <separate command/scope/result>
approvals: <action + durable reference or not requested>
actual events: <commit SHA / push ref / PR URL / merge SHA / none>
work_status: <state or N/A>
delivery_status: <state or N/A>
safe stop: <reason or none>
```
