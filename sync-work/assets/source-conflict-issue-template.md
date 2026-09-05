<!--
Use only after a material conflict between project sources is confirmed.
This is a draft shape, not a mandatory issue or a tracker-specific command.
Do not file synthetic evaluation conflicts.
-->

# Source conflict: <short, searchable title>

## Disposition

| Field | Value |
|---|---|
| Tracker convention / target | `<existing project convention and chosen target>` |
| Existing issue search | `<searched terms; matching issue or none found>` |
| Action | `draft only` / `update existing` / `create after authorization` / `decision needed` |
| Scope | `<candidate paths or documentation/code boundary>` |
| Disposition | `<owner, next decision, and whether dependent work is blocked>` |
| Issue URL | `<actual URL after tracker event, or not created>` |

## Conflicting evidence

Name both sources and resolve each revision or file hash. Do not replace either
statement with a clean-HEAD link when its source is dirty.

| Source | Path + section/symbol | Revision / file hash | Claim | Classification |
|---|---|---|---|---|
| A | `<path>` §<section/symbol> | `<resolved ref/hash>` | `<exact claim>` | intended contract / observed behavior |
| B | `<path>` §<section/symbol> | `<resolved ref/hash>` | `<exact claim>` | intended contract / observed behavior |

**Exact conflict:** <state the two claims without silently reconciling them>.  
**User impact:** <who is affected and what correctness, scope, or delivery risk follows>.

## Correction or decision

**Evidence status:** <what settles the conflict, what remains stale or inaccessible,
and which behavior was actually observed>.

If the evidence settles the answer and the authorized scope covers the edit:

- **Proposed correction:** <precise wording or patch, with affected paths>.
- **Why this is supported:** <source and fresh check>.

Otherwise:

- **Alternative A:** <clearly labeled interpretation or correction>.
- **Alternative B:** <clearly labeled interpretation or correction>.
- **Decision needed:** <owner choice and consequence>.

Do not declare the implementation automatically right or treat an intended document
as observed behavior. Preserve unresolved alternatives until the decision is made.

## Acceptance and verification

- **Acceptance criteria:** <observable correction or decision outcome>.
- **Affected check:** <existing check or documentation/link check that would detect regression>.
- **Evidence required:** <fresh result and scope; no cached PASS>.
- **Privacy handling:** <protected source link or sanitized excerpt; no raw/private logs>.

## Authorization boundary

Create or update the issue only for the explicitly chosen target, audience, and
content scope. Search and deduplicate using the existing tracker convention first;
never invent an issue URL. A user's explicit authorization for this chosen action
may be reused without repeated approval, but requesting a pre-PR brief alone is not
blanket tracker permission.

The issue may be tracked while an unrelated authorized push proceeds. Pause
dependent work only when the conflict creates a material correctness, scope, or
delivery-safety gap, or when actual authorization is missing. The owner or root
agent selects the target and performs the external tracker action; this draft does
not create, update, publish, or broaden the issue.
