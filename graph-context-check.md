# Graph Context Check

Run this check before work that needs repository-wide file, module-reference, or
change-scope evidence.

## Check

1. Locate the active `codebase-understanding` skill and its
   `scripts/repo_map.py`. If it is not installed, use repository search and
   direct file reading.

2. Run `status --root <repo-relative-scope>` and parse its compact JSON. The
   JSON state is authoritative; exit code 1 covers both `missing` and `stale`
   and does not distinguish them by itself.

3. Handle state and coverage:

   - `fresh`: use only the inventory/module-reference evidence covered by the
     reported coverage.
   - `missing` or `stale`: when the task explicitly uses
     `codebase-understanding` and the scan cost is justified, run `scan`;
     otherwise use `rg` and direct reading.
   - `corrupt` or `incompatible`: rebuild once when appropriate, then
     fallback if the error remains.
   - `partial` or `inventory_only`: preserve the cache evidence, and use
     search/direct reading for unsupported or unresolved questions.
   - operational `error`: report it and fallback.

4. Load only relevant records. Repo Map edges are `module_reference`
   candidates, not resolved dependencies, callers/callees, or impact claims.

5. If cached evidence conflicts with current files, trust current files.

## Applies to

- `caveman-review`: inspect module boundaries and change scope.
- `plan-sync`: identify implementation and test paths.
- `systematic-debugging`: find candidate related modules before direct tracing.
- `spec`: find similar implementations and related files.
- `codebase-understanding`: support focused architecture analysis.
- `shared-skill-onboarder`: support repeated module pattern discovery.

## Required output

In the calling skill's report, include one canonical status line:

```text
Graph Context: source=<repo-map|search> state=<fresh|missing|stale|corrupt|incompatible|error|not-run> coverage=<complete|partial|inventory_only|unknown> fallback=<none|rg|direct-reading>
```

This fragment is the only owner of the Graph Context vocabulary. Calling skills
keep the line in their checklist but do not copy its allowed-values list.
