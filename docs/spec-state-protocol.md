# Spec-state protocol

skill-commons keeps engineering intent, execution state, and verification evidence
trustworthy after a conversation ends or work moves to another collaborator, agent,
tool, or session.

## The problem: spec entropy

Requirements lose detail as they move through chat, implementation, review, and
release. Decisions are copied into several documents, plans outlive changed specs, and
completion claims become detached from the command that could prove them. This is spec
entropy: current truth becomes harder to identify and easier to misread.

The protocol counters that drift with repository-resident state:

```text
requirement and acceptance criteria
  → versioned Spec and stable references
  → dependency-aware execution Plan
  → implementation and decision record
  → fresh verification evidence
  → resumable handoff
```

## Stakeholder view

| Collaborator | Question | Repository answer |
|---|---|---|
| Developer | What should I change, and what proves it? | Spec, acceptance criteria, task definition, verification command |
| Handoff collaborator | Where did the previous session stop? | `meta.yml`, canonical Plan, blockers, evidence, Git history |
| Reviewer or tech lead | Is the completion claim supported? | Fresh command output linked to the requirement and task |
| Product or requirement owner | Did implementation drift from intent? | Stable references from PRD and Spec through Plan and reports |
| Maintainer | Do different tools follow the same contract? | Top-level sources, generated adapters, ownership ledger |

Using a construction analogy, Spec 是施工圖, Plan is the construction sequence,
`meta.yml` is the progress board, tests are inspection reports, and Git preserves the
change history. Skills are operators of this shared state; they do not become separate
sources of project truth.

## One durable work item

Work that must survive a handoff lives under one `docs/work/<slug>/` directory. The
execution mode selects the minimum valid set of artifacts; a personal fix does not
inherit the full team-feature chain.

`meta.yml` separates two facts:

- `work_status`: whether the requested engineering work is active, completed, or
  abandoned;
- `delivery_status`: whether approval, PR creation, merge, or deployment actually
  happened.

Each stage points to an existing artifact and records its current state. The machine
contract in `protocol-registry.json` defines which artifacts are required, optional, or
absent for each execution mode. [`ARTIFACTS.md`](../ARTIFACTS.md) is the human-readable
format reference.

## References instead of copied truth

Canonical Plan tasks refer to upstream files and literal stable IDs. They record intent,
expected result, dependencies, definition of done, verification, and evidence. Plan
validation checks references, cycles, blocker transitions, dependency readiness, and
consistency with the sibling work-item metadata.

When a source changes, old evidence does not silently prove the new state. The task can
return to review, record a deviation, or be superseded with an explicit reason. Routine
conversation and duplicated logs stay outside the durable journal.

Plan Sync owns repository execution state. Host Goal Mode owns continuation, budget,
pause, and host completion, so Plan Sync reports `host_goal=unmanaged`. This boundary
allows the same repository plan to survive hosts that expose different lifecycle APIs.

## Evidence before state transitions

A completion claim requires a fresh, relevant command and its result. A plan checker
can validate evidence shape and references; it cannot turn authored `PASS` prose into
behavioral proof.

Human decisions use durable typed references. PRD approval, team design approval, and
release approval remain distinct from machine checks. Delivery evidence is added only
after the corresponding event exists; a passing test never implies a PR, merge, or
deployment.

Security preflight, dependency review, authorization review, and Git operations retain
separate scopes. Push, merge, destructive recovery, and publication require explicit
human authorization at the actual event boundary.

## Cross-tool portability

Top-level skill directories are the only workflow source. Bootstrap selects a delivery
mode and optional capability packs, then generates host adapters for Claude Code and
Codex; Cursor receives its supported rule and `AGENTS.md` boundary. An ownership ledger
limits updates and uninstall to managed content and preserves foreign files.

The portable unit is the repository artifact and contract. Host schedulers, model
memory, UI, and runtime capabilities can differ without becoming the source of work
truth. Platform details live in
[`profile-platform-support.md`](profile-platform-support.md).

## Adoption boundary

The protocol is most useful when work crosses sessions, collaborators, agents, or
formal review gates. A factual lookup or bounded micro-task should take the direct path
and avoid durable ceremony. Team features use the formal PRD, Spec, Plan, QA, and
evidence chain; personal work selects only the state needed for safe continuation.

Discovery, research, testing-seam, and vertical-slice rules are described in
[`discovery-and-planning.md`](discovery-and-planning.md). Current evidence and its claim
limits are recorded in [`evaluation.md`](evaluation.md).
