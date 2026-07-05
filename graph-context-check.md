# Graph Context Check

Run this check before any task that needs file, module, caller/callee, or impact
analysis.

## Check

1. Check whether `.understand-anything/knowledge-graph.json` exists.
   - If it exists and is recent, read only the graph summary needed for the
     current task.
   - If it exists but is older than 7 days, treat it as stale. Tell the user that
     a new `codebase-understanding` run may be needed. If the user does not rerun
     it, fall back to repository files and search.
   - If it does not exist, fall back to `rg`, `grep`, and direct file reading.
     Do not start Understand-Anything unless the current task explicitly uses
     `codebase-understanding`.

2. If the task needs git diff impact analysis and `/understand-diff` is
   available, use it to create a diff overlay. If it is unavailable, use the
   existing graph summary plus `git diff` and repository search.

3. Load only the graph context required for the task:
   - find the relevant file, symbol, route, or module node;
   - read directly adjacent incoming and outgoing edges;
   - avoid loading the full graph into context.

4. If the graph conflicts with the current files, trust the current files.

## Applies to

- `caveman-review`: inspect module boundaries and impact radius.
- `plan-sync`: assess implementation and test path impact.
- `systematic-debugging`: trace callers, callees, and data flow.
- `spec`: find similar implementations and related files.
- `codebase-understanding`: support focused architecture analysis.
- `shared-skill-onboarder`: support repeated module pattern discovery.

## Required output

In the calling skill's report, include a short status line:

```text
Graph Context: [used / understand-diff used / missing -> rg fallback / stale -> rg fallback / skipped]
```
