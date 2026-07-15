# Evaluation and evidence

This document separates repository conformance, model behavior, operating cost, and
product value. A green structural test supports only the contract it executes.

## Evidence map

| Question | Current evidence | Status |
|---|---|---|
| Do artifact, Plan, profile, adapter, and release contracts agree? | Deterministic repository suites | Supported for the tested revision |
| What is the input-token cost of loading workflow guidance? | Historical eight-case A/B/C narrative; raw private run artifacts unavailable | Unverified until original evidence is recovered or rerun |
| Did the historical blind scorer establish quality or usability gains? | Packets leaked arm identity | Unsupported; scores compromised |
| Did the repaired Luna-high blind scoring establish a quality winner? | Historical audit/scoring narrative; raw private run artifacts unavailable | No; the narrative is mixed and cannot be independently replayed |
| Can another tool cold-start and continue with less rework? | No matched handoff experiment yet | Unmeasured |
| Does the bundle improve team throughput or human usability? | No matched team study | Unmeasured |

## Deterministic repository verification

The repository runner covers skill/profile composition, artifact and work-item shape,
protocol-registry constraints, canonical Plan references and dependencies, Repo Map,
journey fixtures, gate automation, generated ownership, public export, bootstrap safety,
and release convergence.

The T07 convergence checkpoint on 2026-07-13 recorded 1,520 deterministic assertions
with zero failures. That proves the checked repository contracts agreed at that
checkpoint. It does not measure developer time, rework, model quality, or cross-tool
handoff success. Release candidates rerun `PROFILE=all bash bootstrap/generate.sh` and
`bash tests/run-all.sh`; historical counts never replace fresh output.

## Historical benchmark evidence warning

During the 2026-07-15 private-source reconciliation, the benchmark harness, packets,
ledgers, handoff, and replay artifacts described below were absent from private
`origin/main`, every local branch/tag/reflog entry, recoverable Git blobs, and accessible
workspace copies. No scores or session records were reconstructed. The numbers below
are retained as the narrative that shipped in v0.8, but they are not independently
replayable evidence and must not be used as a release claim. See the private
`docs/work/skill-bundle-effect-benchmark/evidence-recovery.md` record in the development
repository.

## Frozen A/B/C benchmark

Eight cases covered factual lookup, a micro-task near miss, bounded ambiguity,
qualified research, refused Deep escalation, Wayfinding resume, known cross-session
planning, and wide-refactor planning.

- A: no workflow payload.
- B: Router, Brainstorming, Research, Wayfinding, and Plan Sync all preloaded.
- C: Router first, with conditional reads observed from host tool events.

All execution arms used the same prompt, fixture, requested `gpt-5.5`, low reasoning,
32,768 context limit, read-only sandbox, and disabled external capabilities. The pilot
ran 24 executions and 8 scorer sessions. The authorized replay ran 24 executions,
8 scorer sessions, and 1 adversarial review, exactly 33 new sessions with no retry.

Replay mean input tokens were:

| Arm | Mean input tokens | Relative to A |
|---|---:|---:|
| A | 25,514.625 | baseline |
| B | 42,065.625 | +64.9% |
| C | 35,093.5 | +37.5% |

C used 16.6% fewer mean input tokens than B. This supports selective loading over
all-preload and the shortest route for factual or micro work. It does not establish a
quality advantage or prove that the remaining overhead is worthwhile.

## Why historical blind scores are excluded

Scorers were intended to receive only X/Y/Z outputs. Some answers cited execution temp
paths whose directory names contained the actual A/B/C arm letter. Four initial and
three replay packets were affected. The scorer was not given the treatment meanings,
but the frozen protocol promised no arm identity, so strict blindness failed.

Post-hoc edits cannot change what a completed scorer saw. Quality, ranking, and
usability-proxy scores remain preserved as compromised descriptive evidence and are
excluded from release claims. Host-token metering and observed component reads do not
depend on those packets and remain valid within their recorded configuration.

## Luna-high scoring repair

A separate v2 packet gate now sanitizes known execution paths, rejects remaining arm
clues, limits packet fields, and freezes per-packet plus complete-set hashes before any
scorer can start. It leaves raw execution evidence and historical scores untouched.

The user authorized exactly 1 packet audit, 8 fresh blind scorers, and 1 final
adversarial review on `codex-cli 0.144.1` with `gpt-5.6-luna`, high reasoning, and no
retry. The packet audit independently checked all eight optimized replay packets before
scoring and passed with no identity leak or rubric asymmetry. Its frozen manifest
identity is `c28b4c6ab933c49843c32fafd07c522b19b09541e58fbee43dd9676c0380fca6`.

Each scorer received one X/Y/Z packet in a separate ephemeral session. The private
label-to-arm mapping was read only after all eight structured scores were complete.
Descriptive results were:

| Arm | Rubric items passed | Mean rank (lower is better) |
|---|---:|---:|
| A — no workflow | 57/60 (95.0%) | 1.500 |
| B — all-preload | 60/60 (100.0%) | 1.625 |
| C — Router-first | 60/60 (100.0%) | 1.750 |

B and C missed no rubric items in this corpus, while A received the best mean preference
rank. With eight replay cases and one scorer model per case, this is mixed descriptive
evidence, not a general quality or usability effect. It supports neither “workflow is
better” nor “no workflow is better.”

The sole final adversarial-review session completed without retry and returned `fail`.
It passed authorization, unique 1/8/1 accounting, frozen packet identity, audit-before-
scoring order, complete anonymous rubrics, and delayed mapping. The aggregation artifact
was descriptive, but the combined aggregation-and-claim-restraint requirement was
recorded `fail` against the pre-correction text, which overstated completion of the same
review. The reviewer also rejected the full validity chain because, while it was running,
its own ledger row was necessarily still `reserved`; the runner could attach `completed`,
the response hash, and the verdict only after the process exited. A zero-model post-run
validator then confirmed 10/10 completed sessions, exact 1/8/1 roles, and retry ordinal
0. That later fact does not overwrite the reviewer's observation or verdict.

No retry was performed. The repaired scores remain mixed descriptive evidence; the
complete ten-session protocol is recorded as not passed. A future protocol must assign
self-completion verification to an external post-run validator and let the model review
only facts available before its own launch.

## Product-value test still needed

The next direct test is a cold-start handoff:

1. Agent A creates a work item and stops.
2. Agent B, or another supported tool, receives no chat transcript and resumes only
   from repository state.
3. The Spec changes after some work, making part of the Plan stale.
4. The successor must identify the drift, update current truth, and finish against the
   accepted criteria.
5. Compare resume time, clarification questions, stale work, rework, token use, test
   outcome, and reviewer preference against a no-protocol control.

This measures the project's core claim: trustworthy spec-state continuity across
collaborators, tools, and sessions.

## Private development evidence

The v0.8 text previously said the private repository retained the benchmark handoff,
completion audit, and replay analysis. Reconciliation found that statement was false:
those files were never preserved in the available private source history. The private
repository now retains an evidence-recovery record plus a freshly generated deterministic
convergence surface report. `docs/work/` remains excluded from public exports. Until the
original benchmark artifacts are recovered or a new authorized run is completed, all
historical model-run figures in this document remain unverified narrative.
