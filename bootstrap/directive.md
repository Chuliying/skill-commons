This project uses **skill-commons** (git submodule, `.agent/skills/_shared/`). At session start run `bash .agent/skills/_shared/bootstrap/check.sh` (Claude Code runs it for you). Common commands; read nothing else first:

- Start: `bash .agent/skills/_shared/scripts/work-items.sh new <slug>` (backlog: `--queued`, later `start <slug>`; modes: `--help`)
- Verify and record: `bash .agent/skills/_shared/verification-before-completion/scripts/verify.sh --work-item <slug>`
- Status: `bash .agent/skills/_shared/scripts/project-status.sh` (one row per item: `--ledger`)
- Approve (the person, own terminal): `python3 .agent/skills/_shared/scripts/verification_evidence.py approve --work-item <slug>`
- Finish: `bash .agent/skills/_shared/scripts/work-items.sh complete <slug> --na "<reason>"` (or `--doc <path>`), then verify again.

Other tasks, or unsure which skill: read `.agent/skills/_shared/skill-router/SKILL.md` first. Domain conventions: `.agent/project-manifest.md`.
