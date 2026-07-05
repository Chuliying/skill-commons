# [功能名稱] 技術規格

**Story ID**: S-[PAGE]-[NN]
**Spec 版本**: v1.0.0
**對應 PRD**: `<prd-artifact-path>` @ v1.0.0
**Stage**: awaiting-approval | approved | ready

## Capability Snapshot

| Capability | Value | Evidence |
|---|---|---|
| `has_ui` | [true/false] | [path / command / N/A] |
| `has_api` | [true/false] | [path / command / N/A] |
| `typed_contracts` | [true/false] | [path / command / N/A] |
| `has_e2e` | [true/false] | [path / command / N/A] |

## Version History / 版本歷史

| Version | Updated at | Change | Impact | PRD version | Author |
|---|---|---|---|---|---|
| v1.0.0 | [YYYY-MM-DD HH:mm] | 初版 | [scope] | PRD v1.0.0 | [author] |

## Files

| Path | Operation | Purpose |
|---|---|---|
| `[path]` | NEW/MODIFY/DELETE | [change] |

## Contracts

### Data Contracts (`typed_contracts` conditional)

| Contract | Source | Shape / fields | Evidence |
|---|---|---|---|
| [name] | [types_entry / validator / N/A] | [definition or N/A] | [command result / N/A] |

### API Contract (`has_api` conditional)

| Operation | Request | Success response | Error response | Auth / permission |
|---|---|---|---|---|
| [operation or N/A] | [example or N/A] | [example or N/A] | [example or N/A] | [rule or N/A] |

### UI Design (`has_ui` conditional)

| Component / view | States | Interaction | Token evidence | Mockup evidence |
|---|---|---|---|---|
| [name or N/A] | [states or N/A] | [trigger/result or N/A] | [path/result or N/A] | [path/result or N/A] |

## Flow / Data Flow

```text
[input/event] -> [validation] -> [core logic] -> [output/side effect]
```

**API-to-UI transformer**: [name / mapping / N/A]

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

## Test Strategy

| Level | Scope | Command / evidence | Applicability |
|---|---|---|---|
| Unit | [logic/transformer] | [command] | [required/N/A] |
| Integration | [API/external service] | [command/evidence] | [`has_api` or external integration / N/A] |
| Component | [UI behavior] | [command/evidence] | [`has_ui: true` / N/A] |
| E2E | [journey] | [command/evidence] | [`has_e2e: true` / N/A] |

## References

| Document | Path |
|---|---|
| PRD | `<prd-artifact-path>` |
| Architecture map | [path / N/A] |
| API reference | [path / N/A] |
| Design tokens | [path / N/A] |

## Gate 2 自檢

- [ ] Capability Snapshot 與 manifest 一致。
- [ ] Files 覆蓋每個 FR 的實作影響。
- [ ] Contracts/API/UI 條件式章節已填寫或標示 N/A。
- [ ] Flow / Data Flow、Errors、Decisions、Steps 完整。
- [ ] Test Strategy trace PRD AC / ERR，且 capability false 項目為 N/A。
- [ ] Gate 2 evidence 已可被 QA / implement 下游讀取。
