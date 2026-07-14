# Consented Deep wayfinding

Use when material ambiguity spans sessions and no honest execution route exists.
Wayfinding clears decisions before implementation.

## Consent package

Present Destination, scope, question/source budget, expected `brainstorm.md`, and
`proceed`, `narrow`, or `stay Standard`. Persist consent only after proceed.

## Map shape

```markdown
# Brainstorm: <title>

## Wayfinding Control
- Consent Ref: user:<durable-reference>
- Consented Scope: <boundary>
- Initial Budget: <questions/sources>
- Remaining Budget: <questions/sources>
- Last Updated: <ISO-8601>

## Destination
<the decision or executable handoff this exploration must reach>

## Decisions
- [D-001 — name](#d-001--name) — one-line result

## Fog
<in-scope unknowns that cannot yet be phrased as precise questions>

## Frontier
<precise, unblocked questions available now>

## Out of scope
<boundaries that do not graduate into the Frontier>

## Resolutions
### D-001 — name
<answer, evidence links, uncertainty, and newly exposed Frontier/Fog>
```

`Decisions` is a bounded index; each resolution appears once under its stable heading.

## Advance and resume

Resolve one Frontier item at a time. Update Decisions, Fog, Frontier, Remaining
Budget, and Last Updated together. Resume from Wayfinding Control, Destination,
the indexes, and active resolution; skip unrelated detail.

Consent survives within persisted scope and Remaining Budget; expansion requires
new consent. A legacy brief without required headings remains history.

## Entropy and handoff

Keep `brainstorm.md` ≤24,576 UTF-8 bytes and each resolution ≤6,144 bytes. Promote
larger reusable evidence to `docs/reference`, leaving one resolution link.

Stop when PRD, Spec, or Plan tasks can express the work. Wayfinding does not execute
the Destination, create tracker issues, or add a workflow mode.
