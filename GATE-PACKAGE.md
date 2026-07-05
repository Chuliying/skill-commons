# Gate Package Convention

Every human approval presents one compact package. The package belongs in the canonical artifact or closeout report so a new session can reconstruct what was approved.

## Changes since previous Gate

List only material changes since the previous approved state. For the first Gate, summarize the proposed scope.

## Evidence checklist

Map each decision criterion to a file, command output, traceability result, or explicit `N/A`. A bare PASS is not evidence.

## Risks and open questions

State unresolved tradeoffs, accepted gaps, rollback cost, and the consequence of waiting. Use `none` only after checking.

## Decision options

Offer concrete choices such as approve, request named changes, or stop. Record the chosen option and update `meta.yml` from `awaiting-approval` to `approved`; conversation text alone does not change state.
