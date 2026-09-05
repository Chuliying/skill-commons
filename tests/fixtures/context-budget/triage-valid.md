# Context mandate triage fixture

Entries are keyed by source content. The meter resolves each quoted line in the
named source file; line numbers are deliberately absent so section moves do not
invalidate the entry.

| source | quote | class | reason |
|---|---|---|---|
| AGENTS.md | - 每個任務先讀 `skill-router/SKILL.md`，再依 router 載入技能。 | keep | repository-local routing fact |
| tests/fixtures/brainstorming-routing.tsv | # Contract fixture only; does not prove model trigger accuracy, token savings, duration, or output quality. | gate | fixture scope is machine-checkable |
| skill-router/SKILL.md | 1. 持久狀態與交接結果落檔，不能只存在對話 context。 | drop | generic durability guidance for the triage fixture |
