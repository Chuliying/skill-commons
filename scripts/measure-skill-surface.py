#!/usr/bin/env python3
"""Reproduce the frozen and checkpointed skill-bundle convergence metrics."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path


BASELINE = {
    "default_installed_skills": 13,
    "personal_installed_skills": 13,
    "router_bytes": 6747,
    "micro_route_bytes": 17411,
    "default_skill_bytes": 82468,
    "core_source": {"files": 43, "lines": 6469, "bytes": 222308},
    "generated_core": {"files": 129, "lines": 19407, "bytes": 666924},
    "support": {"files": 57, "lines": 9329, "bytes": 424695},
    "profile_registry": {"files": 2, "lines": 312, "bytes": 6352},
    "physical": {"files": 231, "lines": 35517, "bytes": 1320279},
}

T04_CHECKPOINT = {
    "default_installed_skills": 8,
    "router_bytes": 6722,
    "micro_route_bytes": 17386,
    "default_skill_bytes": 55344,
    "core_source": {"files": 28, "lines": 4570, "bytes": 153354},
    "generated_core": {"files": 84, "lines": 13710, "bytes": 460062},
    "support": {"files": 62, "lines": 10499, "bytes": 483900},
    "physical": {"files": 176, "lines": 29086, "bytes": 1103600},
}

T05_CHECKPOINT = {
    "default_installed_skills": 8,
    "router_bytes": 6708,
    "micro_route_bytes": 17372,
    "default_skill_bytes": 58966,
    "core_source": {"files": 28, "lines": 4616, "bytes": 156976},
    "generated_core": {"files": 84, "lines": 13848, "bytes": 470928},
    "support": {"files": 62, "lines": 10688, "bytes": 493154},
    "profile_registry": {"files": 2, "lines": 307, "bytes": 6284},
    "physical": {"files": 176, "lines": 29459, "bytes": 1127342},
}

T06_CHECKPOINT = {
    "default_installed_skills": 7,
    "router_bytes": 6708,
    "micro_route_bytes": 17372,
    "default_skill_bytes": 48542,
    "core_source": {"files": 25, "lines": 4132, "bytes": 140886},
    "generated_core": {"files": 75, "lines": 12396, "bytes": 422658},
    "support": {"files": 62, "lines": 10774, "bytes": 498365},
    "profile_registry": {"files": 2, "lines": 306, "bytes": 6253},
    "physical": {"files": 164, "lines": 27608, "bytes": 1068162},
}


@dataclass(frozen=True)
class Surface:
    files: int = 0
    lines: int = 0
    bytes: int = 0

    def __add__(self, other: "Surface") -> "Surface":
        return Surface(
            self.files + other.files,
            self.lines + other.lines,
            self.bytes + other.bytes,
        )

    def times(self, multiplier: int) -> "Surface":
        return Surface(
            self.files * multiplier,
            self.lines * multiplier,
            self.bytes * multiplier,
        )

    def as_dict(self) -> dict[str, int]:
        return {"files": self.files, "lines": self.lines, "bytes": self.bytes}


def file_surface(paths: list[Path]) -> Surface:
    result = Surface()
    for path in sorted(paths):
        data = path.read_bytes()
        result += Surface(files=1, lines=data.count(b"\n"), bytes=len(data))
    return result


def tree_files(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    return [
        path
        for path in root.rglob("*")
        if path.is_file() and path.name != ".DS_Store"
    ]


def profile_tokens(path: Path) -> list[str]:
    tokens: list[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        token = raw_line.split("#", 1)[0].strip()
        if token:
            tokens.append(token)
    return tokens


def resolve_profile(
    root: Path,
    name: str,
    core_profile: Path,
    stack: tuple[str, ...] = (),
) -> set[str]:
    if name in stack:
        raise ValueError(f"profile include cycle: {' -> '.join((*stack, name))}")
    path = core_profile if name == "core" else root / "profiles" / name
    result: set[str] = set()
    for token in profile_tokens(path):
        if token.startswith("@"):
            result.update(resolve_profile(root, token[1:], core_profile, (*stack, name)))
        else:
            result.add(token)
    return result


def measure(root: Path, core_profile: Path) -> tuple[dict[str, object], list[str]]:
    errors: list[str] = []
    core = resolve_profile(root, "core", core_profile)
    personal = resolve_profile(root, "personal", core_profile)
    team = resolve_profile(root, "team-sprint", core_profile)
    optional = resolve_profile(root, "optional", core_profile)

    for name in sorted(core):
        if not (root / name / "SKILL.md").is_file():
            errors.append(f"core owner is missing top-level source: {name}")

    core_source = file_surface(
        [path for name in core for path in tree_files(root / name)]
    )
    generated_core = file_surface(
        [
            path
            for generated_root in (".claude/skills", ".codex/skills", ".agents/skills")
            for name in core
            for path in tree_files(root / generated_root / name)
        ]
    )
    support = file_surface(tree_files(root / "tests") + tree_files(root / "scripts"))
    profile_registry = file_surface([core_profile, root / "protocol-registry.json"])
    physical = core_source + generated_core + support + profile_registry

    default_skills = file_surface([root / name / "SKILL.md" for name in core])
    router_bytes = (root / "skill-router/SKILL.md").stat().st_size
    micro_route_bytes = sum(
        (root / name / "SKILL.md").stat().st_size
        for name in (
            "skill-router",
            "implement",
            "verification-before-completion",
        )
    )

    expected_generated = core_source.times(3)
    if generated_core != expected_generated:
        errors.append(
            "generated core surface does not equal three source mirrors: "
            f"expected={expected_generated.as_dict()} actual={generated_core.as_dict()}"
        )

    current: dict[str, object] = {
        "default_installed_skills": len(core),
        "personal_installed_skills": len(personal),
        "team_sprint_installed_skills": len(team),
        "optional_capabilities": len(optional),
        "router_bytes": router_bytes,
        "micro_route_bytes": micro_route_bytes,
        "default_skill_bytes": default_skills.bytes,
        "default_skill_lines": default_skills.lines,
        "core_source": core_source.as_dict(),
        "generated_core": generated_core.as_dict(),
        "support": support.as_dict(),
        "profile_registry": profile_registry.as_dict(),
        "physical": physical.as_dict(),
    }

    thresholds = (
        (len(core) < BASELINE["default_installed_skills"], "default installed skill count is not lower than 13"),
        (router_bytes < BASELINE["router_bytes"], "Router bytes are not lower than 6747"),
        (micro_route_bytes < BASELINE["micro_route_bytes"], "micro-route bytes are not lower than 17411"),
        (default_skills.bytes < BASELINE["default_skill_bytes"], "default SKILL bytes are not lower than 82468"),
        (physical.files <= BASELINE["physical"]["files"], "physical files exceed 231"),
        (physical.bytes < BASELINE["physical"]["bytes"], "physical bytes are not lower than 1320279"),
    )
    errors.extend(message for passed, message in thresholds if not passed)
    result = {
        "baseline": BASELINE,
        "t04_checkpoint": T04_CHECKPOINT,
        "t05_checkpoint": T05_CHECKPOINT,
        "t06_checkpoint": T06_CHECKPOINT,
        "current": current,
        "status": "PASS" if not errors else "FAIL",
    }
    return result, errors


def delta(current: int, baseline: int) -> str:
    return f"{current - baseline:+,d}"


def surface_delta(current: dict[str, int], baseline: dict[str, int]) -> str:
    return (
        f"{delta(current['files'], baseline['files'])} files / "
        f"{delta(current['lines'], baseline['lines'])} lines / "
        f"{delta(current['bytes'], baseline['bytes'])} bytes"
    )


def markdown(result: dict[str, object]) -> str:
    baseline = result["baseline"]
    t06 = result["t06_checkpoint"]
    current = result["current"]
    rows = (
        ("Default installed skills", "default_installed_skills"),
        ("Router bytes", "router_bytes"),
        ("Router + Implement + Verification bytes", "micro_route_bytes"),
        ("Default SKILL bytes", "default_skill_bytes"),
    )
    surface_rows = (
        ("Core source", "core_source"),
        ("Three generated core mirrors", "generated_core"),
        ("Tests + scripts", "support"),
        ("Core profile + registry", "profile_registry"),
        ("Frozen physical aggregate", "physical"),
    )
    output = [
        "# T07 final deterministic surface inventory",
        "",
        "Generated by `python3 scripts/measure-skill-surface.py --format markdown`.",
        "Counts use raw bytes, newline counts equivalent to `wc -l`, regular files",
        "excluding `.DS_Store`, the resolved `profiles/core` source trees, their three",
        "generated mirrors, all `tests/` and `scripts/`, and `profiles/core` plus",
        "`protocol-registry.json`. The aggregate sums those four sets without",
        "deduplication. Default instruction bytes count only core `SKILL.md` files.",
        "",
        f"Status: **{result['status']}**",
        "",
        "## Installed and instruction surface",
        "",
        "| Metric | Frozen baseline | T07 final current | Delta |",
        "|---|---:|---:|---:|",
    ]
    for label, key in rows:
        output.append(
            f"| {label} | {baseline[key]:,} | {current[key]:,} | "
            f"{delta(current[key], baseline[key])} |"
        )
    output.extend(
        [
            f"| Personal installed skills | {baseline['personal_installed_skills']:,} | {current['personal_installed_skills']:,} | {delta(current['personal_installed_skills'], baseline['personal_installed_skills'])} |",
            f"| Team-sprint installed skills | n/a | {current['team_sprint_installed_skills']:,} | n/a |",
            f"| Optional capabilities | n/a | {current['optional_capabilities']:,} | n/a |",
            "",
            "## Physical surface",
            "",
            "| Metric | Baseline files / lines / bytes | T07 final files / lines / bytes | Byte delta |",
            "|---|---:|---:|---:|",
        ]
    )
    for label, key in surface_rows:
        old = baseline[key]
        new = current[key]
        output.append(
            f"| {label} | {old['files']:,} / {old['lines']:,} / {old['bytes']:,} | "
            f"{new['files']:,} / {new['lines']:,} / {new['bytes']:,} | "
            f"{delta(new['bytes'], old['bytes'])} |"
        )
    output.extend(
        [
            "",
            "## Accepted T06 checkpoint → T07 final",
            "",
            "| Metric | Accepted T06 | T07 final current | Delta |",
            "|---|---:|---:|---:|",
            f"| Default installed skills | {t06['default_installed_skills']:,} | {current['default_installed_skills']:,} | {delta(current['default_installed_skills'], t06['default_installed_skills'])} |",
            f"| Router bytes | {t06['router_bytes']:,} | {current['router_bytes']:,} | {delta(current['router_bytes'], t06['router_bytes'])} |",
            f"| Router + Implement + Verification bytes | {t06['micro_route_bytes']:,} | {current['micro_route_bytes']:,} | {delta(current['micro_route_bytes'], t06['micro_route_bytes'])} |",
            f"| Default SKILL bytes | {t06['default_skill_bytes']:,} | {current['default_skill_bytes']:,} | {delta(current['default_skill_bytes'], t06['default_skill_bytes'])} |",
            f"| Core source | {t06['core_source']['files']:,} / {t06['core_source']['lines']:,} / {t06['core_source']['bytes']:,} | {current['core_source']['files']:,} / {current['core_source']['lines']:,} / {current['core_source']['bytes']:,} | {surface_delta(current['core_source'], t06['core_source'])} |",
            f"| Three generated core mirrors | {t06['generated_core']['files']:,} / {t06['generated_core']['lines']:,} / {t06['generated_core']['bytes']:,} | {current['generated_core']['files']:,} / {current['generated_core']['lines']:,} / {current['generated_core']['bytes']:,} | {surface_delta(current['generated_core'], t06['generated_core'])} |",
            f"| Tests + scripts | {t06['support']['files']:,} / {t06['support']['lines']:,} / {t06['support']['bytes']:,} | {current['support']['files']:,} / {current['support']['lines']:,} / {current['support']['bytes']:,} | {surface_delta(current['support'], t06['support'])} |",
            f"| Core profile + registry | {t06['profile_registry']['files']:,} / {t06['profile_registry']['lines']:,} / {t06['profile_registry']['bytes']:,} | {current['profile_registry']['files']:,} / {current['profile_registry']['lines']:,} / {current['profile_registry']['bytes']:,} | {surface_delta(current['profile_registry'], t06['profile_registry'])} |",
            f"| Physical aggregate | {t06['physical']['files']:,} / {t06['physical']['lines']:,} / {t06['physical']['bytes']:,} | {current['physical']['files']:,} / {current['physical']['lines']:,} / {current['physical']['bytes']:,} | {surface_delta(current['physical'], t06['physical'])} |",
            "",
            "The T07 final checkpoint retains seven installed owners. `sync-work` is the",
            "sole Git-delivery owner; security, implementation, root-cause debugging, and",
            "fresh verification remain distinct.",
            "",
            "The deterministic thresholds establish profile and repository surface only.",
            "They make no effectiveness, quality, usability, human-effort, or USD-cost claim.",
            "A bounded diff review must still reject equivalent control logic relocated",
            "outside the measured sets.",
        ]
    )
    return "\n".join(output)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--core-profile", type=Path)
    parser.add_argument("--format", choices=("text", "json", "markdown"), default="text")
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    core_profile = (args.core_profile or root / "profiles/core").resolve()
    try:
        result, errors = measure(root, core_profile)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.format == "json":
        print(json.dumps(result, indent=2, sort_keys=True))
    elif args.format == "markdown":
        print(markdown(result))
    else:
        current = result["current"]
        print(
            f"Skill surface: status={result['status']} core={current['default_installed_skills']} "
            f"router={current['router_bytes']} micro={current['micro_route_bytes']} "
            f"default={current['default_skill_bytes']} physical_files={current['physical']['files']} "
            f"physical_bytes={current['physical']['bytes']}"
        )
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
    return 1 if args.check and errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
