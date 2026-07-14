# Discovery and planning contract

This reader guide explains when discovery is worth its cost and how settled intent
becomes an executable, verifiable plan. The authoritative agent instructions remain in
the corresponding top-level skills.

## Brainstorming：有歧義才用

Brainstorming qualifies only material ambiguity that can change scope, architecture,
public behavior, or acceptance criteria and cannot be resolved from repository
evidence. Clear implementation, bug diagnosis, review, approved-spec work, and read-only
事實查證 stay on the direct path.

| Situation | Mode | Boundary |
|---|---|---|
| Factual lookup / 事實查證 | Skip | Read repository or authoritative evidence and answer |
| Bounded ambiguity | Quick or Standard | Resolve the choice, then implement or plan |
| Consented Deep / 同意進入 Deep | Deep + Wayfinding | Track Destination, Fog, Frontier, and remaining budget |
| Known executable work / 需求已清楚 | Skip | Start implementation or Plan Sync |

Quick asks at most one question. Standard asks at most three questions, offers at most
two options per decision, and uses one final confirmation. Deep requires an explained
scope, budget, and explicit consent. `brainstorm.md` is conditional on a durable
cross-session, cross-agent, formal team handoff, or user request.

## Research and Wayfinding

Research is a conditional subroutine inside qualified Standard or Deep discovery. It
starts with a specific implementation decision, source priority, source budget,
stopping condition, citation format, and uncertainty record. Ordinary factual lookup
does not load the discovery workflow.

Wayfinding manages consented Deep work that still has unresolved Fog across sessions.
Its map records Destination, current Frontier, decisions, out-of-scope areas, consent,
and remaining budget. Once the route is clear, the work hands off to requirements,
Spec, or Plan instead of preserving exploration as execution truth.

## Selected Seam

A Spec chooses the nearest stable existing boundary that directly proves an acceptance
criterion at acceptable reliability and execution cost. Repository evidence supports
the selection. Lower-level seams remain only when they prove distinct behavior.

Each seam has a stable `SEAM-*` ID. QA references that exact decision, and the checker
verifies both the Spec fields and the matching QA reference. Unit, integration,
component, and E2E labels follow observed repository behavior rather than a global
preference.

## Vertical slices and wide refactors

Behavior-changing work is divided into a 垂直切片 / vertical slice that leaves the
integrated system supported and has an observable verification point. A migration that
cannot produce an independent increment records the next integration checkpoint.
Wide replacement follows expand → bounded migration → contract, with dependencies and
ready work expressed in canonical Plan fields.

## Evidence boundary

Static contract tests verify these written boundaries and deterministic fixtures. They
do not prove model trigger accuracy, token savings, reduced user effort, or output
quality.

The historical blinded GPT-5.5 classifier smoke scored 83.33%, below its frozen 90%
threshold. That score belongs to the pre-T10 payload and remains pre-T10 historical negative evidence.
The current payload has no equivalent classifier result, so the release does
not claim proven effectiveness.

See [`evaluation.md`](evaluation.md) for the later A/B/C benchmark, strict-blind
validity finding, and proposed cross-session product test.
