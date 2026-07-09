---
name: to-prd
description: Turn the current conversation into a PRD and publish it to the project issue tracker — no interview, just synthesis of what you've already discussed.
disable-model-invocation: true
source: mattpocock/skills@2454c95dc305
source_kind: vendored
stage: docs
output: <work_root>/<slug>/prd.md
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user — just synthesize what you already know.

Issue tracker publication is optional. If tracker access or label vocabulary is unavailable, create the local artifact and report that publication was skipped.

## PRD shape

Write `prd.md` against the canonical [PRD template](../prd-template.md) — the single
source of truth shared with `prd-interview`. Do not keep a private copy of the shape
here. As a synthesis (no interview), populate the `core`-tier sections; omit any
`team`-tier section you cannot fill rather than leaving its placeholders in place.
Record open questions as Follow-ups instead of expanding scope. The shape is enforced
by the shared PRD shape gate (`check-prd.py`), so keep headings and the `AC-<n>`
Given-When-Then form intact. For a team-sprint handoff into `spec`, author the PRD with
`prd-interview` (team tier) instead — a `--tier core` PRD does not satisfy spec's
team-tier precondition (it omits NFR, dependencies, and the metadata table).

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already. Use the project's domain glossary vocabulary throughout the PRD, and respect any ADRs in the area you're touching.

2. Identify the smallest useful verification surface from the existing discussion and codebase evidence. Prefer one high-level observable seam; record uncertainty as a Follow-up instead of expanding the PRD.

3. Write `prd.md` and update `meta.yml` under `<work_root>/<slug>/` following [`../ARTIFACTS.md`](../ARTIFACTS.md), using the canonical [PRD template](../prd-template.md).

4. Run the shared PRD shape gate before handoff and fix any `FAIL` (this check is deterministic and does not wait for human approval):

   ```bash
   python3 <shared_skills_root>/scripts/check-prd.py --prd "<work_root>/<slug>/prd.md" --tier core
   ```

5. If an issue tracker and `ready-for-agent` label are configured, publish the PRD after the local files exist and the shape gate passes.
