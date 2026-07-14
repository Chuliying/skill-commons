# [入口] - [Feature 名稱] 整合技術規格

**對應 PRD**: `<prd-artifact-path>` @ v1.0.0
**Spec 版本**: v1.0.0
**Stage**: awaiting-approval | approved | ready

## Capability Snapshot

| Capability | Value | Evidence |
|---|---|---|
| `has_ui` | [true/false] | [path / command / N/A] |
| `has_api` | [true/false] | [path / command / N/A] |
| `typed_contracts` | [true/false] | [path / command / N/A] |
| `has_e2e` | [true/false] | [path / command / N/A] |

## Version History / 版本歷史

| Version | Updated at | Change | PRD version | Author |
|---|---|---|---|---|
| v1.0.0 | [YYYY-MM-DD HH:mm] | 初版 | PRD v1.0.0 | [author] |

## Integration Target

| Feature | Artifact | Capability | Prerequisite |
|---|---|---|---|
| [name] | `[existing PRD/spec path]` | [capability] | [ready/version] |

## Files

| Path | Operation | Purpose |
|---|---|---|
| `[path]` | NEW/MODIFY/DELETE | [configuration or integration change] |

## Contracts

### Data Contracts (`typed_contracts` conditional)

| Contract | Source | Shape / fields | Evidence |
|---|---|---|---|
| [name or N/A] | [existing spec/types_entry/N/A] | [reference or N/A] | [command result / N/A] |

### API Contract (`has_api` conditional)

| Operation | Request | Success response | Error response | Auth / permission |
|---|---|---|---|---|
| [operation or N/A] | [example or N/A] | [example or N/A] | [example or N/A] | [rule or N/A] |

### UI Design (`has_ui` conditional)

| Entry / view | States | Interaction | Token evidence | Mockup evidence |
|---|---|---|---|---|
| [entry or N/A] | [states or N/A] | [trigger/result or N/A] | [path/result or N/A] | [path/result or N/A] |

## Flow / Data Flow

```text
[entry] -> [existing feature] -> [configured output]
```

**API-to-UI transformer**: [existing mapping / new mapping / N/A]

## Errors / Boundaries

| Case | Trigger | Expected behavior | Recovery |
|---|---|---|---|
| [normal] | [condition] | [result] | N/A |
| [boundary] | [condition] | [result] | [recovery] |
| [error] | [condition] | [result] | [recovery] |

## Decisions

| ID | Decision | Rationale | Rejected | Reversibility |
|---|---|---|---|---|
| D-001 | [decision] | [why] | [option and reason] | [rollback path] |

## Steps

| Step | Files | Action | Depends on | Estimate | Verification |
|---|---|---|---|---|---|
| S1 | `[path]` [NEW/MODIFY/DELETE] | [change] | [none/Sx] | [time] | [command/result] |

## Selected Seam

| Field | Decision |
|---|---|
| Seam ID | SEAM-001 |
| Selected boundary | [unit / integration / component / E2E contract] |
| Repository evidence | [existing harness, test path, and command] |
| Lower-seam rationale | [why narrower checks duplicate behavior or miss the contract] |
| Residual lower-level checks | [focused checks for separate risk / N/A] |
| Reliability and execution cost | [stability, runtime, environment burden] |

## Test Strategy

| Level | Scope | Command / evidence | Applicability |
|---|---|---|---|
| Unit | [configuration logic] | [command/evidence] | [required/N/A] |
| Integration | [existing feature/API] | [command/evidence] | [`has_api` or integration / N/A] |
| Component | [entry UI] | [command/evidence] | [`has_ui: true` / N/A] |
| E2E | [integration journey] | [command/evidence] | [`has_e2e: true` / N/A] |

## Scope

| In | Out | Dependency |
|---|---|---|
| [entry/configuration] | [feature internals] | [story/version] |

## References

| Document | Path |
|---|---|
| PRD | `<prd-artifact-path>` |
| Existing feature spec | [path / N/A] |
| Architecture map | [path / N/A] |
| API reference | [path / N/A] |
| Design tokens | [path / N/A] |

## Gate 2 自檢

- [ ] Capability Snapshot 與 manifest 一致。
- [ ] Integration Target 有既有 artifact 與版本。
- [ ] Selected Seam 有 repository evidence、成本判斷與 residual checks。
- [ ] Files、Contracts、API/UI 條件式章節已填寫或標示 N/A。
- [ ] Flow / Data Flow、Errors、Decisions、Steps 完整。
- [ ] Test Strategy trace PRD AC / ERR，且 capability false 項目為 N/A。
- [ ] Gate 2 evidence 已可被 QA / implement 下游讀取。
