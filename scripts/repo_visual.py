#!/usr/bin/env python3
"""Build the deterministic model behind the repo visual map, and gate flow drift.

Two responsibilities, both read-only over the repository:

  model        emit the presentation model as deterministic JSON on stdout
  check-flows  assert flows.json agrees with the router prose and the registry

The model carries no wall-clock value. A build that embeds the current time
cannot be diffed against its own regeneration, which is the only cheap way to
prove a generated page still matches the repository it claims to describe.
Identity comes from the Git commit instead.
"""

from __future__ import annotations

import argparse
import hashlib
from html import escape
import json
from pathlib import Path
import re
import subprocess
import sys

MODEL_SCHEMA = "repo-visual/v1"
PAGE_PATH = Path("docs") / "repo-visual.html"
FLOWS_SCHEMA = "skill-commons/flows/v1"

# docs/work and docs/STATUS.md are excluded from the public export. Presentation
# built from them would silently bind this page to the private repository, so the
# producer refuses to carry their content rather than trusting a downstream test.
PRIVATE_MARKERS = ("docs/work/", "STATUS.md")

CLAIM_TODO_COPY = {
    "What is the input-token cost of loading workflow guidance?": {
        "task": "重建 workflow guidance 的 input-token 成本基線",
        "done_when": (
            "找回原始八案例 artifacts，或在固定 revision、model 與 prompt 下重跑 "
            "A/B/C，並保存可重播的 raw artifacts。"
        ),
        "status": "待補證據",
    },
    "Did the historical blind scorer establish quality or usability gains?": {
        "task": "重做不洩漏 arm identity 的品質與可用性盲評",
        "done_when": (
            "凍結匿名 packets 與 rubric，保存 scorer inputs／outputs，並驗證 packets "
            "不含 arm identity。"
        ),
        "status": "待重做",
    },
    "Did the repaired Luna-high blind scoring establish a quality winner?": {
        "task": "重跑修正後的 Luna-high 盲評",
        "done_when": (
            "保存完整 raw artifacts 與 post-run validator 結果，讓流程可獨立重播，"
            "並依結果記錄勝者或無勝者。"
        ),
        "status": "待重跑",
    },
    "Can another tool cold-start and continue with less rework?": {
        "task": "量測跨工具 cold-start 與續接成本",
        "done_when": (
            "以相同 task 與 revision 執行 matched handoff experiment，比較接續時間、"
            "釐清次數、stale work、rework、token 與測試結果。"
        ),
        "status": "待設計實驗",
    },
    "Does the bundle improve team throughput or human usability?": {
        "task": "量測 team throughput 與 human usability",
        "done_when": (
            "以預先定義的週期時間、重工、錯誤率與可用性指標完成 matched team study。"
        ),
        "status": "待設計研究",
    },
}

NON_SKILL_DIRS = {"docs", "tests", "scripts", "bootstrap", "profiles", "journey-evals", "_archive", "node_modules"}


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def frontmatter(text: str) -> dict[str, str]:
    """Parse a SKILL.md frontmatter block, folding `key: |` blocks to one line."""
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    block = text[3:end].strip("\n")
    fields: dict[str, str] = {}
    key = None
    for line in block.splitlines():
        if not line.strip():
            continue
        match = re.match(r"^([a-z_]+):\s*(.*)$", line)
        if match and not line.startswith((" ", "\t")):
            key = match.group(1)
            value = match.group(2).strip()
            fields[key] = "" if value in ("|", ">", "|-", ">-") else value
        elif key and line.startswith((" ", "\t")) and not fields.get(key):
            fields[key] = line.strip()
    return fields


def skill_dirs(root: Path) -> list[Path]:
    return sorted(
        path
        for path in root.iterdir()
        if path.is_dir()
        and not path.name.startswith(".")
        and path.name not in NON_SKILL_DIRS
        and (path / "SKILL.md").is_file()
    )


def package_dirs(root: Path) -> list[Path]:
    return sorted(
        path
        for path in root.iterdir()
        if path.is_dir()
        and not path.name.startswith(".")
        and path.name not in NON_SKILL_DIRS
        and (path / "__init__.py").is_file()
    )


def resolve_profile(root: Path, name: str, depth: int = 0) -> list[str]:
    """Resolve one profiles/<name> file, following `@other` includes."""
    if depth > 3:
        raise SystemExit(f"profile include depth exceeded at {name}")
    path = root / "profiles" / name
    if not path.is_file():
        raise SystemExit(f"profile file missing: profiles/{name}")
    names: list[str] = []
    for line in read(path).splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("@"):
            names.extend(resolve_profile(root, line[1:], depth + 1))
        else:
            names.append(line)
    return names


def evidence_map(root: Path) -> list[dict[str, str]]:
    """Extract the `## Evidence map` table from docs/evaluation.md."""
    text = read(root / "docs" / "evaluation.md")
    section = re.search(r"^## Evidence map\s*$(.*?)(?=^## )", text, re.MULTILINE | re.DOTALL)
    if not section:
        raise SystemExit("docs/evaluation.md has no `## Evidence map` section")
    rows: list[dict[str, str]] = []
    for line in section.group(1).splitlines():
        line = line.strip()
        if not line.startswith("|") or set(line) <= set("|-: "):
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) != 3 or cells[0].lower() == "question":
            continue
        row = {"question": cells[0], "evidence": cells[1], "status": cells[2]}
        for value in row.values():
            for marker in PRIVATE_MARKERS:
                if marker in value:
                    raise SystemExit(
                        f"evidence map row carries private reference `{marker}`: {value}"
                    )
        rows.append(row)
    if not rows:
        raise SystemExit("docs/evaluation.md evidence map is empty")
    return rows


def claim_todos(claim_limits: list[dict[str, str]]) -> list[dict[str, str]]:
    """Turn unresolved evidence claims into a fail-closed action list."""
    questions = [row["question"] for row in claim_limits]
    missing = sorted(set(questions) - set(CLAIM_TODO_COPY))
    stale = sorted(set(CLAIM_TODO_COPY) - set(questions))
    if missing or stale:
        details = []
        if missing:
            details.append(f"missing copy for: {', '.join(missing)}")
        if stale:
            details.append(f"stale copy for: {', '.join(stale)}")
        raise SystemExit("claim todo copy drifted from docs/evaluation.md (" + "; ".join(details) + ")")
    return [CLAIM_TODO_COPY[question] for question in questions]


def roster(root: Path) -> list[dict[str, str]]:
    result = subprocess.run(
        ["bash", "tests/verify.sh", "--list"],
        cwd=root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"verify.sh --list failed: {result.stderr.strip()}")
    entries: list[dict[str, str]] = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        entries.append({"kind": parts[0], "name": parts[1]})
    if not entries:
        raise SystemExit("verify.sh --list returned an empty roster")

    # This generated page ships in the public payload. The private source tree
    # discovers maintainer-only suites too, but embedding them would make the
    # exported page name files that do not exist and fail its own regeneration.
    # Ask Git for the one authoritative public/private boundary instead of
    # duplicating the export-ignore roster here.
    suites = [entry["name"] for entry in entries if entry["kind"] == "suite"]
    attrs = subprocess.run(
        ["git", "check-attr", "export-ignore", "--", *suites],
        cwd=root,
        capture_output=True,
        text=True,
    )
    if attrs.returncode != 0:
        raise SystemExit(f"git check-attr export-ignore failed: {attrs.stderr.strip()}")
    ignored = {
        line.rsplit(": ", 1)[0].split(": export-ignore", 1)[0]
        for line in attrs.stdout.splitlines()
        if line.endswith(": set")
    }
    public_entries = [
        entry
        for entry in entries
        if entry["kind"] != "suite" or entry["name"] not in ignored
    ]
    if not public_entries:
        raise SystemExit("public verify roster is empty after export-ignore filtering")
    return public_entries


def content_digest(payload: dict) -> str:
    """Stable identity for the described contracts, independent of the checkout."""
    canonical = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]


def applicable_gates(registry: dict, installed: set[str]) -> list[str]:
    """Derive the human decisions that can occur with one delivery bundle.

    An execution mode is available only when every required artifact has at
    least one installed producer.  Optional and absent artifacts do not make a
    mode unavailable.  Gate applicability is the union across the modes that
    remain possible; this keeps profile semantics in the machine model instead
    of teaching the renderer special cases such as ``personal``.
    """
    gates: set[str] = set()
    for mode in registry.get("execution_modes", {}).values():
        required = (
            artifact
            for artifact in mode.get("artifacts", {}).values()
            if artifact.get("requirement") == "required"
        )
        if all(
            any(producer in installed for producer in artifact.get("producers", []))
            for artifact in required
        ):
            gates.update(mode.get("human_gates", []))
    return sorted(gates)


def build_model(root: Path) -> dict:
    registry = json.loads(read(root / "protocol-registry.json"))
    profiles_config = json.loads(read(root / "profiles.json"))
    lock = json.loads(read(root / "skills-lock.json")).get("skills", {})
    flows = json.loads(read(root / "flows.json"))

    profile_names = sorted(registry.get("profiles", {}))
    membership = {name: sorted(set(resolve_profile(root, name))) for name in profile_names}

    skills = []
    for path in skill_dirs(root):
        name = path.name
        fields = frontmatter(read(path / "SKILL.md"))
        upstream = lock.get(name)
        skills.append(
            {
                "name": name,
                "path": f"{name}/SKILL.md",
                "intent": fields.get("description", "").strip(),
                "stage": fields.get("stage", ""),
                "output": fields.get("output", ""),
                "source_kind": fields.get("source_kind", ""),
                "maturity": fields.get("maturity", "stable"),
                # Two independent provenance channels: `skills-lock.json` covers the
                # npx-managed vendored set, while an adapted skill records its origin
                # in its own frontmatter. Reading only the lock silently drops the
                # second group, so both are carried and neither is inferred.
                "provenance": {
                    "lock": (
                        {
                            "source": upstream.get("source", ""),
                            "hash": upstream.get("computedHash", ""),
                        }
                        if upstream
                        else None
                    ),
                    "declared_source": fields.get("source", ""),
                },
                "profiles": sorted(p for p in profile_names if name in membership[p]),
            }
        )

    packages = [
        {
            "name": path.name,
            "path": f"{path.name}/__init__.py",
            "modules": len(sorted(path.glob("*.py"))),
        }
        for path in package_dirs(root)
    ]

    evidence = evidence_map(root)
    profiles = {}
    for name in profile_names:
        kind = registry["profiles"][name].get("kind", "")
        profile = {
            "kind": kind,
            "requires": registry["profiles"][name].get("requires", []),
            "conflicts": registry["profiles"][name].get("conflicts", []),
            "file": f"profiles/{name}",
            "skills": membership[name],
        }
        # A capability pack is not an executable bundle on its own, so applying
        # a gate verdict to it would invent semantics the registry does not own.
        if kind == "delivery-mode":
            profile["applicable_gates"] = applicable_gates(
                registry, set(membership[name])
            )
        profiles[name] = profile

    model = {
        "schema_version": MODEL_SCHEMA,
        "identity": {
            "registry_schema": registry.get("schema_version", ""),
            "profiles_schema": profiles_config.get("schema_version", ""),
            "flows_schema": flows.get("schema_version", ""),
            "work_item_schema": registry.get("work_item", {}).get("schema_version", ""),
        },
        "non_goals": registry.get("non_goals", []),
        "skills": skills,
        "packages": packages,
        "profiles": profiles,
        "platforms": profiles_config.get("platforms", {}),
        "execution_modes": registry.get("execution_modes", {}),
        "work_item": registry.get("work_item", {}),
        "flows": flows.get("flows", []),
        "human_gates": flows.get("human_gates", []),
        "tests": {"roster": roster(root), "runner": "tests/verify.sh"},
        "evidence_map": evidence,
        "claim_limits": [
            row for row in evidence if not row["status"].lower().startswith("supported")
        ],
    }
    described = {key: value for key, value in model.items() if key != "identity"}
    model["identity"]["content_digest"] = content_digest(described)
    return model


def check_flows(root: Path, router_path: Path, flows_path: Path) -> list[str]:
    errors: list[str] = []
    flows = json.loads(read(flows_path))
    registry = json.loads(read(root / "protocol-registry.json"))
    router = read(router_path)

    if flows.get("schema_version") != FLOWS_SCHEMA:
        errors.append(f"flows schema must be {FLOWS_SCHEMA}")

    declared = sorted(flow.get("router_heading", "") for flow in flows.get("flows", []))
    in_router = sorted(re.findall(r"^## Flow: (\S+)\s*$", router, re.MULTILINE))
    if declared != in_router:
        errors.append(
            f"flow headings disagree: flows.json={declared} router={in_router}"
        )

    registry_gates = sorted(
        {
            gate
            for mode in registry.get("execution_modes", {}).values()
            for gate in mode.get("human_gates", [])
        }
    )
    declared_gates = sorted(gate.get("id", "") for gate in flows.get("human_gates", []))
    if declared_gates != registry_gates:
        errors.append(
            f"human gates disagree: flows.json={declared_gates} registry={registry_gates}"
        )
    for gate in flows.get("human_gates", []):
        label = gate.get("router_label", "")
        if label and label not in router:
            errors.append(f"router does not present human gate label `{label}`")

    known_skills = {path.name for path in skill_dirs(root)}
    known_modes = set(registry.get("execution_modes", {}))
    for flow in flows.get("flows", []):
        for variant in flow.get("variants", []):
            mode = variant.get("execution_mode")
            if mode is not None and mode not in known_modes:
                errors.append(
                    f"{flow.get('id')}/{variant.get('id')} names unknown execution mode `{mode}`"
                )
            node_ids = set()
            for node in variant.get("nodes", []):
                node_ids.add(node.get("id", ""))
                if node.get("kind") == "skill" and node.get("ref") not in known_skills:
                    errors.append(
                        f"{flow.get('id')}/{variant.get('id')} references missing skill `{node.get('ref')}`"
                    )
                if node.get("kind") == "gate" and node.get("ref") not in registry_gates:
                    errors.append(
                        f"{flow.get('id')}/{variant.get('id')} references unknown gate `{node.get('ref')}`"
                    )
            for edge in variant.get("edges", []):
                for end in ("from", "to"):
                    if edge.get(end) not in node_ids:
                        errors.append(
                            f"{flow.get('id')}/{variant.get('id')} edge {end} `{edge.get(end)}` is not a declared node"
                        )
    return errors


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

PAGE_RELATIVE_PREFIX = ".."  # the page lives in docs/, repo files are one level up

# The hero is the one image that has to land in fifteen seconds: a delivery
# pipeline where the three human decisions are shaped differently from every
# machine-checked step.
HERO_STEPS = [
    ("rect", "意圖", "router 選最短路徑", "skill-router"),
    ("gate", "PRD 核可", "人工", "prd"),
    ("rect", "設計", "spec / prototype", "spec"),
    ("gate", "team 設計核可", "人工", "team-design"),
    ("rect", "計畫", "canonical plan", "plan-sync"),
    ("rect", "實作", "RED → GREEN", "implement"),
    ("rect", "驗證", "機器 Gate + 證據", "verification-before-completion"),
    ("gate", "發布核可", "人工", "release"),
    ("rect", "交付", "授權後才動 Git", "sync-work"),
]


def hero_svg() -> str:
    """Deterministic inline SVG. No layout library, no external asset."""
    pad, gap, top = 18, 30, 34
    rect_w, gate_w, height = 152, 82, 56
    x = pad
    shapes: list[str] = []
    arrows: list[str] = []
    previous_right: float | None = None
    for kind, label, hint, target in HERO_STEPS:
        width = gate_w if kind == "gate" else rect_w
        centre_x = x + width / 2
        centre_y = top + height / 2
        if previous_right is not None:
            arrows.append(
                f'<line class="edge" x1="{previous_right}" y1="{centre_y}" '
                f'x2="{x - 6}" y2="{centre_y}" marker-end="url(#arrow)"/>'
            )
        if kind == "gate":
            half = height / 2
            points = (
                f"{centre_x},{top} {x + width},{centre_y} "
                f"{centre_x},{top + height} {x},{centre_y}"
            )
            shapes.append(
                f'<g class="node gate" data-gate="{target}" role="button" tabindex="0" '
                f'aria-label="{escape(label)}">'
                f'<polygon points="{points}"/>'
                f'<text class="glyph" x="{centre_x}" y="{centre_y + 5}">人</text>'
                f'<text class="cap" x="{centre_x}" y="{top + height + 23}">{escape(label)}</text>'
                f'<text class="gate-na-label" x="{centre_x}" y="{top + height + 42}">不適用</text>'
                f"</g>"
            )
            del half
        else:
            shapes.append(
                f'<g class="node step" data-skill="{target}" role="button" tabindex="0">'
                f'<rect x="{x}" y="{top}" width="{width}" height="{height}" rx="7"/>'
                f'<text class="lbl" x="{centre_x}" y="{centre_y - 4}">{escape(label)}</text>'
                f'<text class="sub" x="{centre_x}" y="{centre_y + 16}">{escape(hint)}</text>'
                f"</g>"
            )
        previous_right = x + width
        x += width + gap
    total = x - gap + pad
    return (
        f'<svg class="hero" viewBox="0 0 {total} 150" role="img" '
        f'aria-label="交付流水線與三個人工判斷點">'
        '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" '
        'markerWidth="6" markerHeight="6" orient="auto-start-reverse">'
        '<path d="M0,1 L9,5 L0,9 z"/></marker></defs>'
        + "".join(arrows)
        + "".join(shapes)
        + "</svg>"
    )


CSS = """
:root{
  /* Four steps, nothing else: page title, section/card title, body, note. */
  --fs-h1:28px; --fs-title:18px; --fs-body:16px; --fs-note:14px;
  --bg:#fbfbf9; --panel:#ffffff; --panel-2:#f0f0ea; --line:#c6c6b9;
  --ink:#0b0c06; --muted:#2b2e24; --dim:#43463b;
  --accent:#1f4527; --accent-soft:#e2ece3;
  --human:#6b3708; --human-soft:#f4e5d4;
  --warn:#6e2020; --warn-soft:#f6e0dd;
  --mono:ui-monospace,SFMono-Regular,Menlo,monospace;
  --sans:system-ui,-apple-system,"Helvetica Neue",sans-serif;
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#0f1110; --panel:#181b19; --panel-2:#212621; --line:#454d46;
    --ink:#f8faf6; --muted:#e0e5db; --dim:#bcc2b6;
    --accent:#a6e0b5; --accent-soft:#1d2c22;
    --human:#f4c286; --human-soft:#33281a;
    --warn:#f5a79e; --warn-soft:#33201f;
  }
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);
  font-size:var(--fs-body);line-height:1.65;-webkit-font-smoothing:antialiased}
a{color:var(--accent)}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
code,.mono{font-family:var(--mono);font-size:.92em}
.wrap{max-width:1180px;margin:0 auto;padding:40px 22px 100px}
header h1{margin:0 0 10px;font-size:var(--fs-h1);letter-spacing:-.012em}
header p.lede{margin:0 0 14px;color:var(--ink);max-width:66ch}
header p.lede.stance{color:var(--muted);margin-bottom:34px;
  border-left:3px solid var(--accent);padding-left:13px}
h2{font-size:var(--fs-title);letter-spacing:.01em;color:var(--ink);
  margin:48px 0 16px;font-weight:650}
h2:first-of-type{margin-top:0}
.cards{display:grid;gap:13px;grid-template-columns:repeat(auto-fit,minmax(252px,1fr))}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px 17px}
.card h3{margin:0 0 7px;font-size:var(--fs-title)}
.card p{margin:0;color:var(--ink)}
.scroll{overflow-x:auto;background:var(--panel);border:1px solid var(--line);
  border-radius:10px;padding:10px 4px 4px}
svg.hero{display:block;min-width:1240px;width:100%;height:auto}
svg.hero .edge{stroke:var(--dim);stroke-width:1.5}
svg.hero marker path{fill:var(--dim)}
svg.hero .node{cursor:pointer}
svg.hero .step rect{fill:var(--panel-2);stroke:var(--line);stroke-width:1.4}
svg.hero .node:hover rect,svg.hero .node:focus rect{stroke:var(--accent);stroke-width:2.2}
svg.hero .gate polygon{fill:var(--human-soft);stroke:var(--human);stroke-width:2}
svg.hero .node:hover polygon,svg.hero .node:focus polygon{stroke-width:3}
svg.hero text{text-anchor:middle;font-family:var(--sans)}
svg.hero .lbl{font-size:var(--fs-body);fill:var(--ink)}
svg.hero .sub{font-size:var(--fs-note);fill:var(--muted)}
svg.hero .glyph{font-size:var(--fs-title);fill:var(--human);font-weight:700}
svg.hero .cap{font-size:var(--fs-note);fill:var(--human);font-weight:600}
svg.hero .gate-na-label{display:none;font-size:var(--fs-note);fill:var(--muted);font-weight:650}
svg.hero .gate[data-na=true] polygon{fill:var(--panel-2);stroke:var(--muted);stroke-dasharray:4 3}
svg.hero .gate[data-na=true] .glyph,svg.hero .gate[data-na=true] .cap{fill:var(--muted)}
svg.hero .gate[data-na=true] .gate-na-label{display:block}
.legend{display:flex;gap:22px;flex-wrap:wrap;font-size:var(--fs-note);color:var(--ink);
  margin:13px 2px 0}
.legend i{display:inline-block;width:12px;height:12px;margin-right:7px;vertical-align:-1px}
.legend i.m{background:var(--panel-2);border:1px solid var(--line)}
.legend i.h{background:var(--human-soft);border:1px solid var(--human);transform:rotate(45deg)}
.flow{background:var(--panel);border:1px solid var(--line);border-radius:10px;
  padding:15px 17px;margin-bottom:11px}
.flow h3{margin:0 0 4px;font-size:var(--fs-title)}
.flow p.intent{margin:0 0 12px;color:var(--muted);font-size:var(--fs-note)}
.variant{display:grid;grid-template-columns:160px minmax(0,1fr);align-items:start;
  gap:7px;margin:9px 0}
.variant .vname{font-family:var(--mono);font-size:var(--fs-note);color:var(--muted);
  min-width:152px;justify-self:start}
.variant-flow{display:flex;flex-wrap:wrap;align-items:center;gap:7px;min-width:0}
.variant-flow .chip{max-width:100%;overflow-wrap:anywhere}
.chip{border:1px solid var(--line);background:var(--panel-2);border-radius:6px;
  padding:4px 10px;font-size:var(--fs-body);cursor:pointer;color:var(--ink)}
.chip:hover{border-color:var(--accent)}
.chip.gate{background:var(--human-soft);border-color:var(--human);color:var(--human);
  font-weight:600}
.chip.handoff{background:transparent;border-style:dashed;color:var(--muted);cursor:default}
.arrow{color:var(--muted)}
.filters{position:sticky;top:0;z-index:5;display:flex;gap:8px;flex-wrap:wrap;
  align-items:center;background:var(--bg);border-bottom:1px solid var(--line);
  padding:11px 0;margin:0 0 30px}
.filters .lenslabel{font-size:var(--fs-note);color:var(--muted);margin-right:2px}
.filters button{border:1px solid var(--line);background:var(--panel);color:var(--ink);
  border-radius:999px;padding:5px 14px;font-size:var(--fs-note);cursor:pointer;
  font-family:var(--sans)}
.filters button[aria-pressed=true]{background:var(--accent-soft);border-color:var(--accent);
  color:var(--accent);font-weight:650}
/* Out of the selected bundle. Marked, never removed: dropping a chip out of a
   flow chain would leave dangling arrows and misreport the flow, and hiding it
   from the catalogue hides exactly the boundary the reader needs to learn. */
[data-out=true]{opacity:.42}
[data-out=true]:not(.chip.gate){border-style:dashed}
.stage [data-out=true]::after{content:"·未安裝";color:var(--muted);font-size:var(--fs-note)}
svg.hero .node[data-out=true] rect{stroke-dasharray:4 3}
/* Human decisions remain visible and clickable even when no execution mode in
   the selected delivery bundle can reach them.  This is a separate state from
   an uninstalled skill: the gate is part of the protocol, but not this route. */
[data-gate][data-na=true]{opacity:.5}
.chip.gate[data-na=true]{border-style:dashed;background:var(--panel-2);color:var(--muted)}
.chip.gate[data-na=true]::after{content:" · 不適用";font-size:var(--fs-note)}
.stagegrid{display:grid;gap:11px;grid-template-columns:repeat(auto-fit,minmax(284px,1fr))}
.stage{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 15px}
.stage h4{margin:0 0 10px;font-size:var(--fs-note);text-transform:uppercase;
  letter-spacing:.07em;color:var(--muted)}
.stage .chip{margin:0 5px 5px 0;display:inline-block}
.chip .ext{color:var(--muted);font-size:var(--fs-note);margin-left:4px}
table{border-collapse:collapse;width:100%;font-size:var(--fs-body);background:var(--panel);
  font-variant-numeric:tabular-nums}
th,td{border:1px solid var(--line);padding:9px 11px;text-align:left;vertical-align:top}
th{background:var(--panel-2);color:var(--ink);font-weight:650;font-size:var(--fs-note)}
td.req{font-family:var(--mono)}
td.req[data-v=required]{color:var(--accent);font-weight:650}
td.req[data-v=optional]{color:var(--ink)}
td.req[data-v=absent]{color:var(--muted);background:var(--panel-2)}
tr.limit td{background:var(--warn-soft)}
tr.limit td:last-child{color:var(--warn);font-weight:650}
.note{color:var(--muted);font-size:var(--fs-note);margin:12px 0 0;max-width:82ch}
.rosterwrap{display:grid;gap:11px;grid-template-columns:repeat(auto-fit,minmax(272px,1fr))}
dialog.detail{max-width:700px;width:calc(100% - 40px);max-height:82vh;overflow-y:auto;
  background:var(--panel);color:var(--ink);border:1px solid var(--line);border-radius:12px;
  padding:28px 28px 34px;box-shadow:0 24px 60px rgba(0,0,0,.24)}
dialog.detail::backdrop{background:rgba(8,10,8,.58)}
dialog.detail .close{position:absolute;top:15px;right:17px;border:1px solid var(--line);
  background:var(--panel-2);color:var(--ink);border-radius:6px;cursor:pointer;
  font-size:var(--fs-note);padding:4px 11px;font-family:var(--sans)}
dialog.detail h3{margin:0 78px 5px 0;font-size:var(--fs-title)}
dialog.detail .kind{font-family:var(--mono);font-size:var(--fs-note);color:var(--muted);
  margin-bottom:15px}
dialog.detail p{margin:0 0 15px}
dialog.detail dl{margin:0 0 16px;display:grid;grid-template-columns:116px 1fr;gap:9px 13px}
dialog.detail dt{color:var(--muted);font-size:var(--fs-note);padding-top:2px}
dialog.detail dd{margin:0}
dialog.detail details{border-top:1px solid var(--line);padding-top:14px;margin-top:6px}
dialog.detail summary{cursor:pointer;color:var(--accent);font-weight:600}
dialog.detail table{margin-top:12px}
dialog.detail .src{display:inline-block;margin-top:15px}
footer{margin-top:56px;border-top:1px solid var(--line);padding-top:18px;
  color:var(--muted);font-size:var(--fs-note)}
@media (max-width:640px){
  .variant{grid-template-columns:minmax(0,1fr)}
  .variant .vname{min-width:0;max-width:100%;width:max-content}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
"""

JS = """
const MODEL = JSON.parse(document.getElementById('model').textContent);
const byName = {};
MODEL.skills.forEach(s => { byName[s.name] = s; });
const gateById = {};
MODEL.human_gates.forEach(g => { gateById[g.id] = g; });
const dialog = document.querySelector('dialog.detail');
const body = document.getElementById('detail-body');

function esc(v){ const d = document.createElement('div'); d.textContent = v == null ? '' : v; return d.innerHTML; }
function row(k, v){ return v ? '<dt>' + esc(k) + '</dt><dd>' + v + '</dd>' : ''; }

function openDetail(html){
  body.innerHTML = html;
  if (!dialog.open) dialog.showModal();
  dialog.scrollTop = 0;
}
/*SOURCE_FN*/
function closeDetail(){ if (dialog.open) dialog.close(); }
// The dialog element is the only hit area outside the content box, so a click
// landing on it is a backdrop click.
dialog.addEventListener('click', event => { if (event.target === dialog) closeDetail(); });

function skillPanel(name){
  const s = byName[name];
  if (!s) return;
  const prov = s.provenance.lock
    ? esc(s.provenance.lock.source) + '<br><span class="mono">' + esc(s.provenance.lock.hash.slice(0,16)) + '…</span>'
    : (s.provenance.declared_source ? '<span class="mono">' + esc(s.provenance.declared_source) + '</span>' : '');
  const tests = MODEL.tests.roster
    .filter(t => t.name.indexOf(name.replace(/-/g,'_')) !== -1)
    .map(t => '<code>' + esc(t.name) + '</code>').join(' ');
  openDetail(
    '<h3>' + esc(s.name) + '</h3>' +
    '<div class="kind">skill · stage ' + esc(s.stage || '未標') + '</div>' +
    '<p>' + esc(s.intent) + '</p>' +
    '<dl>' +
      row('輸出', s.output ? '<code>' + esc(s.output) + '</code>' : '<span style="color:var(--dim)">無 artifact</span>') +
      row('profile', s.profiles.length ? s.profiles.map(p => '<code>' + esc(p) + '</code>').join(' ') : '<span style="color:var(--dim)">不在任何 consuming profile（maintainer 工具）</span>') +
      row('成熟度', esc(s.maturity)) +
    '</dl>' +
    '<details><summary>細節</summary>' +
      '<dl style="margin-top:12px">' +
        row('source_kind', '<code>' + esc(s.source_kind || 'original') + '</code>') +
        row('provenance', prov || '<span style="color:var(--dim)">原生，無上游</span>') +
        row('相關測試', tests || '<span style="color:var(--dim)">無以此技能命名的 suite</span>') +
      '</dl>' +
    '</details>' +
    source(s.path)
  );
}

function gatePanel(id, handle){
  const g = gateById[id];
  if (!g) return;
  const modes = Object.keys(MODEL.execution_modes).sort()
    .filter(m => MODEL.execution_modes[m].human_gates.indexOf(id) !== -1);
  const lensNote = handle && handle.dataset.na === 'true'
    ? '<p class="note">目前選定的 delivery bundle 不會觸發這個判斷點；保留節點是為了讓流程邊界可見。</p>'
    : '';
  openDetail(
    '<h3>' + esc(g.label) + '</h3>' +
    '<div class="kind">human decision · gate ' + esc(g.id) + '</div>' +
    '<p>' + esc(g.decides) + '</p>' +
    '<dl>' +
      row('router 呈現', '<code>' + esc(g.router_label) + '</code>') +
      row('適用模式', modes.map(m => '<code>' + esc(m) + '</code>').join(' ')) +
    '</dl>' +
    lensNote +
    '<details><summary>細節</summary><p class="note" style="margin-top:12px">' +
      '人工判斷點恰好三個，其餘一律機器檢查。核可是檔案上的狀態轉移（awaiting-approval → approved），不是對話裡的承諾。' +
    '</p></details>' +
    source('skill-router/SKILL.md')
  );
}

function modePanel(name){
  const m = MODEL.execution_modes[name];
  if (!m) return;
  const arts = Object.keys(m.artifacts).sort().map(a => {
    const entry = m.artifacts[a];
    const who = entry.producers.length ? entry.producers.join(', ') : '—';
    return '<tr><td><code>' + esc(a) + '</code></td><td class="req" data-v="' + esc(entry.requirement) + '">'
      + esc(entry.requirement) + '</td><td>' + esc(who) + '</td></tr>';
  }).join('');
  openDetail(
    '<h3>' + esc(name) + '</h3>' +
    '<div class="kind">execution mode · flow ' + esc(m.flow) + '</div>' +
    '<dl>' +
      row('人工判斷點', m.human_gates.map(g => '<code>' + esc(g) + '</code>').join(' ')) +
      row('交接', '<code>' + esc(m.handoff) + '</code>') +
    '</dl>' +
    '<details open><summary>artifact 契約</summary>' +
      '<table style="margin-top:10px"><thead><tr><th>artifact</th><th>要求</th><th>producer</th></tr></thead><tbody>'
      + arts + '</tbody></table>' +
      '<p class="note"><code>absent</code> 不是「還沒做」，是這條路徑不產該 artifact；補造它就是違約。</p>' +
    '</details>' +
    source('protocol-registry.json')
  );
}

document.addEventListener('click', event => {
  const target = event.target.closest('[data-skill],[data-gate],[data-mode],.close');
  if (!target) return;
  if (target.classList.contains('close')) { closeDetail(); return; }
  if (target.dataset.skill) { skillPanel(target.dataset.skill); return; }
  if (target.dataset.gate) { gatePanel(target.dataset.gate, target); return; }
  if (target.dataset.mode) { modePanel(target.dataset.mode); return; }
});

const buttons = Array.prototype.slice.call(document.querySelectorAll('.filters button'));
buttons.forEach(button => button.addEventListener('click', () => {
  const wanted = button.dataset.profile;
  buttons.forEach(b => b.setAttribute('aria-pressed', String(b === button)));
  document.querySelectorAll('[data-skill]').forEach(handle => {
    const owner = byName[handle.dataset.skill];
    const inBundle = wanted === 'all' || (owner && owner.profiles.indexOf(wanted) !== -1);
    if (inBundle) handle.removeAttribute('data-out');
    else handle.setAttribute('data-out', 'true');
  });
  const profile = MODEL.profiles[wanted];
  const applicable = wanted === 'all' || !profile || profile.kind !== 'delivery-mode'
    ? null
    : profile.applicable_gates;
  document.querySelectorAll('[data-gate]').forEach(handle => {
    const applies = applicable === null || applicable.indexOf(handle.dataset.gate) !== -1;
    const gate = gateById[handle.dataset.gate];
    if (applies) handle.removeAttribute('data-na');
    else handle.setAttribute('data-na', 'true');
    if (gate) {
      handle.setAttribute(
        'aria-label',
        gate.label + (applies ? '' : '，目前選定的 bundle 不適用')
      );
    }
  });
}));
"""


SOURCE_FN_LOCAL = (
    "function source(path){ return '<a class=\"src\" href=\"../' + esc(path) "
    "+ '\">開啟 ' + esc(path) + ' →</a>'; }"
)
SOURCE_FN_HOSTED = (
    "function source(path){ return '<div class=\"src\" style=\"color:var(--dim)\">"
    "權威來源 <code>' + esc(path) + '</code>（在 repo checkout 內開啟）</div>'; }"
)


def remote_source_fn(source_base: str) -> str:
    """Build the source-link function for a standalone public site."""
    if not source_base.startswith("https://"):
        raise SystemExit("--source-base must be an https:// URL")
    base = source_base.rstrip("/") + "/"
    encoded_base = json.dumps(base, ensure_ascii=False)
    return (
        f"const SOURCE_BASE = {encoded_base};\n"
        "function source(path){ const href = SOURCE_BASE + encodeURI(path); "
        "return '<a class=\"src\" href=\"' + esc(href) + "
        "'\" target=\"_blank\" rel=\"noreferrer\">開啟 ' + esc(path) + ' →</a>'; }"
    )


def skill_chip(skill: dict) -> str:
    mark = ' <span class="ext">ext</span>' if (
        skill["provenance"]["lock"] or skill["provenance"]["declared_source"]
    ) else ""
    return (
        f'<span class="chip" data-skill="{escape(skill["name"])}" role="button" tabindex="0">'
        f'{escape(skill["name"])}{mark}</span>'
    )


def render_inner(model: dict, source_fn: str) -> str:
    skills = model["skills"]
    stages: dict[str, list[dict]] = {}
    for skill in skills:
        stages.setdefault(skill["stage"] or "未標 stage", []).append(skill)

    entry_cards = [
        ("為什麼是這個形狀", "人只停在三個判斷點：需求、設計取捨、發布。其餘一律機器檢查，缺件與無法界定時停下來，不猜測後繼續。"),
        ("怎麼運作", f"{len(skills)} 個技能依 flow 派發，artifact 契約由 protocol registry 宣告，狀態落在檔案而非對話。"),
        ("怎麼用", "在 .agent/project-manifest.md 設 delivery_mode（personal 或 team-sprint）與選用的 capability_packs（frontend、optional），再跑 bootstrap/onboard.sh 重新 fan-out。execution mode 由 router 依單一任務決定，不必手動設定。"),
        ("怎麼驗", f"{len(model['tests']['roster'])} 條確定性 suite 加真 agent journey；完成宣稱必須附當次證據。"),
    ]

    flow_blocks = []
    for flow in model["flows"]:
        variants = []
        for variant in flow.get("variants", []):
            chips = []
            for index, node in enumerate(variant.get("nodes", [])):
                if index:
                    chips.append('<span class="arrow">→</span>')
                kind = node.get("kind")
                if kind == "gate":
                    gate = next(
                        (g for g in model["human_gates"] if g["id"] == node["ref"]), None
                    )
                    label = gate["label"] if gate else node["ref"]
                    chips.append(
                        f'<span class="chip gate" data-gate="{escape(node["ref"])}" '
                        f'role="button" tabindex="0">{escape(label)}</span>'
                    )
                elif kind == "skill":
                    chips.append(
                        f'<span class="chip" data-skill="{escape(node["ref"])}" '
                        f'role="button" tabindex="0">{escape(node["ref"])}</span>'
                    )
                else:
                    chips.append(f'<span class="chip handoff">{escape(node["ref"])}</span>')
            name = variant.get("execution_mode") or variant.get("id")
            label = (
                f'<span class="vname chip" data-mode="{escape(name)}" role="button" tabindex="0">{escape(name)}</span>'
                if variant.get("execution_mode")
                else f'<span class="vname">{escape(name)}</span>'
            )
            variants.append(
                f'<div class="variant">{label}'
                f'<div class="variant-flow">{"".join(chips)}</div></div>'
            )
        flow_blocks.append(
            f'<div class="flow"><h3>{escape(flow["router_heading"])}</h3>'
            f'<p class="intent">{escape(flow["intent"])}</p>{"".join(variants)}</div>'
        )

    artifact_names = sorted(
        {
            name
            for mode in model["execution_modes"].values()
            for name in mode["artifacts"]
        }
    )
    mode_names = sorted(model["execution_modes"])
    header_cells = "".join(f"<th>{escape(m)}</th>" for m in mode_names)
    matrix_rows = []
    for artifact in artifact_names:
        cells = []
        for mode in mode_names:
            requirement = model["execution_modes"][mode]["artifacts"][artifact]["requirement"]
            cells.append(f'<td class="req" data-v="{requirement}">{requirement}</td>')
        matrix_rows.append(
            f'<tr><td><code>{escape(artifact)}</code></td>{"".join(cells)}</tr>'
        )

    delivery = model["work_item"]["delivery_statuses"]
    delivery_rows = []
    for state in delivery:
        required = delivery[state]["required_evidence"]
        delivery_rows.append(
            f'<tr><td><code>{escape(state)}</code></td>'
            f'<td>{escape(", ".join(delivery[state]["allowed_work_statuses"]))}</td>'
            f'<td>{escape(", ".join(required)) if required else "—"}</td></tr>'
        )

    todo_rows = []
    for todo in claim_todos(model["claim_limits"]):
        todo_rows.append(
            f'<tr class="limit todo-item"><td>{escape(todo["task"])}</td>'
            f'<td>{escape(todo["done_when"])}</td><td>{escape(todo["status"])}</td></tr>'
        )

    roster_groups: dict[str, list[str]] = {}
    for entry in model["tests"]["roster"]:
        bucket = "python 分層" if entry["kind"] == "layer" else (
            "bootstrap suites" if "/bootstrap/" in entry["name"] else "top-level suites"
        )
        roster_groups.setdefault(bucket, []).append(entry["name"])

    profile_buttons = "".join(
        f'<button data-profile="{escape(name)}" aria-pressed="false">{escape(name)}'
        f' <span style="color:var(--dim)">{len(model["profiles"][name]["skills"])}</span></button>'
        for name in sorted(model["profiles"])
    )

    identity = model["identity"]
    payload = json.dumps(model, sort_keys=True, ensure_ascii=False).replace("<", "\\u003c")

    return f"""<div class="wrap">
<header>
  <h1>skill-commons</h1>
  <p class="lede">把交付流程的形狀固定下來：每一步產出形體一致、可續跑、可被 script 驗證的 artifact。
  這頁由 repo 的機器來源生成，權威在 repo，此頁只是索引——每個細節都以一個檔案連結收尾。</p>
  <p class="lede stance">它是宣告式契約加一致性檢查，{escape("、".join("不是 " + goal.replace("-", " ") for goal in model["non_goals"]))}。</p>
</header>

<div class="filters">
  <span class="lenslabel">以安裝內容檢視</span>
  <button data-profile="all" aria-pressed="true">全部 {len(skills)}</button>
  {profile_buttons}
</div>

<h2>一眼看懂</h2>
<div class="cards">
{"".join(f'<div class="card"><h3>{escape(t)}</h3><p>{escape(d)}</p></div>' for t, d in entry_cards)}
</div>

<h2>交付流水線</h2>
<div class="scroll">{hero_svg()}</div>
<div class="legend">
  <span><i class="m"></i>機器檢查的步驟</span>
  <span><i class="h"></i>人工判斷點（恰好三個）</span>
  <span style="color:var(--dim)">點任一節點看細節</span>
</div>

<h2>五條 flow</h2>
{"".join(flow_blocks)}
<p class="note">flow 由 <code>flows.json</code> 宣告，並與 router 散文、protocol registry 雙向綁定：
任一方單獨改動，<code>tests/test_repo_visual.sh</code> 就會變紅。</p>

<h2>{len(skills)} 個技能</h2>
<div class="stagegrid">
{"".join(
    f'<div class="stage"><h4>{escape(stage)}</h4>'
    + "".join(skill_chip(s) for s in sorted(items, key=lambda x: x["name"]))
    + "</div>"
    for stage, items in sorted(stages.items())
)}
</div>
<p class="note">profile 歸屬讀自 <code>profiles/</code>，不在此頁重新輸入。
不要從技能數量推論成本或品質。</p>

<h2>Artifact 契約</h2>
<p class="note" style="margin:0 0 12px">契約版本 <code>{escape(identity["work_item_schema"])}</code>——
消費端 repo 的 work item 必須符合這一版；舊版 work item 過不了檢查。</p>
<div class="scroll" style="padding:0">
<table><thead><tr><th>artifact</th>{header_cells}</tr></thead>
<tbody>{"".join(matrix_rows)}</tbody></table>
</div>
<p class="note"><code>required</code> 缺件就停止；<code>optional</code> 存在就讀；
<code>absent</code> 是這條路徑不產該 artifact——補造它就是違約。點欄位標題看單一 mode 的完整契約。</p>

<h2>交付狀態</h2>
<div class="scroll" style="padding:0">
<table><thead><tr><th>delivery_status</th><th>允許的 work_status</th><th>必要證據</th></tr></thead>
<tbody>{"".join(delivery_rows)}</tbody></table>
</div>
<p class="note">工作完成不等於已交付。每個狀態要求對應形狀的證據；形狀檢查不證明外部核可或部署真的發生過。</p>

<h2>驗證</h2>
<div class="rosterwrap">
{"".join(
    f'<div class="stage"><h4>{escape(group)} · {len(names)}</h4>'
    + "".join(f'<div class="mono" style="color:var(--ink)">{escape(n)}</div>' for n in sorted(names))
    + "</div>"
    for group, names in sorted(roster_groups.items())
)}
</div>
<p class="note">單一入口 <code>bash tests/verify.sh</code>，共 {len(model["tests"]["roster"])} 條。
空 roster、空 layer 與缺檔都算錯誤而非通過。真 agent journey 另行執行，不佔確定性 Verify。</p>

<h2>待處理事項</h2>
<p class="note todo-baseline" style="margin:0 0 12px"><strong>已完成基線：</strong>
artifact、Plan、profile、adapter 與 release contracts 的一致性已有確定性 repository suites 支援；
結論只適用於被測 revision。以下五項是下一階段要補齊的驗證工作。</p>
<div class="scroll" style="padding:0">
<table class="todo-table"><thead><tr><th>待處理事項</th><th>完成條件</th><th>目前狀態</th></tr></thead>
<tbody>{"".join(todo_rows)}</tbody></table>
</div>

<footer>
  生成自 <code>scripts/repo_visual.py render</code>，資料來自
  <code>protocol-registry.json</code>、<code>profiles.json</code>、<code>flows.json</code>、
  <code>skills-lock.json</code>、各 <code>SKILL.md</code> frontmatter、
  <code>tests/verify.sh --list</code> 與 <code>docs/evaluation.md</code>。
  不含 wall-clock，因此可與自身重生成逐位元比對。
  <br>生成資訊：契約摘要 <code>{escape(identity["content_digest"])}</code> ·
  registry <code>{escape(identity["registry_schema"])}</code> ·
  flows <code>{escape(identity["flows_schema"])}</code>。摘要只在被描述的事實改變時變動，與 commit 無關。
</footer>
</div>

<dialog class="detail" aria-label="細節">
  <button class="close" autofocus>關閉</button>
  <div id="detail-body"></div>
</dialog>

<script id="model" type="application/json">{payload}</script>
<script>{JS.replace('/*SOURCE_FN*/', source_fn)}</script>
"""


def render_document(model: dict, source_fn: str) -> str:
    """Complete standalone document with one chosen source-link policy."""
    return (
        "<!DOCTYPE html>\n"
        '<html lang="zh-Hant">\n'
        "<head>\n"
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
        "<title>skill-commons Repo Map</title>\n"
        f"<style>{CSS}</style>\n"
        "</head>\n"
        "<body>\n"
        f"{render_inner(model, source_fn)}"
        "</body>\n"
        "</html>\n"
    )


def render_page(model: dict) -> str:
    """Standalone document for the repository copy."""
    return render_document(model, SOURCE_FN_LOCAL)


def render_site(model: dict, source_base: str) -> str:
    """Standalone public site whose detail exits resolve to the source repo."""
    return render_document(model, remote_source_fn(source_base))


def render_artifact(model: dict) -> str:
    """Hosted fragment. The publish host supplies the document shell, and repo
    paths are shown as text because they cannot resolve away from a checkout."""
    return (
        "<title>skill-commons Repo Map</title>\n"
        f"<style>{CSS}</style>\n"
        f"{render_inner(model, SOURCE_FN_HOSTED)}"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("model")
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument(
        "--check",
        action="store_true",
        help="compare the committed page against a fresh render instead of writing",
    )
    render_kind = render_parser.add_mutually_exclusive_group()
    render_kind.add_argument(
        "--artifact",
        action="store_true",
        help="emit the hosted fragment instead of the standalone repository page",
    )
    render_kind.add_argument(
        "--source-base",
        default=None,
        help="emit a standalone public site whose detail links use this https URL base",
    )
    render_parser.add_argument("--out", default=None, help="write to this path instead of the default")
    flows_parser = subparsers.add_parser("check-flows")
    flows_parser.add_argument("--router", default=None)
    flows_parser.add_argument("--flows", default=None)
    args = parser.parse_args(argv)

    root = repo_root()
    if args.command == "model":
        model = build_model(root)
        text = json.dumps(model, sort_keys=True, indent=2, ensure_ascii=False)
        for marker in PRIVATE_MARKERS:
            if marker in text:
                print(f"model carries private reference `{marker}`", file=sys.stderr)
                return 3
        print(text)
        return 0

    if args.command == "render":
        model = build_model(root)
        if args.artifact:
            page = render_artifact(model)
        elif args.source_base:
            page = render_site(model, args.source_base)
        else:
            page = render_page(model)
        for marker in PRIVATE_MARKERS:
            if marker in page:
                print(f"page carries private reference `{marker}`", file=sys.stderr)
                return 3
        target = Path(args.out) if args.out else root / PAGE_PATH
        if args.check:
            if not target.is_file():
                print(f"page missing: {target}", file=sys.stderr)
                return 2
            if target.read_text(encoding="utf-8") != page:
                print(
                    f"page drift: {target} differs from a fresh render; "
                    "regenerate with `python3 scripts/repo_visual.py render`",
                    file=sys.stderr,
                )
                return 1
            print(f"page: {target} matches a fresh render")
            return 0
        target.write_text(page, encoding="utf-8")
        print(f"page: wrote {target}")
        return 0

    router_path = Path(args.router) if args.router else root / "skill-router" / "SKILL.md"
    flows_path = Path(args.flows) if args.flows else root / "flows.json"
    errors = check_flows(root, router_path, flows_path)
    if errors:
        for error in errors:
            print(f"flow drift: {error}", file=sys.stderr)
        return 1
    print("flows: consistent with router prose and protocol registry")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
