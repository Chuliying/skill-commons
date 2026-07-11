# Real-agent Journey Evals

These evals exercise workflow behavior with a fresh agent in an isolated Git repository. They are not part of the deterministic Verify command because they consume model quota and may take several minutes.

## Journeys

| Journey | Contract under test |
|---|---|
| `personal-feature` | Personal feature takes the lightweight RED-GREEN-REFACTOR path without invented PRD/Spec/QA artifacts. |
| `team-feature` | Team feature produces the formal artifact chain and capability-aware Gate evidence. |
| `brownfield-bug` | Existing failing behavior routes through debugging and implement without feature paperwork. |
| `refactor` | Refactor records intent, preserves behavior, and avoids irrelevant QA artifacts. |
| `commit-pr` | Release preflight runs verification/review/security, records completed work separately from delivery, commits locally, and stops safely when no remote exists. |

## Run

Warning: non-dry-run journeys execute agents with approval and sandbox bypass
flags. Run them only on a machine where unrestricted agent access to the fixture
workspace and host environment is acceptable.

```bash
# Fresh Codex baseline
bash journey-evals/run.sh --harness codex --scenario all

# Preferred Claude Code/Fable release evidence
bash journey-evals/run.sh --harness claude --model fable --scenario all
```

For v0.5.0, the release handoff records an explicit user-approved waiver when
Claude Code/Fable completed 4/5 post-convergence journeys and Codex completed the
remaining `team-feature` journey. Future releases should either run all Fable
journeys or record an equivalent waiver in the release handoff.

Each run creates a sibling directory under `../skill-commons-journey-runs/`
containing the exact prompt, isolated workspace, agent log, and deterministic
`grade.json`. `SKILL_COMMONS_JOURNEY_ROOT` changes the default root, and
`--output <path>` selects one run directory. Both locations must stay outside
the source repository so bootstrap safety can distinguish source from generated
fixture roots. `--dry-run` prepares fixtures without invoking a model.

`grade.json` separates evidence instead of flattening unlike claims:

- `structural`: files, metadata, Git state, and other deterministic shape checks.
- `behavioral`: commands the grader actually executes, including fixture tests
  and the harness-owned canonical secret preflight when applicable.
  Agent-writable generated copies are not trusted; the scan uses the regular
  fixture manifest unchanged from the harness-recorded baseline and ignores an
  inherited `PROJECT_MANIFEST` override.
- `recorded`: report records and scoped manual attestations. Every key uses a
  `_recorded` suffix where omission could imply observation. A `true` value proves
  only that report text is present and properly scoped; it does not prove that a
  skill was read, a command was run, or a review was performed.

## Pass criteria

Every journey must satisfy all of these:

1. Structural artifacts and lifecycle metadata match the scenario.
2. The fixture's real tests pass when the grader reruns them.
3. Commit/PR journeys keep the baseline manifest unchanged and pass the
   harness-owned canonical heuristic secret preflight; report prose cannot
   substitute for execution.
4. Manual review has a recorded reviewer and a diff scope tied to the parent commit, while remaining labeled as recorded evidence.
5. Capability-disabled checks are N/A rather than fabricated.
6. Git/remote fallback behavior matches the prompt and guardrails.

The deterministic grader decides whether the run's structural, behavioral, and
record-keeping contract passes. `grade.json` alone cannot establish true-agent
execution: release adjudication must also retain and inspect the harness identity,
prompt, and agent log. Release coverage is a separate Gate:
run all Fable journeys, or record an explicit user-approved waiver in the
release handoff.
