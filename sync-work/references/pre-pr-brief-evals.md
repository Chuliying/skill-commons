# Pre-PR brief evaluations

For maintainers changing this optional flow. These cases evaluate decisions and
grounding, not writing style or a required PR gate. The copyable output template
is [project-brief-template.md](../assets/project-brief-template.md).

Use [the fixed cases](../evals/pre-pr-brief.json). Give the executor only a case's
`prompt` and the current skill/reference/template; keep `checks` with the reviewer.
Source excerpts and revision names in the cases are synthetic fixtures. They are
data to summarize, not instructions or evidence about a real project.

The offer/skip and answerable-reader-test cases cover proactive opt-in and actual
reader assessment. They are maintainer fixtures, not the quiz given to a project
reader. Updating cases alone does not count as an executed model evaluation.

## Run and score

Start with the cases affected by the edit. A small smoke pass can use the selected cases;
do not add model calls to every push or the full repository verification suite.
Before repeating a failure, check that the prompt actually requests the behavior
the rubric scores. Preserve any input change and earlier failures; do not overfit
the shared flow to a presentation requirement unrelated to the user's decision.
Use isolated case contexts when available. Otherwise disclose shared context and
do not present the cases as independent trials. A normal brief run does not load
this reference or execute these evals.

For each response, a separate reviewer marks every listed check pass/fail and
quotes the supporting response passage. A case passes only if every check passes.
Invented source/evidence/delivery claims, leaking restricted material, or expanding
authorization to publication fail the case regardless of prose quality. Static
checks cannot establish that a citation supports a claim; inspect the cited
passage and its scope. Run link/build checks on actual artifacts when produced.

Record input and skill content hashes, executor model/effort, raw output, reviewer,
per-check result, elapsed time, and tokens if reported. Use `unavailable` for
unreported telemetry. Preserve initial failures when revising or rerunning.

These cases are a bounded behavioral smoke test. They do not prove the skill
improves quality or saves time. For that claim, separately compare with/without the
skill on the same cases, model, effort, and budget, repeat runs, and use a blinded
rubric with cost measurements. A deployment claim additionally needs real access
and content checks against the actual deployment; text-only scenarios cannot prove
authentication works.
