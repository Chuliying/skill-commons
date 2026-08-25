#!/usr/bin/env bash
# Repo visual map: deterministic model build (T01) + flow-declaration consistency (T02).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$REPO/scripts/repo_visual.py"
FLOWS="$REPO/flows.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

if [ ! -f "$TOOL" ]; then
  fail "repo_visual.py entrypoint exists"
  finish
  exit $?
fi

# ---------- T01: model ----------
model_a="$TMP/a.json"
model_b="$TMP/b.json"
(cd "$REPO" && python3 "$TOOL" model > "$model_a" 2>"$TMP/err_a"); rc_a=$?
assert_eq 0 "$rc_a" "model subcommand exits 0"
if [ "$rc_a" -ne 0 ]; then
  echo "  stderr: $(cat "$TMP/err_a")"
  finish
  exit $?
fi

(cd "$REPO" && python3 "$TOOL" model > "$model_b" 2>/dev/null)
if cmp -s "$model_a" "$model_b"; then
  assert_eq ok ok "two model runs are byte-identical (no wall-clock in model)"
else
  fail "two model runs are byte-identical (no wall-clock in model)"
fi

# Run a python probe over the model. An interpreter error is a suite failure,
# never an empty string that an "expected empty" assertion would accept.
probe() { # script msg -> sets PROBE_OUT
  PROBE_OUT="$(python3 -c "$1" "$model_a" 2>"$TMP/probe_err")"
  if [ $? -ne 0 ]; then
    fail "$2 (probe crashed: $(tr '\n' ' ' < "$TMP/probe_err"))"
    PROBE_OUT="__PROBE_CRASHED__"
  fi
}

field() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$model_a" "$2"; }

assert_eq "repo-visual/v1" "$(field _ schema_version)" "model declares schema_version"

# Skills = top-level dirs holding SKILL.md, enumerated independently of the tool.
expected_skills="$(cd "$REPO" && for d in */; do
  [ -f "$d/SKILL.md" ] && basename "$d"
done | sort | tr '\n' ' ')"
actual_skills="$(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
print(" ".join(sorted(s["name"] for s in m["skills"]))+" ")
' "$model_a")"
assert_eq "$expected_skills" "$actual_skills" "model skill set equals SKILL.md folders"

# Python packages are not skills; they must be classified separately.
pkgs="$(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
print(" ".join(sorted(p["name"] for p in m["packages"])))
' "$model_a")"
assert_contains "$pkgs" "foundation" "python packages listed separately"
assert_not_contains "$actual_skills" "foundation" "foundation is not treated as a skill"

# Profile membership must come from profiles/, not be re-typed.
personal_skills="$(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
print(" ".join(sorted(m["profiles"]["personal"]["skills"])))
' "$model_a")"
for team_only in prd-interview spec qa prototype domain-modeling; do
  assert_not_contains " $personal_skills " " $team_only " "personal profile excludes $team_only"
done

# Registry passthrough, not a re-declaration.
modes="$(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
print(" ".join(sorted(m["execution_modes"])))
' "$model_a")"
assert_eq "bug-fix personal-feature refactor team-feature" "$modes" "execution modes come from the registry"

gates="$(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
print(",".join(m["execution_modes"]["team-feature"]["human_gates"]))
' "$model_a")"
assert_eq "prd,team-design,release" "$gates" "team-feature human gates preserved"

# A delivery-mode lens must show which human decisions can actually occur with
# that installed bundle.  The model derives this from required artifact
# producers; the renderer only presents the result.  Capability packs are not
# complete delivery modes, so they intentionally carry no gate verdict.
probe 'import json,sys
m=json.load(open(sys.argv[1]))
print(",".join(m["profiles"]["personal"]["applicable_gates"]))' \
  "personal gate applicability is present"
assert_eq "release" "$PROBE_OUT" "personal bundle only applies the release gate"

probe 'import json,sys
m=json.load(open(sys.argv[1]))
print(",".join(m["profiles"]["team-sprint"]["applicable_gates"]))' \
  "team-sprint gate applicability is present"
assert_eq "prd,release,team-design" "$PROBE_OUT" "team-sprint bundle applies all three gates"

probe 'import json,sys
m=json.load(open(sys.argv[1]))
print(" ".join(sorted(name for name,p in m["profiles"].items()
                      if p["kind"] != "delivery-mode" and "applicable_gates" in p)))' \
  "capability packs do not claim gate applicability"
assert_eq "" "$PROBE_OUT" "only delivery-mode profiles carry gate applicability"

# The page is public payload, so its roster must describe that same surface.
# Derive the boundary from .gitattributes rather than repeating a private-suite
# list here; an exported checkout must render the same model as the source tree.
roster_expected="$(cd "$REPO" && bash tests/verify.sh --list | while IFS=' ' read -r kind name extra; do
  if [ "$kind" = "suite" ]; then
    attr="$(git check-attr export-ignore -- "$name" | sed 's/^.*: //')"
    [ "$attr" = "set" ] && continue
  fi
  printf '%s %s\n' "$kind" "$name"
done)"
roster_actual="$(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
print("\n".join("{} {}".format(entry["kind"], entry["name"]) for entry in m["tests"]["roster"]))
' "$model_a")"
assert_eq "$roster_expected" "$roster_actual" "test roster equals the public verify surface"

# Unverified claims must survive into the model instead of being dropped.
limits="$(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
print(len(m["claim_limits"]))
' "$model_a")"
if [ "$limits" -gt 0 ]; then
  assert_eq ok ok "claim limits carried from docs/evaluation.md"
else
  fail "claim limits carried from docs/evaluation.md (found 0)"
fi

# Provenance must survive for adapted skills too, not only lock-tracked ones.
probe '
import json,sys
m=json.load(open(sys.argv[1]))
bad=[s["name"] for s in m["skills"]
     if s["source_kind"] in ("adapted","external")
     and not (s["provenance"]["lock"] or s["provenance"]["declared_source"])]
print(" ".join(sorted(bad)))
' "adapted and external skills carry provenance"
assert_eq "" "$PROBE_OUT" "adapted and external skills carry provenance"

# Every referenced path must exist.
probe '
import json,sys
from pathlib import Path
m=json.load(open(sys.argv[1]))
bad=[]
def walk(o):
    if isinstance(o,dict):
        for k,v in o.items():
            if k in ("path","file") and isinstance(v,str) and not Path(v).exists():
                bad.append(v)
            else: walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
walk(m)
print(" ".join(sorted(set(bad))))
' "every path in the model exists"
missing="$PROBE_OUT"
assert_eq "" "$missing" "every path in the model exists"

# Privacy boundary: docs/work and STATUS.md are excluded from public export.
raw="$(cat "$model_a")"
assert_not_contains "$raw" "docs/work/" "model carries no docs/work content"
assert_not_contains "$raw" "STATUS.md" "model carries no STATUS.md content"

# ---------- T02: flows ----------
assert_file "$FLOWS" "flows.json exists"
if [ -f "$FLOWS" ]; then
  flow_count="$(python3 -c '
import json,sys
print(len(json.load(open(sys.argv[1]))["flows"]))
' "$FLOWS")"
  assert_eq 5 "$flow_count" "flows.json declares five flows"

  gate_count="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(len(d["human_gates"]))
' "$FLOWS")"
  assert_eq 3 "$gate_count" "flows.json declares exactly three human gates"

  (cd "$REPO" && python3 "$TOOL" check-flows >/dev/null 2>"$TMP/cf_err"); rc_cf=$?
  assert_eq 0 "$rc_cf" "check-flows passes against the real router"
  [ "$rc_cf" -ne 0 ] && echo "  stderr: $(cat "$TMP/cf_err")"

  # Bidirectional drift: mutating either side must fail closed.
  mut_router="$TMP/router.md"
  sed 's/## Flow: 修錯/## Flow: 修錯錯/' "$REPO/skill-router/SKILL.md" > "$mut_router"
  (cd "$REPO" && python3 "$TOOL" check-flows --router "$mut_router" >/dev/null 2>&1); rc_mr=$?
  assert_neq 0 "$rc_mr" "check-flows fails when the router drifts"

  mut_flows="$TMP/flows.json"
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
d["human_gates"].append({"id":"fourth-gate","label":"invented"})
json.dump(d,open(sys.argv[2],"w"))
' "$FLOWS" "$mut_flows"
  (cd "$REPO" && python3 "$TOOL" check-flows --flows "$mut_flows" >/dev/null 2>&1); rc_mf=$?
  assert_neq 0 "$rc_mf" "check-flows fails when a fourth human gate is invented"
fi

# ---------- T03/T04: render + drift gate ----------
PAGE="$REPO/docs/repo-visual.html"
# Check before this suite writes anything. Otherwise an exported page may drift
# from its public checkout, get silently regenerated here, and still report green.
(cd "$REPO" && python3 "$TOOL" render --check >/dev/null 2>"$TMP/pre_render_check_err"); rc_pre=$?
assert_eq 0 "$rc_pre" "checked-in page matches a fresh render before the suite mutates it"
if [ "$rc_pre" -ne 0 ]; then
  echo "  stderr: $(cat "$TMP/pre_render_check_err")"
fi

(cd "$REPO" && python3 "$TOOL" render >/dev/null 2>"$TMP/render_err"); rc_r=$?
assert_eq 0 "$rc_r" "render subcommand exits 0"
if [ "$rc_r" -ne 0 ]; then
  echo "  stderr: $(cat "$TMP/render_err")"
else
  assert_file "$PAGE" "render writes docs/repo-visual.html"

  # Determinism: the page must be diffable against its own regeneration.
  cp "$PAGE" "$TMP/page_a.html"
  (cd "$REPO" && python3 "$TOOL" render >/dev/null 2>&1)
  if cmp -s "$TMP/page_a.html" "$PAGE"; then
    assert_eq ok ok "two renders are byte-identical (no wall-clock in page)"
  else
    fail "two renders are byte-identical (no wall-clock in page)"
  fi

  page="$(cat "$PAGE")"

  # Self-contained: a strict offline page must not reach any external host.
  assert_not_contains "$page" 'src="http' "page loads no external scripts or images"
  assert_not_contains "$page" 'href="http' "page loads no external stylesheets or links"
  assert_not_contains "$page" "fonts.googleapis.com" "page loads no external fonts"

  # Honesty surface: the three human gates and the unverified claims must be visible.
  for gate_label in "PRD 核可" "team 設計核可" "發布核可"; do
    assert_contains "$page" "$gate_label" "page presents human gate $gate_label"
  done
  assert_contains "$page" "Unmeasured" "page presents unmeasured claim limits"
  assert_contains "$page" "absent" "page presents the absent artifact state"

  # A cold reader must learn the value and the two delivery choices before any
  # installation controls or internal contract vocabulary.  Capability packs
  # remain a separate axis instead of being presented as delivery modes.
  orientation_probe="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path

text = Path("repo-visual.html").read_text(encoding="utf-8")
header = text[text.index("<header>"):text.index("</header>")]
problems = []
for phrase in (
    "給軟體團隊與 AI 協作者共用的交付流程",
    "需求、設計、實作、驗證與發布",
    "接手時不必重新猜測上下文",
):
    if phrase not in header:
        problems.append(f"missing-value-{phrase}")
for jargon in ("artifact", "repo", "script", "runtime engine", "state machine", "scheduler"):
    if jargon in header:
        problems.append(f"jargon-before-orientation-{jargon.replace(' ', '-')}")
guide_start = text.find('<section class="mode-guide"')
lens_start = text.find('<div class="filters">')
if guide_start == -1:
    problems.append("missing-mode-guide")
else:
    guide = text[guide_start:lens_start]
    if guide.count('class="mode-card"') != 2:
        problems.append("mode-card-count")
    for handle in (
        "個人或小範圍工作",
        "需要正式需求、設計核可與 QA 驗證的團隊工作",
        "delivery mode",
        "capability pack",
    ):
        if handle not in guide:
            problems.append(f"missing-mode-explanation-{handle}")
if guide_start != -1 and lens_start != -1 and guide_start > lens_start:
    problems.append("mode-guide-after-lens")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$orientation_probe" "cold readers see purpose and delivery-mode choices before internals"

  # Evidence gaps are reader-facing tasks first and reproducibility methods
  # second.  Technical evaluation vocabulary stays available in disclosures,
  # while the primary reading path explains what each task will answer.
  todo_probe="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path

text = Path("repo-visual.html").read_text(encoding="utf-8")
problems = []
title = "<h2>待處理事項</h2>"
if title not in text:
    problems.append("missing-title")
    section = ""
else:
    section = text[text.index(title):text.index("<footer>")]
if "<h2>還沒被證明的事</h2>" in text:
    problems.append("negative-heading-remains")
if "5 項未達 supported" in text:
    problems.append("negative-summary-remains")
if section.count('<tr class="limit">') != 2:
    problems.append("todo-count-is-not-two")
if '<table class="todo-table">' not in section:
    problems.append("todo-table-missing")
if '<div class="todo-list">' in section or '<article class="limit todo-item">' in section:
    problems.append("todo-still-card-layout")
for heading in ("待處理事項", "完成後可以回答", "技術驗證方法", "目前狀態"):
    if heading not in section:
        problems.append(f"todo-column-missing-{heading}")
if "已完成" not in section or "只證明規則沒有互相矛盾" not in section:
    problems.append("supported-baseline-missing")
if "支持" in section:
    problems.append("mainland-support-term-remains")
for reader_handle in (
    "是否能更快繼續、減少重做",
    "是否交付更快、重工更少",
):
    if reader_handle not in section:
        problems.append(f"missing-reader-question-{reader_handle}")
if section.count('class="todo-question"') != 2:
    problems.append("reader-question-count")
if section.count('class="todo-result"') != 2:
    problems.append("reader-result-count")
if section.count('class="todo-method"') != 2:
    problems.append("method-count")
if '<details class="todo-method">' in section or '<summary>展開技術驗證方法</summary>' in section:
    problems.append("method-still-collapsible")
methods = " ".join(re.findall(r'<p class="todo-method">(.*?)</p>', section, re.DOTALL))
for method_handle in (
    "matched handoff experiment",
    "matched team study",
):
    if method_handle not in methods:
        problems.append(f"missing-method-handle-{method_handle}")
primary = " ".join(re.findall(r'<td class="todo-(?:task|result|status)">.*?</td>', section, re.DOTALL))
for jargon in ("arm identity", "packets", "rubric", "Luna-high", "matched handoff", "matched team"):
    if jargon in primary:
        problems.append(f"jargon-in-primary-copy-{jargon.replace(' ', '-')}")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$todo_probe" "follow-ups separate plain outcomes from technical replay methods"

  # Completed experiment evidence is presented on the page, not only removed
  # from the follow-up list, and never leaks private work-item paths.
  done_probe="$(cd "$REPO/docs" && python3 - <<'EOF'
from pathlib import Path

text = Path("repo-visual.html").read_text(encoding="utf-8")
problems = []
title = "<h2>已完成的實驗證據</h2>"
if title not in text:
    problems.append("missing-done-title")
    section = ""
else:
    section = text[text.index(title):text.index("<h2>待處理事項</h2>")]
if section.count('<tr class="done">') != 2:
    problems.append("done-count-is-not-two")
if '<table class="todo-table done-table">' not in section:
    problems.append("done-table-missing")
for handle in (
    "會增加多少模型輸入量",
    "是否認為其中一種流程品質更高",
    "17.2%",
    "描述性證據",
    "已有可重播證據",
    "零模型驗證器",
):
    if handle not in section:
        problems.append(f"missing-done-handle-{handle}")
# Each completed row carries its full inline eval report; the pending rows
# carry their progress records. Reports must not name private paths.
if section.count("展開完整 eval 報告") != 2:
    problems.append("done-report-count")
followups = text[text.index("<h2>待處理事項</h2>"):text.index("<footer>")]
if followups.count("展開目前進度的完整紀錄") != 2:
    problems.append("todo-report-count")
for report_handle in ("Attempt 歷史", "固定條件", "已完成的 pilot", "已預先註冊的研究方案"):
    if report_handle not in section + followups:
        problems.append(f"missing-report-handle-{report_handle}")
if "docs/work" in section or "docs/work" in followups:
    problems.append("done-section-leaks-private-path")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$done_probe" "completed experiment evidence is presented without private paths"

  test_catalog_probe="$(cd "$REPO/docs" && python3 - <<'EOF'
import json
import re
from pathlib import Path

text = Path("repo-visual.html").read_text(encoding="utf-8")
model = json.loads(
    re.search(r'<script id="model" type="application/json">(.*?)</script>', text, re.DOTALL)
    .group(1)
    .replace("\\u003c", "<")
)
start = text.find("<h2>驗證</h2>")
end = text.find("</details><!-- engineering-details -->")
section = text[start:end]
problems = []
if section.count('class="test-table"') != 3:
    problems.append("test-catalog-group-count")
if ".rosterwrap{display:grid;gap:11px;grid-template-columns:minmax(0,1fr)}" not in text:
    problems.append("test-catalog-groups-still-split-horizontally")
if ".test-table{min-width:0;table-layout:fixed}" not in text:
    problems.append("test-catalog-description-column-can-overflow")
for entry in model["tests"]["roster"]:
    if not entry.get("description"):
        problems.append(f"missing-description-{entry['name']}")
    elif entry["description"] not in section:
        problems.append(f"description-not-rendered-{entry['name']}")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$test_catalog_probe" "verification catalog explains every public test"

  build_probe="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path

text = Path("repo-visual.html").read_text(encoding="utf-8")
problems = []
if '<div class="flow build-flow" data-flow="build">' not in text:
    problems.append("build-flow-class-missing")
if '<div class="variant"><div class="variant-name"><span class="vname chip" data-mode="team-feature"' not in text:
    problems.append("team-feature-unit-label-missing")
if '<div class="variant"><div class="variant-name"><span class="vname chip" data-mode="team-feature"' in text and '<div class="variant-flow"><span class="chip" data-skill="prd-interview"' not in text:
    problems.append("team-feature-following-flow-not-separated")
if not re.search(r'<div class="variant-separator"[^>]*></div>', text):
    problems.append("unit-separator-missing")
if "margin-inline:16px" not in text:
    problems.append("unit-separator-not-mx-4")
if ".flow.build-flow{background:var(--build-bg)" not in text:
    problems.append("build-flow-dark-token-missing")
if "--build-bg:#" not in text:
    problems.append("build-palette-missing")
if "border-left:4px solid var(--build-accent)" in text:
    problems.append("build-flow-accent-edge-remains")
if ".flow.build-flow h3{display:inline-block;background:#000;color:#fff" in text:
    problems.append("build-heading-still-black")
if ".flow.build-flow .variant .vname.chip{background:#000;border-color:#fff;color:#fff" not in text:
    problems.append("build-unit-label-white-border-missing")
if ".todo-table tr.limit td{background:var(--panel)}" not in text:
    problems.append("todo-red-background-remains")
if '<details class="todo-method">' in text:
    problems.append("todo-method-is-collapsible")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$build_probe" "build flow has a distinct dark visual treatment"

  # The long catalogue and contract rosters remain one disclosure away without
  # competing with the overview.  The follow-up section stays outside it.
  details_probe="$(cd "$REPO/docs" && python3 - <<'EOF'
from pathlib import Path

text = Path("repo-visual.html").read_text(encoding="utf-8")
problems = []
start = text.find('<details class="engineering-details">')
end = text.find('</details><!-- engineering-details -->')
if start == -1 or end == -1 or end < start:
    problems.append("missing-engineering-disclosure")
else:
    details = text[start:end]
    for heading in ("個技能", "Artifact 契約", "交付狀態", "驗證"):
        if heading not in details:
            problems.append(f"missing-detail-{heading}")
    followups = text.find("<h2>待處理事項</h2>")
    if followups == -1:
        problems.append("missing-followups-heading")
    elif followups < end:
        problems.append("followups-trapped-in-engineering-details")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$details_probe" "engineering catalogues use one level of progressive disclosure"

  # Identity describes the contracts, not the checkout. A page stamped with HEAD
  # would be invalidated by every commit -- including the commit that adds it --
  # so the drift gate could never be green.
  head_commit="$(cd "$REPO" && git rev-parse HEAD 2>/dev/null || echo none)"
  assert_not_contains "$page" "$head_commit" "page identity is independent of HEAD"
  probe '
import hashlib, json, sys
m = json.load(open(sys.argv[1]))
described = {k: v for k, v in m.items() if k != "identity"}
canonical = json.dumps(described, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
want = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]
print("" if m["identity"]["content_digest"] == want else f"{m[chr(34)+chr(34)] if False else m}")
' "content digest matches the described model"
  assert_eq "" "$PROBE_OUT" "content digest matches the described model"
  assert_contains "$page" 'href="../' "repository page links to real repo files"

  # The "how to use" card must be actionable: where to change the selection and
  # what to run afterwards, not just which words to choose.
  for handle in "delivery_mode" "capability_packs" "onboard.sh" "project-manifest.md"; do
    assert_contains "$page" "$handle" "usage card names $handle"
  done

  # Positioning is prose, not metadata. Schema versions and the digest belong in
  # the footer; technical non-goals belong in the engineering disclosure rather
  # than taking over the cold-reader header.
  probe_regions="$(cd "$REPO/docs" && python3 - <<'EOF'
import json, re
from pathlib import Path
text = Path("repo-visual.html").read_text(encoding="utf-8")
model = json.loads(
    re.search(r'<script id="model" type="application/json">(.*?)</script>', text, re.DOTALL)
    .group(1).replace("\\u003c", "<")
)
head = text[text.index("<header>"):text.index("</header>")]
footer = text[text.index("<footer>"):text.index("</footer>")]
problems = []
engineering_start = text.find('<details class="engineering-details">')
engineering_end = text.find('</details><!-- engineering-details -->')
if engineering_start == -1 or engineering_end == -1:
    engineering = ""
    problems.append("engineering-details-missing")
else:
    engineering = text[engineering_start:engineering_end]
if "runtime-engine" in head:
    problems.append("non-goals-still-raw-in-header")
if "runtime engine" in head:
    problems.append("non-goals-still-in-reader-header")
if "runtime engine" not in engineering:
    problems.append("non-goals-missing-from-engineering-details")
digest = model["identity"]["content_digest"]
if digest in head:
    problems.append("digest-still-in-header")
if digest not in footer:
    problems.append("digest-missing-from-footer")
if model["identity"]["work_item_schema"] not in text[text.index("Artifact 契約"):]:
    problems.append("work-item-schema-not-next-to-contract")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$probe_regions" "positioning is prose and build metadata sits in the footer"

  # The profile lens is page-level: it must sit above the first section, stick to
  # the viewport, and mark out-of-bundle skills instead of removing them. Removing
  # a chip from a flow chain leaves dangling arrows and misreports the flow.
  probe_lens="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path
text = Path("repo-visual.html").read_text(encoding="utf-8")
markup = re.sub(r"<script\b.*?</script>", "", text, flags=re.DOTALL)
script = "".join(re.findall(r"<script>(.*?)</script>", text, re.DOTALL))
problems = []
if markup.index('class="filters"') > markup.index('class="cards"'):
    problems.append("lens-below-first-section")
if not re.search(r"\.filters\{[^}]*position:sticky", text):
    problems.append("lens-not-sticky")
if "data-out" not in text:
    problems.append("no-out-of-bundle-state")
if "style.display" in script:
    problems.append("filter-still-removes-nodes")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$probe_lens" "profile lens is page-level and marks instead of removing"

  responsive_reader_probe="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path

text = Path("repo-visual.html").read_text(encoding="utf-8")
css = text[text.index(":root{"):text.index("</style>")]
problems = []
filters = re.search(r"\.filters\{([^}]*)\}", css)
if not filters or "overflow-x:auto" not in filters.group(1):
    problems.append("lens-not-horizontally-scrollable")
mobile = css[css.index("@media (max-width:640px){"):css.index("@media (prefers-reduced-motion:reduce)")]
if ".filters{flex-wrap:nowrap" not in mobile:
    problems.append("mobile-lens-still-wraps")
if "scroll-margin-top" not in css:
    problems.append("headings-have-no-sticky-offset")
if ".todo-table{min-width:940px}" not in mobile:
    problems.append("mobile-followups-not-scrollable-table")
if ".todo-table-wrap{overflow-x:auto" not in css:
    problems.append("mobile-followups-wrapper-not-scrollable")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$responsive_reader_probe" "mobile lens and follow-ups preserve section context"

  probe_gate_lens="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path
text = Path("repo-visual.html").read_text(encoding="utf-8")
problems = []
if 'data-na' not in text:
    problems.append("no-not-applicable-state")
if 'gate-na-label' not in text:
    problems.append("hero-has-no-not-applicable-label")
if not re.search(r'\[data-gate\]\[data-na=true\]', text):
    problems.append("gate-state-not-styled")
if 'applicable_gates' not in text:
    problems.append("lens-does-not-read-derived-gates")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$probe_gate_lens" "profile lens marks inapplicable gates without removing them"

  # A variant name is metadata for the following sequence, not the first node in
  # that sequence.  Keep the two regions structurally separate so the mobile
  # layout can always put the name on its own row instead of relying on accidental
  # flex wrapping at particular label and chip widths.
  probe_variant_layout="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path

text = Path("repo-visual.html").read_text(encoding="utf-8")
variant_count = len(re.findall(r'class="variant"', text))
flow_count = len(re.findall(r'class="variant-flow"', text))
problems = []
if flow_count != variant_count:
    problems.append(f"variant-flow-count={flow_count}/{variant_count}")
if not re.search(r'<div class="variant"><div class="variant-name"><span class="vname(?: chip)?"[^>]*>.*?</span></div><div class="variant-separator"[^>]*></div><div class="variant-flow">', text):
    problems.append("name-and-flow-not-separated")
if ".variant{display:grid;" not in text or ".variant-separator{" not in text or ".variant-flow{display:flex;" not in text:
    problems.append("desktop-regions-not-explicit")
if not re.search(r"\.variant \.vname\{[^}]*white-space:nowrap", text):
    problems.append("unit-label-can-wrap")
if "@media (max-width:640px){" not in text or not re.search(r"\.variant\{grid-template-columns:minmax\(0,1fr\);gap:7px\}", text):
    problems.append("mobile-name-row-not-explicit")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$probe_variant_layout" "variant names stay separate from mobile flow sequences"

  # Detail view is a modal dialog, not a side drawer.
  assert_contains "$page" "<dialog" "detail view uses a native dialog element"
  assert_contains "$page" "showModal" "dialog opens as a modal"
  assert_not_contains "$page" 'class="drawer"' "no side drawer remains"
  assert_contains "$page" "::backdrop" "dialog backdrop is styled"

  # Readability floor: body text and the smallest labels must not regress.
  probe_css="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path
css = Path("repo-visual.html").read_text(encoding="utf-8")
stylesheet = css[css.index(":root{"):css.index("</style>")]
inline = css[css.index("</style>"):]
css = stylesheet
problems = []

# The scale is a closed set of four steps: page title, section/card title, body, note.
tokens = {name: float(value) for name, value in
          re.findall(r"(--fs-[a-z0-9]+):\s*([0-9.]+)px", css)}
expected = {"--fs-h1": 28.0, "--fs-title": 18.0, "--fs-body": 16.0, "--fs-note": 14.0}
if tokens != expected:
    problems.append(f"scale={tokens}")

# Nothing may bypass the scale with an ad-hoc pixel size.
adhoc = re.findall(r"font-size:\s*([0-9.]+)px", css + inline)
if adhoc:
    problems.append("adhoc-sizes=" + ",".join(sorted(set(adhoc))))
print(" ".join(problems))
EOF
)"
  assert_eq "" "$probe_css" "type scale is a closed four-step set"

  probe_contrast="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path

def luminance(hexcolour):
    r, g, b = (int(hexcolour[i:i + 2], 16) / 255 for i in (0, 2, 4))
    def channel(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = channel(r), channel(g), channel(b)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def ratio(fg, bg):
    a, b = luminance(fg), luminance(bg)
    lighter, darker = max(a, b), min(a, b)
    return (lighter + 0.05) / (darker + 0.05)

css = Path("repo-visual.html").read_text(encoding="utf-8")
blocks = {
    "light": css[css.index(":root{"):css.index("@media (prefers-color-scheme:dark)")],
    "dark": css[css.index("@media (prefers-color-scheme:dark)"):css.index("*{box-sizing")],
}
problems = []
for theme, block in blocks.items():
    tokens = dict(re.findall(r"(--[a-z0-9-]+):(#[0-9a-fA-F]{6})", block))
    ground = tokens["--bg"].lstrip("#")
    for name in ("--ink", "--muted", "--dim"):
        got = ratio(tokens[name].lstrip("#"), ground)
        floor = {"--ink": 15.0, "--muted": 11.0, "--dim": 8.0}[name]
        if got < floor:
            problems.append(f"{theme}{name}={got:.1f}<{floor}")
print(" ".join(problems))
EOF
)"
  assert_eq "" "$probe_contrast" "text tokens clear their contrast floor in both themes"

  # Privacy boundary holds through rendering too.
  assert_not_contains "$page" "docs/work/" "page carries no docs/work content"
  assert_not_contains "$page" "STATUS.md" "page carries no STATUS.md content"

  # T04 drift gate: --check must accept a fresh page and reject a mutated one.
  (cd "$REPO" && python3 "$TOOL" render --check >/dev/null 2>&1); rc_ck=$?
  assert_eq 0 "$rc_ck" "render --check accepts a freshly generated page"

  printf '\n<!-- hand edit -->\n' >> "$PAGE"
  (cd "$REPO" && python3 "$TOOL" render --check >/dev/null 2>&1); rc_ck2=$?
  assert_neq 0 "$rc_ck2" "render --check rejects a hand-edited page"
  cp "$TMP/page_a.html" "$PAGE"

  # Missing-source direction: absence must fail closed, never read as "nothing to check".
  mv "$PAGE" "$TMP/parked.html"
  (cd "$REPO" && python3 "$TOOL" render --check >/dev/null 2>&1); rc_ck3=$?
  assert_neq 0 "$rc_ck3" "render --check fails closed when the page is missing"
  mv "$TMP/parked.html" "$PAGE"

  (cd "$REPO" && python3 "$TOOL" check-flows --flows "$TMP/does-not-exist.json" >/dev/null 2>&1); rc_mis=$?
  assert_neq 0 "$rc_mis" "check-flows fails closed when the declaration is missing"

  # Every static repo link must resolve. Script blocks are excluded on purpose:
  # drawer links are built at runtime from model paths, and those paths already
  # have their own existence assertion above.
  probe_page="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path
text = Path("repo-visual.html").read_text(encoding="utf-8")
markup = re.sub(r"<script\b.*?</script>", "", text, flags=re.DOTALL)
bad = sorted({h for h in re.findall(r'href="(\.\./[^"#]+)"', markup) if not Path(h).exists()})
print(" ".join(bad))
EOF
)"
  assert_eq "" "$probe_page" "every repo link on the page resolves"

  # Interaction wiring: every clickable handle in the static markup must resolve to
  # something the drawer can actually open. Without this, a renamed skill silently
  # produces a chip that does nothing when clicked.
  dead="$(cd "$REPO/docs" && python3 - <<'EOF'
import json, re
from pathlib import Path
text = Path("repo-visual.html").read_text(encoding="utf-8")
model = json.loads(
    re.search(r'<script id="model" type="application/json">(.*?)</script>', text, re.DOTALL)
    .group(1)
    .replace("\\u003c", "<")
)
markup = re.sub(r"<script\b.*?</script>", "", text, flags=re.DOTALL)
skills = {s["name"] for s in model["skills"]}
gates = {g["id"] for g in model["human_gates"]}
modes = set(model["execution_modes"])
dead = []
for name, value in re.findall(r'data-(skill|gate|mode|node)="([^"]+)"', markup):
    if name == "skill" and value not in skills:
        dead.append(f"skill:{value}")
    elif name == "gate" and value not in gates:
        dead.append(f"gate:{value}")
    elif name == "mode" and value not in modes:
        dead.append(f"mode:{value}")
    elif name == "node":
        # No exemption list. A handle that cannot open anything is a dead click,
        # and a dead click that still shows a pointer cursor is worse than none.
        target = value[5:] if value.startswith("gate-") else value
        if target not in gates and target not in skills:
            dead.append(f"node:{value}")
print(" ".join(sorted(set(dead))))
EOF
)"
  assert_eq "" "$dead" "every clickable handle resolves to a model entry"

  probe_pointer="$(cd "$REPO/docs" && python3 - <<'EOF'
import re
from pathlib import Path
text = Path("repo-visual.html").read_text(encoding="utf-8")
markup = re.sub(r"<script\b.*?</script>", "", text, flags=re.DOTALL)
problems = []
for group in re.findall(r"<g class=\"node[^\"]*\"[^>]*>", markup):
    if not re.search(r'data-(skill|gate|mode|node)="', group):
        problems.append(group[:60])
print(" ".join(problems))
EOF
)"
  assert_eq "" "$probe_pointer" "every pointer-styled hero node carries a handle"

  # The embedded payload must be the same model the CLI emits.
  embedded="$(cd "$REPO/docs" && python3 - <<'EOF'
import json, re
from pathlib import Path
text = Path("repo-visual.html").read_text(encoding="utf-8")
raw = re.search(r'<script id="model" type="application/json">(.*?)</script>', text, re.DOTALL).group(1)
print(json.dumps(json.loads(raw.replace("\\u003c", "<")), sort_keys=True, ensure_ascii=False))
EOF
)"
  (cd "$REPO" && python3 "$TOOL" model > "$TMP/cli.json")
  cli_model="$(python3 - "$TMP/cli.json" <<'EOF'
import json, sys
print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True, ensure_ascii=False))
EOF
)"
  if [ "$embedded" = "$cli_model" ]; then
    assert_eq ok ok "embedded payload equals the CLI model"
  else
    fail "embedded payload equals the CLI model"
  fi

  # Hosted variant: the publish host supplies the document shell, so the fragment
  # must not carry one, and repo paths must not become dead links.
  frag="$TMP/artifact.html"
  (cd "$REPO" && python3 "$TOOL" render --artifact --out "$frag" >/dev/null 2>&1); rc_a=$?
  assert_eq 0 "$rc_a" "render --artifact exits 0"
  if [ "$rc_a" -eq 0 ]; then
    fragment="$(cat "$frag")"
    assert_not_contains "$fragment" "<!DOCTYPE" "hosted fragment carries no document shell"
    assert_not_contains "$fragment" "<body" "hosted fragment carries no body tag"
    assert_contains "$fragment" "<title>" "hosted fragment names itself"
    assert_not_contains "$fragment" 'href="../' "hosted fragment has no unresolvable repo links"
    assert_not_contains "$fragment" "docs/work/" "hosted fragment carries no docs/work content"
    assert_not_contains "$fragment" "STATUS.md" "hosted fragment carries no STATUS.md content"
    # Same data, different frame: the payload must be identical to the repo page.
    frag_payload="$(python3 - "$frag" <<'EOF'
import json, re, sys
from pathlib import Path
raw = re.search(r'<script id="model" type="application/json">(.*?)</script>',
                Path(sys.argv[1]).read_text(encoding="utf-8"), re.DOTALL).group(1)
print(json.dumps(json.loads(raw.replace("\\u003c", "<")), sort_keys=True, ensure_ascii=False))
EOF
)"
    if [ "$frag_payload" = "$cli_model" ]; then
      assert_eq ok ok "hosted fragment carries the same model as the repo page"
    else
      fail "hosted fragment carries the same model as the repo page"
    fi
  fi

  # Public-site variant: unlike the host-supplied Artifact fragment, this is a
  # complete document.  Its detail exits must resolve to the public source repo
  # instead of retaining checkout-relative links that would break on Vercel.
  site="$TMP/site.html"
  source_base="https://github.com/Chuliying/skill-commons/blob/main/"
  (cd "$REPO" && python3 "$TOOL" render --source-base "$source_base" --out "$site" >/dev/null 2>&1); rc_site=$?
  assert_eq 0 "$rc_site" "render --source-base exits 0"
  if [ "$rc_site" -eq 0 ]; then
    site_page="$(cat "$site")"
    assert_contains "$site_page" "<!DOCTYPE html>" "public-site render carries a document shell"
    assert_contains "$site_page" "$source_base" "public-site detail exits use the public source repo"
    assert_contains "$site_page" 'target="_blank"' "public-site source links declare a new browsing context"
    assert_contains "$site_page" 'rel="noreferrer"' "public-site source links suppress referrer data"
    assert_not_contains "$site_page" 'href="../' "public-site render has no checkout-relative links"
    site_payload="$(python3 - "$site" <<'EOF'
import json, re, sys
from pathlib import Path
raw = re.search(r'<script id="model" type="application/json">(.*?)</script>',
                Path(sys.argv[1]).read_text(encoding="utf-8"), re.DOTALL).group(1)
print(json.dumps(json.loads(raw.replace("\\u003c", "<")), sort_keys=True, ensure_ascii=False))
EOF
)"
    if [ "$site_payload" = "$cli_model" ]; then
      assert_eq ok ok "public-site render carries the same model as the repo page"
    else
      fail "public-site render carries the same model as the repo page"
    fi
  fi
fi

finish
