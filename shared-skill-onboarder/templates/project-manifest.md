# Project Manifest

## skill-commons bootstrap

- submodule_path: .agent/skills/_shared
- platforms: claude-code, codex
<!-- onboard.sh replaces this with the agents it finds (.claude, .codex, .cursor) when it creates the manifest. -->
- delivery_mode: personal
- capability_packs: optional
<!-- Default since 2026-10-29: optional is included so a fresh install can run the full flow
     (to-prd, discovery, review, onboarding). Remove it for the smallest skill set
     (direct form: CAPABILITY_PACKS=optional). -->

## Paths

<!-- TODO: discover and record project document, source, test, and work-item paths. -->

## Stack

<!-- TODO: discover the project's typecheck, lint, and test commands. -->
- has_ui: false
- has_api: false
- typed_contracts: false
- has_e2e: false

## Git Workflow

<!-- TODO: record the default branch, integration policy, and protected operations. -->
<!-- Optional: add `- sprint_tracking: true` only when PRDs must belong to a Sprint. -->
