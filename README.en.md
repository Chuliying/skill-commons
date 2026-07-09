# skill-commons

**skill-commons makes AI-agent development output repeatable, reviewable, and resumable.** It fixes the shape of the software delivery flow: requirement, spec, plan, implementation, verification, and release each produce a shape-consistent, resumable, script-verifiable artifact that survives a change of session, model, or agent — addressing the three worst failure modes of agent development: inconsistent output shape, "done" without evidence, and losing everything when the conversation resets. It is a set of engineering workflow skills installable across Claude Code, Codex, and Cursor; v0.6.0 is the public beta, with automated validation covering Python CLI and TypeScript/Web fixtures.

The skills remain zh-TW single-source. This page summarizes the positioning, design intent, and setup path for non-Chinese readers.

## Design intent

One line: fix the shape of the flow so every output is shape-consistent, resumable, and script-verifiable. Three principles constrain its behavior:

- **Durable state and evidence.** LLM context is volatile, so persistent state lives in `docs/work/<slug>/`, `meta.yml`, and plan-sync memory and survives a new session; models claim success without evidence, so every Gate and verification-before-completion demands direct proof.
- **Safety and division of labor.** Irreversible operations (push, merge, delete) apply guardrails first, with sync-work and Recovery Mode controlling boundaries; human review focuses on judgment (requirements, design trade-offs, release and merge), while scripts handle mechanical checks.
- **Right-sized, not over-built.** Contracts appear only at handoffs (team profile produces formal PRD, Spec, QA; personal uses snapshots and lightweight plans); Gate density follows `min(rework cost, operator debugging ability)`.

## Requirements and Quick Start

Requirements: git with submodule support, bash 4+, `jq`, Node.js 18+ for onboarding scans, and optional Python 3.10+ for plan-sync scripts or markitdown. Node.js and Python are required to maintain and fully verify this repository.

```bash
git submodule add git@github.com:Chuliying/skill-commons.git .agent/skills/_shared
git -C .agent/skills/_shared checkout v0.6.0
bash .agent/skills/_shared/bootstrap/onboard.sh
```

This tag pin keeps consuming repositories on a reviewed workflow version. Then ask the agent to read `shared-skill-onboarder/SKILL.md` and run its Scan mode. See the [zh-TW README](README.md) for profiles, Gate definitions, troubleshooting, and the trigger reference.
