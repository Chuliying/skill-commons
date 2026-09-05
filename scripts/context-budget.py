#!/usr/bin/env python3
"""Measure the repository-owned context surface.

The source checkout is the authority for this report.  In particular, this
module never walks generated adapter roots when it inventories skills and it
parses multiline frontmatter descriptions without importing a YAML dependency.
"""

from __future__ import annotations

import argparse
import itertools
import json
import re
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


DESCRIPTION_START = re.compile(r"^description\s*:\s*(.*)$")
FRONTMATTER_KEY = re.compile(r"^[A-Za-z0-9_.-]+\s*:")
MANDATE_CANDIDATE = re.compile(
    r"必須|不得|禁止|\bMUST\b|\bNEVER\b|\bABSOLUTELY\b"
)
TRIAGE_CLASSES = ("drop", "keep", "gate")
ENTRY_PATHS = {
    "claude-code": "CLAUDE.md",
    "codex": "AGENTS.md",
    "cursor": "bootstrap/directive.md",
}
EXCLUDED = (
    ("_archive/", "retired or historical source; outside the live skill surface"),
    (".claude/", "generated Claude adapter output; source is top-level skills"),
    (".codex/", "generated Codex adapter output; source is top-level skills"),
    (".agents/", "generated generic-agent adapter output; source is top-level skills"),
)


def byte_size(path: Path) -> int:
    return len(path.read_bytes())


def line_count(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").splitlines())


def clean_profile_line(line: str) -> str:
    return line.split("#", 1)[0].strip()


def resolve_profile(root: Path, profile_file: str, stack: Optional[Tuple[str, ...]] = None) -> List[str]:
    """Expand a profile file and its @includes into skill names."""

    stack = stack or ()
    if profile_file in stack:
        cycle = " -> ".join((*stack, profile_file))
        raise ValueError(f"profile include cycle: {cycle}")
    path = root / profile_file
    if not path.is_file():
        raise ValueError(f"profile file missing: {profile_file}")
    names: List[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = clean_profile_line(raw_line)
        if not line:
            continue
        if line.startswith("@"):
            include_name = line[1:]
            names.extend(resolve_profile(root, f"profiles/{include_name}", (*stack, profile_file)))
        else:
            names.append(line)
    return names


def parse_frontmatter_description(path: Path) -> str:
    """Return the complete description value from a simple YAML frontmatter block.

    The repository frontmatter uses plain scalars and literal/folded block
    scalars.  The parser intentionally preserves the source's line content so
    the meter does not silently charge only the first multiline description.
    """

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return ""
    end = None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            end = index
            break
    if end is None:
        return ""

    for index in range(1, end):
        match = DESCRIPTION_START.match(lines[index].rstrip("\r\n"))
        if not match:
            continue
        value = match.group(1).strip()
        if value not in ("|", ">", "|-", ">-", "|+", ">+"):
            return value

        folded = value.startswith(">")
        block: List[str] = []
        cursor = index + 1
        while cursor < end:
            raw = lines[cursor]
            # A non-indented frontmatter key closes a block scalar. Blank lines
            # remain part of it, including their newline when present.
            if raw.strip() and not raw[:1].isspace():
                break
            content = raw[2:] if raw.startswith("  ") else raw.lstrip("\t")
            block.append(content)
            cursor += 1
        if folded:
            # YAML folded scalars turn ordinary line breaks into spaces while
            # retaining paragraph breaks. This is sufficient for byte accounting
            # and avoids the first-line-only undercount from the visualizer.
            pieces: List[str] = []
            for item in block:
                if item.strip() == "":
                    pieces.append("\n")
                else:
                    if pieces and pieces[-1] not in (" ", "\n"):
                        pieces.append(" ")
                    pieces.append(item.rstrip("\r\n"))
            return "".join(pieces)
        return "".join(block)
    return ""


def top_level_skills(root: Path) -> List[Path]:
    """List live top-level skill files only, including maintainer skill-creator."""

    excluded_dirs = {"_archive", ".claude", ".codex", ".agents", "docs", "tests", "scripts", "bootstrap", "profiles", "node_modules"}
    paths: List[Path] = []
    for child in root.iterdir():
        if child.name.startswith(".") or child.name in excluded_dirs or not child.is_dir():
            continue
        skill = child / "SKILL.md"
        if skill.is_file():
            paths.append(skill)
    return sorted(paths, key=lambda p: (-byte_size(p), p.parent.name))


def read_profiles(root: Path) -> Tuple[dict, Dict[str, List[str]], Dict[str, List[str]]]:
    model_path = root / "profiles.json"
    if not model_path.is_file():
        raise ValueError(f"profiles.json missing: {model_path}")
    model = json.loads(model_path.read_text(encoding="utf-8"))
    modes = model.get("delivery_modes", {})
    packs = model.get("capability_packs", {})
    if not isinstance(modes, dict) or not isinstance(packs, dict):
        raise ValueError("profiles.json delivery_modes/capability_packs must be objects")

    mode_skills: Dict[str, List[str]] = {}
    for name, record in modes.items():
        mode_skills[name] = sorted(set(resolve_profile(root, record["profile_file"])))
    pack_skills: Dict[str, List[str]] = {}
    for name, record in packs.items():
        pack_skills[name] = sorted(set(resolve_profile(root, record["profile_file"])))
    return model, mode_skills, pack_skills


def selection_rows(root: Path, model: dict, mode_skills: Dict[str, List[str]], pack_skills: Dict[str, List[str]]) -> List[dict]:
    platforms = model.get("platforms", {})
    pack_names = sorted(pack_skills)
    rows: List[dict] = []
    selections: List[Tuple[str, Tuple[str, ...], List[str], str]] = []
    for mode in sorted(mode_skills):
        for count in range(len(pack_names) + 1):
            for packs in itertools.combinations(pack_names, count):
                names = set(mode_skills[mode])
                for pack in packs:
                    names.update(pack_skills[pack])
                selections.append((mode, packs, sorted(names), "consumer"))
    # `PROFILE=all` is a generator/maintainer selection. It deliberately drops
    # skill-creator because generate.sh treats that owner as maintainer-only.
    all_names = sorted(
        p.parent.name for p in top_level_skills(root) if p.parent.name != "skill-creator"
    )
    selections.append(("all", tuple(), all_names, "maintainer-ceiling"))

    router = root / "skill-router/SKILL.md"
    registry = root / "protocol-registry.json"
    required_files = (router, registry)
    for required in required_files:
        if not required.is_file():
            raise ValueError(f"required context source missing: {required}")
    router_bytes = byte_size(router)
    router_lines = line_count(router)
    registry_bytes = byte_size(registry)
    registry_lines = line_count(registry)

    for platform, platform_record in platforms.items():
        if platform not in ENTRY_PATHS:
            raise ValueError(f"no entry-file mapping for platform: {platform}")
        entry_path = ENTRY_PATHS[platform]
        entry = root / entry_path
        if not entry.is_file():
            raise ValueError(f"required harness entry missing: {entry}")
        entry_bytes = byte_size(entry)
        entry_lines = line_count(entry)
        fan_out = bool(platform_record.get("skill_fan_out", False))
        for mode, packs, names, row_class in selections:
            description_bytes = 0
            descriptions: List[dict] = []
            if fan_out:
                for name in names:
                    skill_path = root / name / "SKILL.md"
                    if not skill_path.is_file():
                        raise ValueError(f"selected profile skill missing: {skill_path}")
                    description = parse_frontmatter_description(skill_path)
                    amount = len(description.encode("utf-8"))
                    descriptions.append({"name": name, "bytes": amount})
                    description_bytes += amount
            selection = mode if not packs else f"{mode}+{'+'.join(packs)}"
            row_id = f"{platform}|{selection}"
            components = {
                "entry_bytes": entry_bytes,
                "descriptions_bytes": description_bytes,
                "router_bytes": router_bytes,
                "linked_registry_bytes": registry_bytes,
            }
            rows.append(
                {
                    "id": row_id,
                    "harness": platform,
                    "selection": selection,
                    "delivery_mode": mode,
                    "packs": list(packs),
                    "class": row_class,
                    "entry": {
                        "path": entry_path,
                        "bytes": entry_bytes,
                        "lines": entry_lines,
                        "kind": "template" if platform == "cursor" else "entry",
                    },
                    "skill_fan_out": fan_out,
                    "skills": names if fan_out else [],
                    "descriptions": {
                        "count": len(descriptions),
                        "bytes": description_bytes,
                        "values": descriptions,
                    },
                    "required_router": {
                        "path": "skill-router/SKILL.md",
                        "bytes": router_bytes,
                        "lines": router_lines,
                        "reads": "once",
                    },
                    "linked_on_demand": {
                        "path": "protocol-registry.json",
                        "bytes": registry_bytes,
                        "lines": registry_lines,
                        "reads": "separate",
                    },
                    "components": components,
                    "required_read_bytes": entry_bytes + description_bytes + router_bytes,
                    "total_with_on_demand_bytes": entry_bytes + description_bytes + router_bytes + registry_bytes,
                }
            )
    return rows


def inventory(root: Path) -> List[dict]:
    entries: List[dict] = []
    for path in top_level_skills(root):
        entries.append(
            {
                "name": path.parent.name,
                "path": str(path.relative_to(root)),
                "bytes": byte_size(path),
                "lines": line_count(path),
                "candidate_mandate_count": sum(
                    bool(MANDATE_CANDIDATE.search(line))
                    for line in path.read_text(encoding="utf-8").splitlines()
                ),
            }
        )
    return entries


def parse_table_row(line: str) -> List[str]:
    if not line.strip().startswith("|"):
        return []
    cells = line.strip().strip("|").split("|")
    return [cell.strip() for cell in cells]


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        return value[1:-1]
    if value.startswith("`") and value.endswith("`"):
        return value[1:-1]
    return value


def parse_triage_entries(path: Path) -> List[dict]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    entries: List[dict] = []
    header: Optional[List[str]] = None
    for line_number, line in enumerate(lines):
        cells = parse_table_row(line)
        if cells:
            lowered = [cell.lower().replace(" ", "_") for cell in cells]
            if "source" in lowered and ("quote" in lowered or "quoted_source" in lowered) and (
                "class" in lowered or "disposition" in lowered
            ):
                header = lowered
                continue
            if header and all(set(cell) <= {"-", ":"} or not cell for cell in cells):
                continue
            if header and len(cells) >= len(header):
                values = dict(zip(header, cells))
                entries.append(
                    {
                        "source": unquote(values.get("source", "")),
                        "quote": unquote(values.get("quote", values.get("quoted_source", ""))),
                        "class": unquote(values.get("class", values.get("disposition", ""))).lower(),
                    }
                )
                continue

        # Also accept compact YAML-like entries so a stale or hand-authored
        # document reports a bounded unresolved result rather than throwing.
        source_match = re.search(r"(?:^|-\s*)source\s*:\s*(.+)$", line)
        if source_match:
            item = {"source": unquote(source_match.group(1)), "quote": "", "class": ""}
            for offset in range(1, 4):
                if line_number + offset >= len(lines):
                    break
                candidate = lines[line_number + offset]
                match = re.search(r"^\s*(quote|quoted_source|class|disposition)\s*:\s*(.+)$", candidate)
                if match:
                    key = "quote" if match.group(1) in ("quote", "quoted_source") else "class"
                    item[key] = unquote(match.group(2))
            entries.append(item)
    return entries


def triage(root: Path, document: Path) -> Tuple[dict, int]:
    entries = parse_triage_entries(document)
    counts = {name: 0 for name in TRIAGE_CLASSES}
    invalid = 0
    unresolved = 0
    details: List[dict] = []
    for entry in entries:
        disposition = entry.get("class", "")
        if disposition in counts:
            counts[disposition] += 1
        else:
            invalid += 1
        source_name = entry.get("source", "")
        quote = entry.get("quote", "")
        source = (root / source_name).resolve()
        resolves = False
        try:
            source.relative_to(root.resolve())
            if source.is_file() and quote:
                quoted_line = quote.strip()
                resolves = any(
                    quoted_line == line.strip()
                    for line in source.read_text(encoding="utf-8").splitlines()
                )
        except ValueError:
            resolves = False
        if not resolves:
            unresolved += 1
        details.append({**entry, "resolves": resolves})
    result = {
        "document": str(document),
        "entries": len(entries),
        "counts": counts,
        "invalid_class_count": invalid,
        "unresolved_count": unresolved,
        "details": details,
    }
    return result, 1 if unresolved or invalid else 0


def build_report(root: Path) -> dict:
    model, mode_skills, pack_skills = read_profiles(root)
    rows = selection_rows(root, model, mode_skills, pack_skills)
    return {
        "schema_version": "context-budget/v1",
        "repository": str(root),
        "units": "UTF-8 bytes and source lines; token values are intentionally not claimed",
        "profile_source": "profiles.json plus profiles/<name> @includes",
        "platform_source": "profiles.json platforms.skill_fan_out",
        "rows": rows,
        "inventory": inventory(root),
        "inventory_scope": "live top-level */SKILL.md only; counts are regex candidates, not semantic mandate truth",
        "mandate_candidate_regex": MANDATE_CANDIDATE.pattern,
        "excluded": [{"path": path, "reason": reason} for path, reason in EXCLUDED],
    }


def print_human(report: dict, triage_result: Optional[dict] = None) -> None:
    print("Context budget meter (context-budget/v1)")
    print(f"Repository: {report['repository']}")
    print(f"Units: {report['units']}")
    print("Profile source: profiles.json plus profile-file @includes")
    print("Platform source: profiles.json platforms.skill_fan_out")
    print("Rows: normal delivery mode × capability-pack subsets, plus PROFILE=all maintainer ceiling")
    for row in report["rows"]:
        packs = ",".join(row["packs"]) if row["packs"] else "none"
        print(
            f"ROW id={row['id']} harness={row['harness']} delivery={row['delivery_mode']} "
            f"packs={packs} class={row['class']}"
        )
        entry = row["entry"]
        print(
            f"  entry path={entry['path']} bytes={entry['bytes']} lines={entry['lines']} kind={entry['kind']}"
        )
        print(
            f"  installed_descriptions count={row['descriptions']['count']} bytes={row['descriptions']['bytes']} "
            f"skill_fan_out={str(row['skill_fan_out']).lower()}"
        )
        print(
            f"  required_router path={row['required_router']['path']} bytes={row['required_router']['bytes']} "
            f"reads={row['required_router']['reads']}"
        )
        print(
            f"  linked_on_demand path={row['linked_on_demand']['path']} bytes={row['linked_on_demand']['bytes']} "
            f"reads={row['linked_on_demand']['reads']}"
        )
        print(
            f"  measured required_read_bytes={row['required_read_bytes']} "
            f"total_with_on_demand_bytes={row['total_with_on_demand_bytes']}"
        )
    print(f"Inventory: {len(report['inventory'])} live top-level SKILL.md files")
    for item in report["inventory"]:
        print(
            f"  SKILL name={item['name']} path={item['path']} bytes={item['bytes']} "
            f"lines={item['lines']} candidate_mandates={item['candidate_mandate_count']}"
        )
    print(
        "Inventory note: candidate_mandates uses "
        f"/{report['mandate_candidate_regex']}/ and is not semantic truth"
    )
    print("Excluded: " + "; ".join(f"{item['path']} ({item['reason']})" for item in report["excluded"]))
    if triage_result is not None:
        print(f"Triage document: {triage_result['document']}")
        for name in TRIAGE_CLASSES:
            print(f"  class={name} count={triage_result['counts'][name]}")
        print(f"  invalid_class_count={triage_result['invalid_class_count']}")
        print(f"  unresolved_count={triage_result['unresolved_count']}")


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, help="repository root (defaults to the parent of scripts/)")
    parser.add_argument("--json", action="store_true", help="emit deterministic JSON instead of the readable report")
    parser.add_argument("--triage", type=Path, metavar="DOCUMENT", help="also inspect a content-keyed triage Markdown document")
    args = parser.parse_args(argv)
    root = (args.root or Path(__file__).resolve().parents[1]).resolve()
    if not root.is_dir():
        print(f"ERROR: repository root does not exist: {root}", file=sys.stderr)
        return 2
    try:
        report = build_report(root)
        triage_result = None
        triage_rc = 0
        if args.triage:
            document = args.triage if args.triage.is_absolute() else (Path.cwd() / args.triage)
            document = document.resolve()
            if not document.is_file():
                print(f"ERROR: triage document does not exist: {document}", file=sys.stderr)
                return 2
            triage_result, triage_rc = triage(root, document)
            report["triage"] = triage_result
        if args.json:
            print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
        else:
            print_human(report, triage_result)
        return triage_rc
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
