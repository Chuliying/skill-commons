# Skill Commons Submodule Bridge

This document describes the expected way to mount `skill-commons` into a
consuming repository as a Git submodule.

## Goal

Use `skill-commons` as the shared workflow source while keeping project-specific
rules in the consuming repository.

The intended layout is:

```text
.agent/
├── project-manifest.md
├── guardrails.md
└── skills/
    ├── _shared/   # skill-commons submodule
    └── project/   # optional project-specific domain skills
```

## Install

```bash
git submodule add git@github.com:Chuliying/skill-commons.git .agent/skills/_shared
git -C .agent/skills/_shared checkout v0.5.0
bash .agent/skills/_shared/bootstrap/onboard.sh
```

The tag pin keeps the consuming repository on a reviewed workflow version.
Update the tag intentionally; do not follow `main` automatically.

## What onboarding creates

`bootstrap/onboard.sh` is idempotent. It creates or updates only the
skill-commons managed blocks and generated skill roots for the requested
platforms.

On a fresh repository it creates conservative defaults:

- `.agent/project-manifest.md`
- `.agent/guardrails.md`
- agent shims such as `AGENTS.md`, `CLAUDE.md`, Cursor rules, or Codex skill
  roots depending on the detected or configured platforms

Existing manifest and guardrail files are not overwritten.

## After onboarding

Ask the agent to inspect the consuming repository before starting feature work:

```text
Read `.agent/skills/_shared/shared-skill-onboarder/SKILL.md`.
Run Scan mode. Use repository evidence only. Report fields that cannot be
confirmed from the repo instead of guessing.
```

The scan should refine:

- paths for source, tests, docs, and work items;
- stack commands for test, lint, typecheck, and E2E where available;
- capability flags such as `has_ui`, `has_api`, `typed_contracts`, and `has_e2e`;
- Git workflow defaults;
- candidate project-specific domain skills.

## Validate

Use the generated check script when present:

```bash
bash .agent/skills/_shared/bootstrap/check.sh
```

For a stronger local check, run the consuming repository's own test, lint, and
typecheck commands from `.agent/project-manifest.md`.

Do not assume every consuming repository has an npm-based manifest validator.

## Update

```bash
git -C .agent/skills/_shared fetch --tags
git -C .agent/skills/_shared checkout <reviewed-tag>
bash .agent/skills/_shared/bootstrap/onboard.sh
bash .agent/skills/_shared/bootstrap/check.sh
```

Commit the submodule pointer change together with any intentional updates to the
consuming repository's manifest or guardrails.

## Troubleshooting

- If the submodule is missing after clone, run:

  ```bash
  git submodule update --init --recursive
  ```

- If skills cannot be resolved, confirm that
  `.agent/skills/_shared/skill-router/SKILL.md` exists.
- If onboarding reports drift, rerun `bootstrap/onboard.sh` from the pinned tag.
- If repository-specific behavior is still unknown, rerun
  `shared-skill-onboarder` Scan mode and update the manifest from evidence.
