# Phase 5: Escalation (reporting to the user)

> Loaded by `systematic-debugging` when the problem cannot be solved without help.

When the AI cannot solve a problem on its own, it **must** stop and escalate to the user.

## Triggers

| Condition | Why | Action |
|------|------|------|
| **3+ failed fix attempts** | Likely an architecture problem, not a simple bug | Stop → escalate |
| **Unresolved for more than 30 minutes** | Avoid burning time in an endless loop | Stop → escalate |
| **Affects production** | Risk needs a human decision | Escalate immediately |
| **Involves a security issue** | Outside the scope of AI decisions | Escalate immediately |
| **Needs access to protected resources** | Would violate guardrails | Stop → escalate |
| **Root cause cannot be identified** | Phase 1 is complete but the cause is still unclear | Escalate with the investigation results |

## Escalation format

When escalating, you **must** use the following format:

```markdown
## 🆘 Escalation Report

### Problem summary
[One sentence describing the problem]

### Fixes attempted
| # | Hypothesis | Fix action | Result |
|---|------|---------|------|
| 1 | [hypothesis] | [fix action] |  Failed - [reason] |
| 2 | [hypothesis] | [fix action] |  Failed - [reason] |
| 3 | [hypothesis] | [fix action] |  Failed - [reason] |

### Investigation findings
- **Error message**: [full error]
- **Steps to reproduce**: [steps]
- **Recent changes**: [related commits/changes]
- **Data flow trace**: [trace results]

### Possible root causes (guesses)
1. [possible cause 1]
2. [possible cause 2]

### Suggested next steps
- [ ] [suggested action 1]
- [ ] [suggested action 2]

### Needs a human decision
- [question that needs a decision]
```

## Behavior after escalation

```
1. Stop the current fix attempt
2. Output the Escalation Report
3. Wait for the user's instructions
4. Do not continue trying new fixes on your own
```

## Common situations that need escalation

| Situation | Why it needs escalation |
|------|---------------|
| Test and production environments behave differently | May need access to production data |
| A third-party service is failing | Outside what the code can control |
| Root cause of a performance problem is unclear | May need profiling tools |
| Database schema problem | Needs help from a DBA |
| Authentication/authorization failure | Involves security-sensitive operations |

## Relationship to Phase 4.5

Phase 4.5 (Question Architecture) is a **technical judgment**:
- Decide whether this is an architecture problem
- Recommend whether a refactor is needed

Phase 5 (Escalation) is a **process interruption**:
- Stop autonomous AI work
- Hand control over to the user

**Order**: after the Phase 4.5 judgment, if human intervention is confirmed to be needed → trigger Phase 5
