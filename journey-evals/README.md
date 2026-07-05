# Real-agent Journey Evals

These evals exercise workflow behavior with a fresh agent in an isolated Git repository. They are not part of the deterministic Verify command because they consume model quota and may take several minutes.

## Journeys

| Journey | Contract under test |
|---|---|
| `personal-feature` | Personal feature takes the lightweight RED-GREEN-REFACTOR path without invented PRD/Spec/QA artifacts. |
| `team-feature` | Team feature produces the formal artifact chain and capability-aware Gate evidence. |
| `brownfield-bug` | Existing failing behavior routes through debugging and implement without feature paperwork. |
| `refactor` | Refactor records intent, preserves behavior, and avoids irrelevant QA artifacts. |
| `commit-pr` | Release preflight runs verification/review/security, closes the work item, commits locally, and stops safely when no remote exists. |

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

Each run creates an ignored directory under `journey-evals/runs/` containing the exact prompt, isolated workspace, agent log, and deterministic `grade.json`. Use `--output <path>` to choose another location. `--dry-run` prepares fixtures without invoking a model.

## Pass criteria

Every journey must satisfy all of these:

1. The agent report names `skill-router` and the dispatched skills it actually read.
2. Required artifacts exist, forbidden ceremony is absent, and `meta.yml` records the expected state.
3. The fixture's real test command passes after the agent finishes.
4. Capability-disabled checks are N/A rather than fabricated.
5. Git/remote fallback behavior matches the prompt and guardrails.

The deterministic grader is the release decision source. Agent prose alone never counts as a pass.
