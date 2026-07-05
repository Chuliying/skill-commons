# skill-commons

skill-commons is a set of engineering workflow skills that can be installed across Claude Code, Codex, and Cursor. It defines repeatable procedures for requirement capture, technical specification, planning, implementation, verification, and release preflight checks. v0.5.0 is the public beta; automated validation currently covers Python CLI and TypeScript/Web fixtures.

The skills remain zh-TW single-source. This page summarizes the positioning, design intent, and setup path for non-Chinese readers.

## Design intent

1. LLM context is volatile, so durable state lives in `docs/work/<slug>/`, `meta.yml`, and plan-sync artifacts.
2. Models can claim success without evidence, so verification and machine-readable Gate evidence are mandatory.
3. Irreversible operations need explicit boundaries and confirmation before push, merge, or deletion.
4. Human review should focus on judgment calls; scripts handle mechanical checks while people approve product intent, team design trade-offs, and release readiness.
5. Contract density follows handoff needs: team work uses PRD, Spec, and QA artifacts; personal work uses snapshots and lightweight plans.
6. Gate density follows `min(rework cost, operator debugging ability)`, so non-engineering prototype flows retain more checkpoints.

## Requirements and Quick Start

Requirements: git with submodule support, bash 4+, `jq`, Node.js 18+ for onboarding scans, and optional Python 3.10+ for plan-sync scripts or markitdown. Node.js and Python are required to maintain and fully verify this repository.

```bash
git submodule add git@github.com:Chuliying/skill-commons.git .agent/skills/_shared
git -C .agent/skills/_shared checkout v0.5.0
bash .agent/skills/_shared/bootstrap/onboard.sh
```

This tag pin keeps consuming repositories on a reviewed workflow version. Then ask the agent to read `shared-skill-onboarder/SKILL.md` and run its Scan mode. See the [zh-TW README](README.md) for profiles, Gate definitions, troubleshooting, and the trigger reference.
