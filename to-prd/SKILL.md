---
name: to-prd
description: Turn the current conversation into a core-tier PRD at <work_root>/<slug>/prd.md — no interview, just synthesis of what you've already discussed. Optionally publish it to the project issue tracker.
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

5. If an issue tracker and `ready-for-agent` label are configured and the user asks for or approves publication, publish the PRD after the local files exist and the shape gate passes. Otherwise report that publication was skipped.

## Execution Checklist（必填輸出）

> 格式慣例見 [CHECKLIST-CONVENTION.md](../CHECKLIST-CONVENTION.md)。狀態只用 PASS/FAIL/N/A，不使用圖示。

```
Skill: to-prd
Executed At: YYYY-MM-DD HH:MM
Artifact: <work_root>/<slug>/prd.md

Steps:
PASS Step 1: 探索 repo 現況與既有 glossary/ADR
  Evidence: <相關現況摘要>
PASS Step 2: 界定最小可觀察驗證面
  Evidence: <observable seam;不確定改記 Follow-up>
PASS Step 3: 寫 prd.md 與 meta.yml（canonical PRD template）
  Evidence: <work_root>/<slug>/prd.md
PASS Step 4: PRD shape gate（core tier）
  Evidence: check-prd.py --tier core 退出 0
PASS Step 5: tracker 發佈
  Evidence: <PASS 或 N/A（未設定 tracker）>

Result: PASS | FAIL | N/A
Summary: <core-tier PRD 產出摘要>
Notes: <team-sprint 需接 spec 時改用 prd-interview（team tier）;否則填「無」>
```

**未輸出 Checklist = 未完成 Skill**
