# [功能名稱] QA 方案

**PRD**: `<prd-artifact-path>` v1.0.0
**Spec**: `<spec-artifact-path>`
**Capabilities**: `has_ui=[true/false]` · `has_api=[true/false]` · `typed_contracts=[true/false]` · `has_e2e=[true/false]`

---

## Selected Seam

| Field | Decision |
|---|---|
| Spec seam ID | [SEAM-001] |
| Spec reference | [spec.md#selected-seam] |

---

## 1. Traceability

| Source | Behavior / Risk | Test ID | Level | Evidence |
|--------|-----------------|---------|-------|----------|
| AC-001 | [observable behavior] | TC-001 | [L2/L3/L4/L5] | [command or planned evidence] |
| ERR-001 | [failure and recovery] | TC-ERR01 | [level] | [command or planned evidence] |

---

## 2. Test Cases

### TC-001: [behavior title]

**Source**: AC-001 / spec: [module or contract]
**Level**: L2 / L3 / L4 / L5
**Applicability**: [capability condition or always]
**Precondition**: [data, auth, environment]
**Steps**:

```text
Given [controlled precondition]
When [action]
Then [observable result]
```

**Implementation notes**: [repo test file, helper, mock, or N/A]

### TC-ERR01: [error title]

**Source**: ERR-001
**Level**: [level]
**Precondition**: [controlled failure condition]
**Steps**:

```text
Given [system is in recoverable state]
When [failure is triggered]
Then [expected behavior and recovery path are observable]
```

---

## 3. Boundary Tests

| Test ID | Boundary | Expected behavior | Source |
|---------|----------|-------------------|--------|
| TC-B01 | [edge case] | [observable result] | FR-001 / AC-001 |

---

## 4. Capability-specific Tests

| Capability | Required tests | Evidence |
|------------|----------------|----------|
| `has_ui` | L3 component or L5 UI flow, UI states, mockup/token checks | [N/A or command/path] |
| `has_api` | L4 integration contract with controlled service or fixture | [N/A or command/path] |
| `typed_contracts` | typecheck or contract validator | [N/A or command/path] |
| `has_e2e` | complete journey when selected or required for a distinct residual risk | [N/A or command/path] |

---

## 5. Test Matrix

| Level | Scope | Count | Command / Evidence |
|-------|-------|------:|--------------------|
| L2 Unit | [core logic / transformer] | [n] | [manifest test_cmd] |
| L3 Component | [UI component] / N/A | [n] | [repo command or N/A] |
| L4 Integration | [API/external service] / N/A | [n] | [repo command or N/A] |
| L5 E2E | [journey] / N/A | [n] | [manifest e2e_cmd or N/A] |

---

## 6. Mock / Fixture Plan

| Dependency | Strategy | Contract source |
|------------|----------|-----------------|
| [dependency] | [controlled fixture / fake / test environment] | spec / API reference / N/A |

---

## Machine traceability gate

- [ ] Every PRD AC maps to at least one test.
- [ ] Every PRD ERR maps to at least one error or recovery test.
- [ ] Every test has a source ID and level.
- [ ] Capability-disabled sections are marked N/A rather than filled with fake assets.
- [ ] Mock or fixture data follows the Spec/API contract.
- [ ] Representative test evidence is executable or has a concrete command.

---

## Related Documents

| Document | Link |
|----------|------|
| PRD | `<prd-artifact-path>` |
| Spec | `<spec-artifact-path>` |
