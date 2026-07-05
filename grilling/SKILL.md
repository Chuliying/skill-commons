---
name: grilling
description: Interview the user relentlessly about a plan or design. Use when the user wants to stress-test a plan before building, or uses any 'grill' trigger phrases.
source: mattpocock/skills@2454c95dc305
source_kind: vendored
stage: plan
output: <work_root>/<slug>/{adr.md,glossary.md}
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing. Asking multiple questions at once is bewildering.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Modes

- Conversation mode: challenge the plan one decision at a time; no artifact is required.
- Durable docs mode: when the user asks to preserve the stress test or the workflow needs a handoff, also use `domain-modeling`, then write `adr.md`, `glossary.md`, and `meta.yml` under `<work_root>/<slug>/` following [`../ARTIFACTS.md`](../ARTIFACTS.md).

In durable docs mode, `adr.md` records resolved choices, alternatives, consequences, and remaining risks. `glossary.md` records agreed domain terms. Do not manufacture decisions merely to fill either file.
