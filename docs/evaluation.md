# Evaluation and evidence

This document separates repository conformance, model behavior, operating cost, and
product value. A green structural test supports only the contract it executes.

## Evidence map

| Question | Current evidence | Status |
|---|---|---|
| Do artifact, Plan, profile, adapter, and release contracts agree? | Deterministic repository suites | Supported for the tested revision |
| What is the input-token cost of loading workflow guidance? | 2026-08-24 replayable A/B/C rerun: 27 metered sessions at a fixed revision on claude-haiku-4-5; raw session JSON and ledgers preserved in the development repository | Supported for the tested revision and model: all-preload +17.2% uncached input vs no payload; router-first +0.3% on means, a ≈+13% median premium in the paired view |
| Does leak-free blind scoring show a quality winner between the arms? | 2026-08-24 repaired 1/8/1 protocol rerun: structural blindness, frozen packet hashes, zero-model post-run validation | Supported as descriptive evidence only: all-preload won rank and rubric in the tested corpus; not a general quality effect |
| Can another tool cold-start and continue with less rework? | Matched handoff instrument built and piloted 2026-08-24, n=1 per arm; no protocol benefit observable at micro-task scale | Unmeasured beyond the pilot; needs matched pairs on context-heavy tasks |
| Does the bundle improve team throughput or human usability? | Pre-registered matched team study protocol designed 2026-08-24; no data collected | Unmeasured until a consenting team runs the protocol |

## Deterministic repository verification

The repository runner covers skill/profile composition, artifact and work-item shape,
protocol-registry constraints, canonical Plan references and dependencies, Repo Map,
journey fixtures, gate automation, generated ownership, public export, bootstrap safety,
and release convergence.

The T07 convergence checkpoint on 2026-07-13 recorded 1,520 deterministic assertions
with zero failures. That proves the checked repository contracts agreed at that
checkpoint. It does not measure developer time, rework, model quality, or cross-tool
handoff success. Release candidates rerun `PROFILE=all bash bootstrap/generate.sh` and
`bash tests/verify.sh`; historical counts never replace fresh output.

## 2026-08-24 evidence reruns

Rather than recovering the lost 2026-07 artifacts, the open questions were
re-answered by fresh, fully replayable experiments recorded in the development
repository's `eval-evidence-rerun` work item (harness, raw session JSON,
ledgers, frozen manifests, and reports). All runs used the `claude` CLI
headless with full token metering at repository revision `c6015d1`.

- **Token cost (A/B/C rerun)**: 8 cases mirroring the historical taxonomy,
  three arms (A no payload; B preload router+brainstorming+plan-sync; C router
  only with conditional in-workspace reads), 27 `claude-haiku-4-5` sessions
  including one documented amendment (a turn-cap failure rerun as a complete
  case). On uncached input tokens, B costs **+17.2%** vs A while C costs
  **+0.3%** vs A (−14.4% vs B) on means — the same direction as the
  unreplayable 2026-07 narrative. The paired view tempers the C result: C sits
  above A in 6 of 8 cases with a ≈+13% median premium; the near-zero mean
  traces to a single A-arm outlier. Total-input differences are turn-count
  dominated and unstable at n=8. Session cost USD 2.62.
- **Blind scoring (repaired 1/8/1 protocol)**: anonymized X/Y/Z packets with
  neutral path sanitization, a zero-model leak gate, and hashes frozen before
  any session; 1 packet audit, 8 tool-less single-packet scorers, zero-model
  aggregation, then 1 adversarial review restricted to pre-launch facts, with
  session accounting verified by an external zero-model validator instead of
  any model's self-attestation. Two early attempts were aborted fail-closed by
  the packet audit (execution-path leaks — the exact historical failure mode —
  then a self-describing redaction placeholder); one attempt lost a scorer to a
  turn cap and was recorded incomplete. The completed attempt: validator PASS;
  pre-registered decision rule yields **all-preload as the descriptive winner**
  (rubric 31/32, mean rank 1.75 vs 2.125/2.125). The adversarial reviewer
  returned fail after misreading a 64-character frozen hash as 66 characters;
  its verdict is preserved unedited, and the deterministic recomputation that
  contradicts it is exactly the external-validator architecture this protocol
  exists to provide. Descriptive evidence only: one scorer session per case,
  one model pair. 22 sessions across attempts, USD 2.96 actually spent (the
  ledgers first recorded 2.67 because failed sessions' costs were skipped;
  the harness now records them).
- **Cold-start handoff**: the matched experiment described below now exists as
  a replayable instrument and ran one pilot pair (protocol arm vs control) on
  a three-criterion task with a mid-stream spec change. Both successors
  finished correctly; the protocol arm showed no benefit at this micro-task
  scale and its predecessor under-complied with the plan contract. n=1 per
  arm measures nothing general; the instrument and its next-iteration
  requirements are recorded in the work item.
- **Team study**: cannot be produced by a machine experiment; a pre-registered
  protocol (metrics, matched crossover design, decision rules, threats) is
  written and awaits a consenting team.

Notable tension to carry into any future claim: the arm that won the blind
preference (all-preload) is the arm with the measured input-cost premium, and
the cheapest arm (router-first) scored lowest on rubric passes in this corpus.

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

## Competitor comparison (October 2026)

A pre-registered test compared skill-commons with GitHub Spec Kit (`specify-cli` 1.2.5) and
SpecWeave 3.1.15. The pass definitions were committed before the runs they scored; step S6b and
criteria E to G were added later, before the runs that used them. Each product got the same
task: a small Python CLI, one feature with at least two acceptance criteria, then, after the product marked
the work done, a one-line code change, a one-sentence change inside a criterion, and a change outside
any criterion. Executors were Claude Haiku (competitors, and skill-commons rounds 1 and 2) and
Claude Sonnet (skill-commons round 3); scoring was by a second model and spot-checked by a third.

| Criterion | Spec Kit 1.2.5 | SpecWeave 3.1.15 | skill-commons `6f7ae22` |
|---|---|---|---|
| Status flags a code change after done, without a rerun | no (no per-item state) | no (`Completed`; `verify` catches it on rerun) | yes, 3 of 3 runs |
| Status flags a criterion change after done | no | no | yes, 3 of 3 runs |
| Approval records approver, scope and content fingerprint | not in the core flow (optional review gates not exercised) | no (`approvedAt` only) | yes |
| Install with at most two commands and no question, then the full flow | no (three commands, one prompt) | no (test command had to be given; `--cmd` and `--reason` were both available, and the refusal is counted blocking because the product should derive the command) | yes, 2 valid runs |
| Test command found without being told | no | no | yes |
| One list of all work items with stage files, verification and approver | no | partial (per increment) | yes |
| AI tool and time recorded by the product | no | yes (agent claim and time) | yes |
| Session identifier recorded by the product | no | yes (in its task ledger) | yes (Claude Code, Codex; Cursor reports none) |

Limits: each competitor has one designated run and two supplemental runs from the same round, and
none was rerun after skill-commons changed. One Spec Kit supplemental run applied the LLM convergence
step by hand and flagged both changes; it is excluded from the first two rows because they ask for a
status command, a rule written after that run.
skill-commons reached these results after fixes made in response to earlier runs of the same test,
whose failures are kept in the private record. One of the three final runs had an inconclusive
install and is not counted for install-related measures. A planted-defect handoff check did not
separate the products. skill-commons writes more root entries (six in a two-agent repository) than
Spec Kit (two in a Claude-only repository).
Six competitor runs shared containers with skill-commons runs or with each other, and every
scoring subagent loaded the development repository's own `CLAUDE.md`; one Spec Kit run describes
its implement skill in skill-commons wording.

### Agent-verification tools (November 2026)

The same steps and definitions, pre-registered before the runs, were applied to two tools that
bind agent verification to repository state: Lians 0.5.0 (commit `4eb78dc`) and ProofFlow v0.1.8
(`0662ee4`). One run each, Claude Sonnet executor. Neither defines a requirement file, so the
executor wrote a plain `requirements.md`.

| Criterion | Lians 0.5.0 | ProofFlow v0.1.8 | skill-commons `6f7ae22` |
|---|---|---|---|
| Status flags a code change, without a rerun | yes (`stale`) | no (`ready_for_review` while tests failed) | yes |
| Status flags a criterion change | yes, but with the same reasons as any file change | no | yes |
| Status ignores a change outside any criterion | no (flagged) | yes | yes |
| Approval records approver, scope and content fingerprint | not tested (needs an interactive terminal) | no | yes |
| Install with at most two commands and no question, then the full flow | no (tasks only through MCP; no done step) | no (five commands; MCP server failed to start) | yes |
| Test command found without being told | no (it does not run tests) | no | yes |
| One list of all work items with stage files, verification and approver | no (counts only) | partial (all cases, without those fields) | yes |
| AI tool and session recorded by the product | no (agent-typed `client`) | no (timestamps only) | yes |
| Files added to the repository by install | none | none | six root entries |

Lians reacts to any change in the workspace; skill-commons reacts only to changes in the files and
criteria a verification covers. ProofFlow reports on what the agent recorded, so it does not see
later code changes until the agent takes a new snapshot. Limits: one run per tool, MCP calls made
through a hand-written client (Lians) or the REST API the MCP tools wrap (ProofFlow), and Lians's
`report --json` and human confirmation were not exercised.

### Approval levels and allowed scope (November 2026)

Two more pre-registered checks ran on skill-commons `6fd9bed` (two Sonnet runs; competitors scored
from their earlier records). H asks whether an agent can record a person's confirmation: in both
runs the plain `approve` was refused in the agent session with the person's command printed, and
the approval finally recorded said `agent-reported`. Lians's human confirmation needs an
interactive terminal and has no agent-reported path, so it is not comparable; ProofFlow's decision
records no level. I asks whether changes outside a declared scope are listed: both runs listed a
committed `__pycache__` file and an out-of-scope `README.md`, and not an in-scope edit. Lians and
ProofFlow flagged a committed `__pycache__` in their own runs; an out-of-scope source file was not
tested for them. The same runs measured the install after the generated copies stopped being
committed: 7 root entries (including a new `.gitignore`), 466 files on disk, 8 tracked files.

## Product-value test still needed

The cold-start handoff instrument below was built and piloted on 2026-08-24
(see the rerun section above); what remains is running enough matched pairs on
context-heavy tasks to measure the effect. The design:

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
convergence surface report. `docs/work/` remains excluded from public exports. The
original benchmark artifacts were never recovered, so all historical model-run figures in
this document remain unverified narrative; the 2026-08-24 reruns above replace them as
the citable, replayable baselines for token cost and blind scoring.
