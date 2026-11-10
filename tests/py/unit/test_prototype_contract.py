"""Executable regressions for prototype-contract false accepts, not UI-quality scores."""
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / "prototype/scripts"
TEMPLATES = ROOT / "prototype/templates"
# Throwaway repos must not follow an inherited GIT_DIR (e.g. inside a hook) into a real repo.
GIT_ENV = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}


def git(repo, *args):
    return subprocess.run(["git", "-c", "user.name=Prototype Test", "-c", "user.email=prototype@example.invalid",
                           "-c", "commit.gpgsign=false", *args],
                          cwd=repo, env=GIT_ENV, check=True, capture_output=True)


def valid_map(shell="standard"):
    return {
        "meta": {"schemaVersion": 2, "projectName": "Demo", "subtitle": "",
                 "prdVersion": "v1", "shellType": shell,
                 "createdAt": "2026-09-15T00:00:00Z", "frozenAt": "2026-09-15T00:00:00Z",
                 "coverageRate": 100, "gaps": []},
        "routes": {"s1": {"name": "Start", "pages": ["home"]}},
        "pages": {"home": {"label": "Home", "type": "surface", "frameRef": "frame-home",
                           "acs": [{"id": "AC-001", "text": "Show welcome"}]}},
        "frames": {"frame-home": {"shell": "content", "sections": [
            {"row": 1, "label": "Welcome", "span": 12}]}},
    }


def routed_map(routes, steps=None):
    """Otherwise-valid map with the given route layout; steps maps (page, field) to a target."""
    data = valid_map()
    home = data["pages"].pop("home")
    data["routes"] = {sid: {"name": sid.upper(), "pages": list(pages)} for sid, pages in routes.items()}
    for page_id in dict.fromkeys(page for pages in routes.values() for page in pages):
        data["pages"][page_id] = dict(copy.deepcopy(home), label=page_id.title())
    for (page_id, field), target in (steps or {}).items():
        data["pages"][page_id][field] = target
    return data


# Node VM prelude: a fake DOM (ID lookup plus the fields engine.js writes) and a localStorage stub.
# load(state, frames) runs runtime-data.js, a frames.js stand-in and engine.js in page order.
ENGINE_VM = r'''const fs=require('fs'), vm=require('vm'), assert=require('assert');
const [mapText, runtime, engine]=process.argv.slice(1).map(path=>fs.readFileSync(path,'utf8'));
function load(state, frames){
  const nodes={};
  const node=id=>nodes[id]||(nodes[id]={innerHTML:'',textContent:'',style:{},
   classList:{add(){},remove(){}},querySelectorAll:()=>[],contains:()=>true});
  node('prototype-map').textContent=mapText; node('scenario-state').textContent=state;
  const context={document:{getElementById:node,querySelector:()=>null,querySelectorAll:()=>[]},
   localStorage:{store:{},getItem(key){return this.store[key]??null;},setItem(key,value){this.store[key]=String(value);}},
   window:{}};
  vm.createContext(context);
  for(const code of [runtime,frames,engine]) vm.runInContext(code,context);
  return {context,nodes};
}
'''


class PrototypeContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.map = self.root / "map.json"
        self.html = self.root / "index.html"
        self.data = valid_map()
        self.write_map()

    def write_map(self):
        self.map.write_text(json.dumps(self.data), encoding="utf-8")

    def validate(self):
        self.write_map()
        return subprocess.run(["bash", str(SCRIPTS / "validate-map.sh"), str(self.map)],
                              capture_output=True, text=True)

    def validate_json(self):
        self.write_map()
        result = subprocess.run(["bash", str(SCRIPTS / "validate-map.sh"), "--json", str(self.map)],
                                capture_output=True, text=True)
        self.assertNotIn("Traceback", result.stderr)
        return result.returncode, json.loads(result.stdout)

    def verify(self):
        return subprocess.run(["python3", str(SCRIPTS / "verify-freeze.py"),
                               "--map", str(self.map), "--html", str(self.html)],
                              capture_output=True, text=True)

    def run_engine(self, script):
        """Run ENGINE_VM plus `script` in Node against self.data and the fixed templates."""
        self.write_map()
        return subprocess.run(["node", "-e", ENGINE_VM + script, str(self.map), str(TEMPLATES / "runtime-data.js"),
                               str(TEMPLATES / "engine.js")], capture_output=True, text=True)

    def bundle(self, state=None, output=None):
        """Write the generator inputs next to self.map and run it into `output` (default self.root)."""
        self.write_map()
        (self.root / "state.json").write_text(
            json.dumps({sid: {} for sid in self.data["routes"]} if state is None else state))
        (self.root / "frames.js").write_text(
            'var FRAME_REGISTRY = {"frame-home": function(ctx) {'
            'return "<button class=\\"c-welcome\\">Welcome</button>";}};')
        (self.root / "library.css").write_text(".c-welcome {padding: 1rem;}")
        return subprocess.run(["python3", str(SCRIPTS / "prototype_bundle.py"),
                               "--map", str(self.map), "--state", str(self.root / "state.json"),
                               "--frames", str(self.root / "frames.js"),
                               "--library", str(self.root / "library.css"),
                               "--output", str(output or self.root)], capture_output=True, text=True)

    def fixture(self):
        result = self.bundle()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        result = self.verify()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def check_repair(self, base, fixed, *allow, base_rev=None, cwd=None):
        """Hash the base bytes as they are now and check the `fixed` map as the candidate."""
        candidate = self.root / "candidate.json"
        candidate.write_text(json.dumps(fixed))
        args = ["python3", str(SCRIPTS / "check-repair.py"), "--base", str(base), "--candidate", str(candidate),
                "--base-sha256", hashlib.sha256(base.read_bytes()).hexdigest()]
        args += [arg for path in allow for arg in ("--allow", path)]
        if base_rev is not None:
            args.append("--base-rev=" + base_rev)  # one argument, so option-like values reach the checker
        return subprocess.run(args, cwd=cwd, env=GIT_ENV, capture_output=True, text=True)

    def test_supported_map(self):
        self.assertEqual(0, self.validate().returncode)

    def test_rejects_invalid_contract_values(self):
        mutations = {
            "unknown version": lambda m: m["meta"].update(schemaVersion=999),
            "unknown field": lambda m: m["pages"]["home"].update(typo="hidden"),
            "string version": lambda m: m["meta"].update(schemaVersion="2"),
            "bool version": lambda m: m["meta"].update(schemaVersion=True),
            "coverage range": lambda m: m["meta"].update(coverageRate=999),
            "boolean coverage": lambda m: m["meta"].update(coverageRate=True),
            "AC missing fields": lambda m: m["pages"]["home"].update(acs=[{}]),
            "AC wrong type": lambda m: m["pages"]["home"].update(acs="AC-001"),
            "span type": lambda m: m["frames"]["frame-home"]["sections"][0].update(span="wide"),
            "span float": lambda m: m["frames"]["frame-home"]["sections"][0].update(span=1.5),
            "span bool": lambda m: m["frames"]["frame-home"]["sections"][0].update(span=True),
            "orphan page": lambda m: m["pages"].update(orphan=copy.deepcopy(m["pages"]["home"])),
            "page enum": lambda m: m["pages"]["home"].update(type="unknown"),
            # Routed, so the ID denylist is the only error; an unrouted page also fails as unreachable.
            "prototype key": lambda m: (m["pages"].update(__proto__=copy.deepcopy(m["pages"]["home"])),
                                        m["routes"]["s1"]["pages"].append("__proto__")),
            "missing route page": lambda m: m["routes"]["s1"].update(pages=["missing"]),
            "route ID object": lambda m: m["routes"]["s1"].update(pages=[{"id": "home"}]),
            "numeric route order": lambda m: m["routes"].update({"1": {"name": "Numeric", "pages": ["home"]}}),
            "route collides with shell": lambda m: m["routes"].update(state={"name": "State", "pages": ["home"]}),
            "page collides with route": lambda m: (m["pages"].update(s1=copy.deepcopy(m["pages"]["home"])), m["routes"].update(scenario={"name": "Other", "pages": ["s1"]})),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label):
                self.data = valid_map()
                mutate(self.data)
                result = self.validate()
                self.assertNotEqual(0, result.returncode, result.stdout)
                self.assertNotIn("Traceback", result.stderr)
                self.assertNotIn("integer expression expected", result.stderr)

    def test_single_defect_reports_its_exact_error(self):
        # Each map is otherwise valid, so the rule under test is the only one that can reject it.
        def edited(change):
            data = valid_map()
            change(data)
            return data

        def home(data):
            return data["pages"]["home"]

        flow_steps = {(page, field): value for page in ("home", "queue")
                      for field, value in (("type", "flow-step"), ("flowId", "apply"))}
        cases = {
            "route ID __proto__": (
                edited(lambda m: m.update(routes={"__proto__": m["routes"]["s1"]})),
                [("/routes/__proto__", "unsafe identifier")]),
            "page ID constructor, routed": (
                routed_map({"s1": ["constructor"]}),
                [("/pages/constructor", "unsafe identifier")]),
            "frame ID prototype": (
                edited(lambda m: m["frames"].update(prototype=copy.deepcopy(m["frames"]["frame-home"]))),
                [("/frames/prototype", "unsafe identifier")]),
            "frameRef constructor, no frame catalog": (
                edited(lambda m: (m.pop("frames"), home(m).update(frameRef="constructor"))),
                [("/pages/home/frameRef", "unsafe frame identifier")]),
            "frameRef missing from frame catalog": (
                edited(lambda m: home(m).update(frameRef="frame-missing")),
                [("/pages/home/frameRef", "unknown frame reference")]),
            # The second "home" also repeats the generated frame ID s1-home, reported at the same path.
            "page listed twice in a route": (
                edited(lambda m: m["routes"]["s1"]["pages"].append("home")),
                [("/routes/s1/pages/1", "duplicate page reference"),
                 ("/routes/s1/pages/1", "ambiguous generated DOM id")]),
            "flowId across two routes": (
                routed_map({"s1": ["home"], "s2": ["queue"]}, flow_steps),
                [("/pages", "flowId apply must belong to exactly one route")]),
            "isHint not boolean": (
                edited(lambda m: home(m)["acs"][0].update(isHint="yes")),
                [("/pages/home/acs/0/isHint", "must be boolean")]),
            "frozenAt without timezone": (
                edited(lambda m: m["meta"].update(frozenAt="2026-09-15T00:00:00")),
                [("/meta/frozenAt", "must be an ISO timestamp with timezone")]),
            "abbreviated PRD reference": (
                edited(lambda m: home(m)["acs"][0].update(prd="同上")),
                [("/pages/home/acs/0/prd", "expand abbreviated PRD reference")]),
            "gap without reason": (
                edited(lambda m: m["meta"].update(gaps=[{"prdAcId": "PRD-7", "description": "Export to CSV",
                                                         "acknowledgedBy": "PM"}])),
                [("/meta/gaps/0/reason", "must be a non-empty string")]),
            "duplicate section row": (
                edited(lambda m: m["frames"]["frame-home"]["sections"].append(
                    {"row": 1, "label": "Footer", "span": 12})),
                [("/frames/frame-home/sections/1/row", "duplicate row")]),
            # json.dumps writes these floats as bare NaN/Infinity, which JSON does not allow.
            "NaN literal": (
                edited(lambda m: m["meta"].update(coverageRate=float("nan"))),
                [("", "non-JSON number: NaN")]),
            "Infinity literal": (
                edited(lambda m: m["meta"].update(backfillRound=float("inf"))),
                [("", "non-JSON number: Infinity")]),
        }
        for label, (data, expected) in cases.items():
            with self.subTest(label=label):
                self.data = data
                code, report = self.validate_json()
                self.assertEqual(expected, [(error["path"], error["message"]) for error in report["errors"]])
                self.assertEqual((1, False), (code, report["pass"]))

    def test_step_targets_stay_in_every_route_of_their_page(self):
        # G5 frames call goTo(ctx.sid, ctx.nextStep); the target needs a frame in that same route.
        rejected = {
            "cross-route nextStep": ({"s1": ["home"], "s2": ["queue"]},
                                     {("home", "nextStep"): "queue"}, "/pages/home/nextStep", "s1"),
            "cross-route backStep": ({"s1": ["home"], "s2": ["queue"]},
                                     {("queue", "backStep"): "home"}, "/pages/queue/backStep", "s2"),
            "shared page, target in one route": ({"s1": ["home", "review"], "s2": ["home"]},
                                                 {("home", "nextStep"): "review"}, "/pages/home/nextStep", "s2"),
        }
        for label, (routes, steps, path, route) in rejected.items():
            with self.subTest(label=label):
                self.data = routed_map(routes, steps)
                code, report = self.validate_json()
                self.assertEqual([path], [error["path"] for error in report["errors"]])
                self.assertRegex(report["errors"][0]["message"], rf"\broute {route}\b")
                self.assertEqual(1, code)
        accepted = {
            "same-route steps": ({"s1": ["home", "review"]},
                                 {("home", "nextStep"): "review", ("review", "backStep"): "home"}),
            "shared page, target in every route": ({"s1": ["home", "review"], "s2": ["review", "home"]},
                                                   {("home", "nextStep"): "review"}),
            "self target": ({"s1": ["home"]}, {("home", "nextStep"): "home"}),
        }
        for label, (routes, steps) in accepted.items():
            with self.subTest(label=label):
                self.data = routed_map(routes, steps)
                code, report = self.validate_json()
                self.assertEqual((0, []), (code, report["errors"]))
        with self.subTest(label="target missing from pages"):
            self.data = routed_map({"s1": ["home"]}, {("home", "nextStep"): "missing"})
            code, report = self.validate_json()
            self.assertEqual([{"path": "/pages/home/nextStep", "message": "unknown page reference"}],
                             report["errors"])

    def test_step_target_check_survives_malformed_routes_and_pages(self):
        mutations = {
            "routes not an object": lambda m: m.update(routes=["home"]),
            "route not an object": lambda m: m["routes"].update(s2="review"),
            "route pages not an array": lambda m: m["routes"]["s1"].update(pages="home"),
            "route page not a string": lambda m: m["routes"]["s1"]["pages"].append({"id": "review"}),
            "target page not an object": lambda m: m["pages"].update(review="review"),
            "target not a string": lambda m: m["pages"]["home"].update(nextStep=["review"]),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label):
                self.data = routed_map({"s1": ["home", "review"]}, {("home", "nextStep"): "review"})
                mutate(self.data)
                code, report = self.validate_json()
                self.assertEqual((1, False), (code, report["pass"]))

    def test_comment_only_html_is_not_a_bundle(self):
        self.fixture()
        self.html.write_text('<!-- assets/component-library.css PROTOTYPE_MAP FRAME_REGISTRY '
                             'SCENARIO_STATE scenario-s1 s1-home frame-home AC-001 -->')
        self.assertNotEqual(0, self.verify().returncode)

    def test_engine_tampering_rejected(self):
        self.fixture()
        (self.root / "assets/engine.js").write_text('throw Error("broken");')
        self.assertNotEqual(0, self.verify().returncode)

    def test_changed_frozen_content_rejected(self):
        self.fixture()
        self.data["pages"]["home"]["acs"][0]["text"] = "Different requirement"
        self.write_map()
        self.assertNotEqual(0, self.verify().returncode)

    def test_generated_standard_and_flow(self):
        for shell in ("standard", "flow"):
            with self.subTest(shell=shell):
                self.data = valid_map(shell)
                self.fixture()
                result = self.verify()
                self.assertEqual(0, result.returncode, result.stdout)
                self.assertIn(f"assets/shell-{shell}.css", self.html.read_text())

    def test_script_like_text_stays_data(self):
        self.data["pages"]["home"]["acs"][0]["text"] = '</script><script>throw Error("injected")</script>'
        self.data["meta"]["projectName"] = '<img src=x onerror="alert(1)">'
        self.fixture()
        self.assertNotIn('</script><script>throw', self.html.read_text())
        self.assertNotIn('<img src=x', self.html.read_text())

    def test_generated_nav_renders_route_name_as_text(self):
        self.data["routes"]["s1"]["name"] = "<img src=x onerror=1>"
        self.fixture()
        html = self.html.read_text()
        self.assertNotIn("<img", html)
        self.assertIn(">&lt;img src=x onerror=1&gt;</li>", html)

    def test_placeholder_like_text_is_not_reinterpreted(self):
        self.data["meta"]["projectName"] = "{{PROTOTYPE_MAP_JSON}}"
        self.data["pages"]["home"]["acs"][0]["text"] = "{{SCENARIO_STATE_JSON}} assets/shell-standard.css"
        self.data["meta"]["shellType"] = "flow"
        self.fixture()
        self.assertIn('<title>{{PROTOTYPE_MAP_JSON}}', self.html.read_text())

    def test_shell_tampering_rejected(self):
        self.fixture()
        self.html.write_text(self.html.read_text().replace('id="s1-home"', 'id="missing"'))
        self.assertNotEqual(0, self.verify().returncode)

    def test_asset_symlink_rejected(self):
        self.fixture()
        path = self.root / "assets/engine.js"
        path.unlink()
        path.symlink_to(TEMPLATES / "engine.js")
        self.assertNotEqual(0, self.verify().returncode)

    def test_index_symlink_rejected(self):
        self.fixture()
        real = self.root / "index-real.html"
        self.html.rename(real)
        self.html.symlink_to(real)  # same bytes, so only the symlink check can object
        result = self.verify()
        self.assertEqual((1, "FAIL index.html must not be a symlink"), (result.returncode, result.stdout.strip()))

    def test_state_copy_must_equal_embedded_state(self):
        self.fixture()
        (self.root / "data/scenario-state.json").write_text(json.dumps({"s1": {"step": 2}}))
        result = self.verify()
        self.assertEqual((1, "FAIL embedded scenario state differs from data/scenario-state.json"),
                         (result.returncode, result.stdout.strip()))

    def test_embedded_state_must_satisfy_the_state_contract(self):
        # Both state copies agree and the HTML is exactly what the generator renders for that state,
        # so only verify-freeze's own state validation can reject this hand-made bundle.
        self.fixture()
        slot = '<script id="scenario-state" type="application/json">{}</script>'
        html = self.html.read_text()
        self.assertEqual(1, html.count(slot.format('{"s1":{}}')))
        self.html.write_text(html.replace(slot.format('{"s1":{}}'), slot.format('{"s1":{"note":""}}')))
        (self.root / "data/scenario-state.json").write_text('{"s1":{"note":""}}')
        result = self.verify()
        self.assertEqual((1, "FAIL missing/invalid pure JSON data: state s1.note requires a concrete scalar; "
                             "regenerate with prototype_bundle.py"), (result.returncode, result.stdout.strip()))

    def test_bundle_refuses_prototype_state_keys(self):
        for key in ("__proto__", "constructor", "prototype"):
            with self.subTest(key=key):
                result = self.bundle(state={"s1": {key: "x"}})
                self.assertEqual((1, f"FAIL unsafe state key: {key}"), (result.returncode, result.stdout.strip()))
                self.assertFalse(self.html.exists())

    def test_bundle_refuses_output_paths_that_leave_the_bundle(self):
        output, outside = self.root / "bundle", self.root / "outside"
        outside.mkdir()
        output.mkdir()
        (output / "assets").symlink_to(outside, target_is_directory=True)
        result = self.bundle(output=output)
        self.assertEqual((1, "FAIL output path escapes bundle or is a symlink: assets/frames.js"),
                         (result.returncode, result.stdout.strip()))
        # Every destination is checked before the first write.
        self.assertEqual([], sorted(outside.iterdir()))
        self.assertEqual([output / "assets"], sorted(output.iterdir()))

    def test_duplicate_json_key_rejected(self):
        self.map.write_text(self.map.read_text().replace('"schemaVersion": 2', '"schemaVersion": 2, "schemaVersion": 2'))
        result = subprocess.run(["bash", str(SCRIPTS / "validate-map.sh"), str(self.map)], capture_output=True)
        self.assertNotEqual(0, result.returncode)

    @unittest.skipUnless(shutil.which("node"), "runtime projection needs Node.js")
    def test_projection_uses_frozen_order_and_ac_objects(self):
        self.data["routes"] = {"s2": {"name": "Second first", "pages": ["home"]},
                               "s1": {"name": "First second", "pages": ["home"]}}
        self.fixture()
        # A JS VM with only data-node access verifies projection, not browser behavior.
        script = '''const fs=require('fs'), vm=require('vm'), assert=require('assert');
const map=fs.readFileSync(process.argv[1],'utf8');
const state=JSON.stringify({s2:{},s1:{}});
const context={document:{getElementById:id=>({textContent:id==='prototype-map'?map:state})}};
vm.createContext(context); vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),context);
assert.equal(Object.keys(context.SCENARIO_TITLES).join(','),'s2,s1');
assert.equal(context.NAV_PATH.s2.join(','),'home');
assert.equal(context.STEPS.s2[0].label,'Home');
assert.equal(context.AC_DATA.s2.home,context.PROTOTYPE_MAP.pages.home.acs);
'''
        result = subprocess.run(["node", "-e", script, str(self.map), str(TEMPLATES / "runtime-data.js")],
                                capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)

    def test_repair_bounds_and_stale_hash(self):
        self.data["frames"]["frame-home"]["sections"][0]["span"] = "wide"
        self.write_map()
        original = self.map.read_bytes()
        digest = hashlib.sha256(original).hexdigest()
        candidate = self.root / "candidate.json"
        fixed = copy.deepcopy(self.data)
        fixed["frames"]["frame-home"]["sections"][0]["span"] = 12
        candidate.write_text(json.dumps(fixed))
        args = ["python3", str(SCRIPTS / "check-repair.py"), "--base", str(self.map),
                "--candidate", str(candidate), "--base-sha256", digest,
                "--allow", "/frames/frame-home/sections/0/span"]
        self.assertEqual(0, subprocess.run(args, capture_output=True).returncode)
        self.assertEqual(original, self.map.read_bytes())
        fixed["pages"]["home"]["acs"][0]["text"] = "Silently change requirement"
        candidate.write_text(json.dumps(fixed))
        self.assertNotEqual(0, subprocess.run(args, capture_output=True).returncode)
        self.map.write_bytes(original + b"\n")
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("stale base hash", result.stdout)

    @unittest.skipUnless(shutil.which("node"), "runtime text rendering needs Node.js")
    def test_runtime_renders_requirement_text_as_text(self):
        script = '''const fs=require('fs'), vm=require('vm'), assert=require('assert');
const nodes={};
const node=id=>nodes[id]||(nodes[id]={innerHTML:'',textContent:'',style:{},
 classList:{add(){},remove(){}},querySelectorAll:()=>[],contains:()=>true});
const document={getElementById:node,querySelector:()=>null,querySelectorAll:()=>[]};
const map=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));
const attack='<img src=x onerror="alert(1)">';
map.pages.home.acs[0].text=attack; map.pages.home.acs[0].src=attack;
map.pages.home.acs[0].prd='Reference'; map.pages.home.label=attack;
map.meta.projectName=attack; delete map.meta.coverageRate;
node('prototype-map').textContent=JSON.stringify(map);
node('scenario-state').textContent='{"s1":{}}';
const context={document,FRAME_REGISTRY:{'frame-home':()=>'<button>Welcome</button>'},
 localStorage:{getItem:()=>null},window:{}};
vm.createContext(context);
vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),context);
vm.runInContext(fs.readFileSync(process.argv[3],'utf8'),context);
assert.ok(nodes['s1-home'].innerHTML.includes('Welcome'));
assert.ok(nodes['panel-ac-list'].innerHTML.includes('&lt;img'));
assert.ok(!nodes['panel-ac-list'].innerHTML.includes('<img'));
assert.ok(!nodes['panel-stepper'].innerHTML.includes('<img'));
const report=context.buildReportHtml();
assert.ok(!report.includes('<img')); assert.ok(!report.includes('100%'));
'''
        result = subprocess.run(["node", "-e", script, str(self.map), str(TEMPLATES / "runtime-data.js"),
                                 str(TEMPLATES / "engine.js")], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)

    @unittest.skipUnless(shutil.which("node"), "runtime report needs Node.js")
    def test_report_renders_route_names_ac_ids_and_gaps_as_text(self):
        attack = "<img src=x onerror=1>"
        self.data["routes"]["s1"]["name"] = attack
        self.data["pages"]["home"]["acs"][0]["id"] = attack
        self.data["meta"]["gaps"] = [{"prdAcId": attack, "description": attack, "reason": attack,
                                      "acknowledgedBy": "PM"}]
        result = self.run_engine(r'''
const {context}=load('{"s1":{}}',"var FRAME_REGISTRY={'frame-home':function(){return 'Welcome';}};");
const report=context.buildReportHtml(), text='&lt;img src=x onerror=1&gt;';
assert.ok(!report.includes('<img'),report);
assert.ok(report.includes('<h2 class="c-print-report__route-title">'+text+'</h2>'),report);
assert.ok(report.includes('<span class="c-print-report__ac-id">'+text+'</span>'),report);
assert.ok(report.includes('<strong>'+text+'</strong>：'+text+' — '+text+'</div>'),report);
''')
        self.assertEqual(0, result.returncode, result.stderr)

    @unittest.skipUnless(shutil.which("node"), "runtime freeze needs Node.js")
    def test_frames_cannot_rewrite_frozen_runtime_data(self):
        # frames.js runs after runtime-data.js and before engine.js. Its writes to the map or a
        # projection must not reach the AC panel or the report that PM/UI/DEV sign.
        self.data["meta"].pop("coverageRate")
        result = self.run_engine(r'''
const writes=["PROTOTYPE_MAP.pages.home.acs[0].text='TAMPERED AC TEXT'", "PROTOTYPE_MAP.meta.coverageRate=100",
 "NAV_PATH.s1.push('home')", "AC_DATA.s1.home=[{id:'AC-X',text:'TAMPERED AC TEXT'}]",
 "AC_DATA={s1:{home:[{id:'AC-X',text:'TAMPERED AC TEXT'}]}}",
 "PROTOTYPE_MAP={meta:{projectName:'TAMPERED',coverageRate:100},routes:PROTOTYPE_MAP.routes,pages:PROTOTYPE_MAP.pages}"];
const problems=[];
for(const strict of [false,true]){
  const mode=strict?'strict':'sloppy', expect=(ok,what)=>ok||problems.push(mode+': '+what);
  // Each write has its own try/catch, so a refused write cannot skip the next one.
  const {context,nodes}=load('{"s1":{}}',(strict?"'use strict';\n":'')+'var refused=[];\n'+
   writes.map(write=>'try{'+write+';}catch(e){refused.push(e.name);}').join('\n')+
   "\nvar FRAME_REGISTRY={'frame-home':function(){return 'Welcome';}};");
  const seen=vm.runInContext('({text:PROTOTYPE_MAP.pages.home.acs[0].text,project:PROTOTYPE_MAP.meta.projectName,'+
   'coverage:PROTOTYPE_MAP.meta.coverageRate,nav:NAV_PATH.s1.join(),shared:AC_DATA.s1.home===PROTOTYPE_MAP.pages.home.acs,'+
   'refused:refused.join()})',context);
  const list=nodes['panel-ac-list'].innerHTML, report=context.buildReportHtml();
  expect(seen.text==='Show welcome','map AC text '+seen.text);
  expect(seen.project==='Demo'&&seen.coverage===undefined,'map meta '+seen.project+' coverage '+seen.coverage);
  expect(seen.nav==='home','NAV_PATH.s1 '+seen.nav);
  expect(seen.shared,'AC_DATA.s1.home is no longer the map acs');
  expect(list.includes('Show welcome')&&!list.includes('TAMPERED'),'AC panel text changed');
  expect(report.split('Show welcome').length===2&&!report.includes('TAMPERED'),'report AC text changed');
  expect(report.includes('AC 覆蓋率：未計算'),'report '+(report.match(/AC 覆蓋率：[^<]*/)||['coverage missing'])[0]);
  // Sloppy mode ignores plain writes; strict mode and array mutators throw.
  expect(seen.refused===(strict?Array(writes.length).fill('TypeError').join():'TypeError'),'refused ['+seen.refused+']');
  // Every published name, including those the writes above skip, is a read-only global over deep-frozen data.
  const open=vm.runInContext(`(()=>{
   const frozen=v=>v===null||typeof v!=='object'||Object.isFrozen(v)&&Object.values(v).every(frozen);
   return ['PROTOTYPE_MAP','SCENARIO_TITLES','NAV_PATH','STEPS','STEPPER_LABELS','PANEL_MAP','AC_DATA'].filter(name=>{
    const d=Object.getOwnPropertyDescriptor(globalThis,name); return d.writable||d.configurable||!frozen(d.value);}).join(' ');
  })()`,context);
  expect(open==='','not locked and deep-frozen: '+open);
}
assert.deepEqual(problems,[]);
''')
        self.assertEqual(0, result.returncode, result.stderr)

    @unittest.skipUnless(shutil.which("node"), "runtime state needs Node.js")
    def test_runtime_state_stays_writable_next_to_frozen_data(self):
        # Guard against freezing too much: frames keep form input in SCENARIO_STATE between steps
        # (an email typed on one step is shown on the next), reviewers keep AC checks and notes.
        result = self.run_engine(r'''
const {context,nodes}=load('{"s1":{"email":""}}',"'use strict';\nSCENARIO_STATE.s1.email='pilot@example.com';\n"+
 "var FRAME_REGISTRY={'frame-home':function(ctx){return 'email='+ctx.email;}};");
assert.equal(nodes['s1-home'].innerHTML,'email=pilot@example.com');
vm.runInContext("'use strict'; SCENARIO_STATE.s1.email='next@example.com'; goTo('s1','home');",context);
assert.equal(nodes['s1-home'].innerHTML,'email=next@example.com');
const item={checked:false,classList:{toggle(){item.checked=!item.checked;},contains:()=>item.checked}};
context.toggleAcItem('s1','home',0,item); context.saveAcNote('s1__home__0',' Copy needs review ');
const report=context.buildReportHtml();
assert.ok(report.includes('已確認：1 / 1'),report); assert.ok(report.includes('Copy needs review'),report);
''')
        self.assertEqual(0, result.returncode, result.stderr)

    @unittest.skipUnless(shutil.which("node"), "runtime navigation needs Node.js")
    def test_goto_without_target_frame_keeps_current_frame(self):
        self.data = routed_map({"s1": ["home", "review"], "s2": ["queue"]},
                               {("home", "nextStep"): "review", ("review", "backStep"): "home"})
        self.write_map()
        # Fake DOM: a node tree with class state, Node.contains and compound class selectors only.
        script = r'''const fs=require('fs'), vm=require('vm'), assert=require('assert');
const map=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));
const nodes=[], byId={};
const matches=(n,sel)=>/^(\.[\w-]+)+$/.test(sel)&&sel.slice(1).split('.').every(c=>n.classes.has(c));
function make(id,cls,parent){
  const n={id,parentNode:parent||null,classes:new Set(cls?cls.split(' '):[]),innerHTML:'',textContent:'',style:{}};
  n.classList={add:c=>n.classes.add(c),remove:c=>n.classes.delete(c),contains:c=>n.classes.has(c)};
  n.contains=o=>{for(let p=o;p;p=p.parentNode){if(p===n)return true;}return false;};
  n.querySelectorAll=sel=>nodes.filter(d=>d!==n&&n.contains(d)&&matches(d,sel));
  nodes.push(n); if(id)byId[id]=n; return n;
}
const document={getElementById:id=>byId[id]||null,
 querySelector:sel=>nodes.find(n=>matches(n,sel))||null,
 querySelectorAll:sel=>nodes.filter(n=>matches(n,sel))};
make('prototype-map').textContent=JSON.stringify(map);
make('scenario-state').textContent='{"s1":{},"s2":{}}';
const side=make('','l-step-panel');
['panel-scenario-title','panel-progress-badge','panel-stepper','panel-ac-list','btn-prev','btn-next']
 .forEach(id=>make(id,'',side));
make('s1-stray','',side);  // carries a frame-style ID but sits outside scenario-s1
Object.keys(map.routes).forEach((sid,i)=>{
  const panel=make('scenario-'+sid,'l-scenario-panel'+(i?'':' is-active'));
  const content=make('','c-standard-shell__content',panel);
  map.routes[sid].pages.forEach(pid=>make(sid+'-'+pid,'c-flow-frame',content));
});
const render=ctx=>ctx.sid+'/'+ctx.stepId+' back='+ctx.backStep+' next='+ctx.nextStep;
const context={document,FRAME_REGISTRY:{'frame-home':render},localStorage:{getItem:()=>null},window:{}};
vm.createContext(context);
vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),context);
vm.runInContext(fs.readFileSync(process.argv[3],'utf8'),context);
const VmError=vm.runInContext('Error',context);
const overlay=make('','c-confirm-dialog-overlay is-open',byId['s1-home']);  // dialog opened after load
const active=sid=>byId['scenario-'+sid].querySelectorAll('.c-flow-frame.is-active').map(n=>n.id);
assert.deepEqual(active('s1'),['s1-home']); assert.equal(context.currentStepId,'home');
// Cross-route page, unknown page, ID outside the panel, unknown scenario, ID that is a shell element.
for(const [sid,step] of [['s1','queue'],['s1','missing'],['s1','stray'],['s9','home'],['panel','stepper']]){
  assert.throws(()=>context.goTo(sid,step),e=>e instanceof VmError&&e.message.includes('no frame '+sid+'-'+step));
  assert.deepEqual(active('s1'),['s1-home']); assert.ok(!byId['s1-stray'].classes.has('is-active'));
  assert.equal(context.currentScenario,'s1'); assert.equal(context.currentStepId,'home');
  assert.ok(overlay.classes.has('is-open')); assert.equal(byId['panel-progress-badge'].textContent,'1 / 2');
}
context.goTo('s1','review');
assert.deepEqual(active('s1'),['s1-review']); assert.ok(!overlay.classes.has('is-open'));
assert.equal(byId['s1-review'].innerHTML,'s1/review back=home next=undefined');
assert.equal(context.currentStepId,'review'); assert.equal(byId['panel-progress-badge'].textContent,'2 / 2');
context.goTo('s2','queue');
assert.deepEqual(active('s2'),['s2-queue']); assert.equal(context.currentScenario,'s2');
assert.ok(byId['scenario-s2'].classes.has('is-active')); assert.ok(!byId['scenario-s1'].classes.has('is-active'));
'''
        result = subprocess.run(["node", "-e", script, str(self.map), str(TEMPLATES / "runtime-data.js"),
                                 str(TEMPLATES / "engine.js")], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)

    def test_repair_rejects_reordering_and_structural_rewrites(self):
        self.data["routes"] = {"s2": {"name": "Second", "pages": ["home"]},
                               "s1": {"name": "First", "pages": ["home"]}}
        self.data["meta"]["coverageRate"] = 999
        self.write_map()
        digest = hashlib.sha256(self.map.read_bytes()).hexdigest()
        candidate = self.root / "candidate.json"
        repaired = copy.deepcopy(self.data)
        repaired["meta"]["coverageRate"] = 100
        repaired["routes"] = dict(reversed(list(repaired["routes"].items())))
        candidate.write_text(json.dumps(repaired))
        result = subprocess.run(["python3", str(SCRIPTS / "check-repair.py"), "--base", str(self.map),
                                 "--candidate", str(candidate), "--base-sha256", digest,
                                 "--allow", "/meta/coverageRate"], capture_output=True, text=True)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("route order", result.stdout)
        self.data = valid_map()
        self.data["frames"]["frame-home"]["sections"] = []
        self.write_map()
        candidate.write_text(json.dumps(valid_map()))
        result = subprocess.run(["python3", str(SCRIPTS / "check-repair.py"), "--base", str(self.map),
                                 "--candidate", str(candidate), "--base-sha256",
                                 hashlib.sha256(self.map.read_bytes()).hexdigest(),
                                 "--allow", "/frames/frame-home/sections"], capture_output=True, text=True)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("structural/content", result.stdout)

    def test_repair_refuses_unreported_paths_added_or_removed_fields_and_invalid_candidates(self):
        # tuning.md: only selected fields the validator reports may change, only as existing scalars,
        # and the candidate must validate. `reported` pins each base's validator errors.
        span, text, page_label, subtitle = ("/frames/frame-home/sections/0/span", "/pages/home/acs/0/text",
                                            "/pages/home/label", "/meta/subtitle")

        def edited(change):
            data = valid_map()
            change(data)
            return data

        def with_span(value):
            return edited(lambda m: m["frames"]["frame-home"]["sections"][0].update(span=value))

        new_text = edited(lambda m: m["pages"]["home"]["acs"][0].update(text="Skip identity verification"))
        numeric_subtitle = edited(lambda m: m["meta"].update(subtitle=5))
        cases = {
            "allow names a path the validator accepts": (
                valid_map(), [], new_text, [text], "allow paths must name current validator errors"),
            "allow adds an unreported path to a reported one": (
                with_span("wide"), [span], new_text, [span, text], "allow paths must name current validator errors"),
            "candidate adds a field": (
                edited(lambda m: m["pages"]["home"].pop("label")), [page_label], valid_map(), [page_label],
                f"repair requires structural/content authoring, not scalar correction: {page_label}"),
            "candidate removes a field": (
                numeric_subtitle, [subtitle], edited(lambda m: m["meta"].pop("subtitle")), [subtitle],
                f"repair requires structural/content authoring, not scalar correction: {subtitle}"),
            "candidate still fails validation": (
                with_span("wide"), [span], with_span(13), [span],
                f"candidate still fails validation: [{{'path': '{span}', 'message': 'must be an integer in 1..12'}}]"),
        }
        for case, (base, reported, candidate, allow, message) in cases.items():
            with self.subTest(label=case):
                self.data = base
                code, report = self.validate_json()  # also leaves these base bytes in self.map
                self.assertEqual(reported, [error["path"] for error in report["errors"]])
                result = self.check_repair(self.map, candidate, *allow)
                self.assertEqual((1, "FAIL " + message), (result.returncode, result.stdout.strip()), result.stderr)
        with self.subTest(label="same field corrected in place"):
            self.data = numeric_subtitle
            self.write_map()
            result = self.check_repair(self.map, valid_map(), subtitle)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_repair_refuses_decision_fields(self):
        # G4: acknowledgedBy records a gap the user accepted and frozenAt the freeze cut. An error
        # there is a missing decision, so even an otherwise bounded scalar repair must not fill it.
        ack, frozen, span = "/meta/gaps/0/acknowledgedBy", "/meta/frozenAt", "/frames/frame-home/sections/0/span"

        def snapshot(acknowledged_by="PM (accepted)", frozen_at="2026-09-16T00:00:00Z", width=12):
            data = valid_map()
            data["meta"].update(frozenAt=frozen_at, gaps=[{"prdAcId": "PRD-7", "description": "Export to CSV",
                                                           "reason": "Out of scope", "acknowledgedBy": acknowledged_by}])
            data["frames"]["frame-home"]["sections"][0]["span"] = width
            return data

        self.data = snapshot()
        code, report = self.validate_json()
        self.assertEqual((0, []), (code, report["errors"]))  # the candidate in every case below
        for label, (base, path) in {"fill acknowledgedBy": (snapshot(acknowledged_by=None), ack),
                                    "fill frozenAt": (snapshot(frozen_at=None), frozen)}.items():
            with self.subTest(label=label):
                self.data = base
                code, report = self.validate_json()  # also leaves these base bytes in self.map
                self.assertEqual([path], [error["path"] for error in report["errors"]])
                result = self.check_repair(self.map, snapshot(), path)
                self.assertEqual(1, result.returncode, result.stdout + result.stderr)
                self.assertIn(f"FAIL {path} is a decision field", result.stdout)
        with self.subTest(label="decision changed outside --allow"):
            self.data = snapshot(acknowledged_by=None, width="wide")
            self.write_map()
            result = self.check_repair(self.map, snapshot(), span)
            self.assertEqual(1, result.returncode, result.stdout + result.stderr)
            self.assertIn(f"FAIL {ack} is a decision field", result.stdout)
        with self.subTest(label="decision named in --allow, change elsewhere"):
            self.data = snapshot(frozen_at=None, width="wide")
            self.write_map()
            result = self.check_repair(self.map, snapshot(frozen_at=None), span, frozen)
            self.assertEqual(1, result.returncode, result.stdout + result.stderr)
            self.assertIn(f"FAIL {frozen} is a decision field", result.stdout)

    def test_repair_base_rev_requires_the_committed_base(self):
        # The hash proves which base was compared; --base-rev also ties those bytes to a commit.
        repo = self.root / "repo"
        (repo / "data").mkdir(parents=True)
        span, text = "/frames/frame-home/sections/0/span", "/pages/home/acs/0/text"
        broken = valid_map()
        broken["frames"]["frame-home"]["sections"][0]["span"] = "wide"
        (repo / "data/broken.json").write_text(json.dumps(broken))
        (repo / "data/lines.json").write_text(json.dumps(broken, indent=2) + "\n")  # multi-line, LF
        (repo / "data/map.json").write_text(json.dumps(valid_map()))
        for args in (["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "freeze"]):
            git(repo, *args)
        base = repo / "data/broken.json"
        with self.subTest(label="committed base"):
            result = self.check_repair(base, valid_map(), span, base_rev="HEAD:data/broken.json", cwd=repo)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn("PASS bounded scalar repair against committed HEAD:data/broken.json", result.stdout)
        refused = {
            "unknown revision": ("no-such-rev:data/broken.json", "--base-rev revision 'no-such-rev' is not a commit"),
            "path missing from commit": ("HEAD:data/gone.json", "--base-rev path 'data/gone.json' is not a file in HEAD"),
            "path is a tree": ("HEAD:data", "--base-rev path 'data' is not a file in HEAD"),
            "index entry, no commit": (":data/broken.json", "--base-rev must be REV:PATH"),
            "option-like revision": ("--output=x:data/broken.json", "--base-rev must be REV:PATH"),
        }
        for label, (rev, message) in refused.items():
            with self.subTest(label=label):
                result = self.check_repair(base, valid_map(), span, base_rev=rev, cwd=repo)
                self.assertEqual(1, result.returncode, result.stdout + result.stderr)
                self.assertIn(f"FAIL {message}", result.stdout)
        with self.subTest(label="base edited after commit"):
            # Laundering: blank a committed AC, re-hash, then "repair" it into new requirement text.
            blanked, rewritten = valid_map(), valid_map()
            blanked["pages"]["home"]["acs"][0]["text"] = ""
            rewritten["pages"]["home"]["acs"][0]["text"] = "Skip identity verification"
            edited = repo / "data/map.json"
            edited.write_text(json.dumps(blanked))
            # Without --base-rev the hash only names the edited base, so this documented limit passes.
            self.assertEqual(0, self.check_repair(edited, rewritten, text, cwd=repo).returncode)
            result = self.check_repair(edited, rewritten, text, base_rev="HEAD:data/map.json", cwd=repo)
            self.assertEqual(1, result.returncode, result.stdout + result.stderr)
            self.assertIn("FAIL base bytes differ from the committed blob HEAD:data/map.json; use that version "
                          "as --base: git cat-file blob HEAD:data/map.json > base.json", result.stdout)
            # Staging the edit and naming its tree still records no commit.
            git(repo, "add", "data/map.json")
            tree = git(repo, "write-tree").stdout.decode().strip()
            result = self.check_repair(edited, rewritten, text, base_rev=tree + ":data/map.json", cwd=repo)
            self.assertEqual(1, result.returncode, result.stdout + result.stderr)
            self.assertIn(f"FAIL --base-rev revision '{tree}' is not a commit", result.stdout)
        with self.subTest(label="checkout with line-ending conversion"):
            # core.autocrlf rewrites LF to CRLF on checkout, so a multi-line working file no longer
            # equals the blob. The recovery the message names writes the blob itself as the base.
            git(repo, "config", "core.autocrlf", "true")
            lines = repo / "data/lines.json"
            lines.unlink()
            git(repo, "checkout", "--", "data/lines.json")
            self.assertIn(b"\r\n", lines.read_bytes())
            result = self.check_repair(lines, valid_map(), span, base_rev="HEAD:data/lines.json", cwd=repo)
            self.assertEqual(1, result.returncode, result.stdout + result.stderr)
            self.assertIn("git cat-file blob HEAD:data/lines.json > base.json", result.stdout)
            blob = self.root / "base.json"
            blob.write_bytes(git(repo, "cat-file", "blob", "HEAD:data/lines.json").stdout)
            result = self.check_repair(blob, valid_map(), span, base_rev="HEAD:data/lines.json", cwd=repo)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_legacy_map_and_supported_hint(self):
        self.data["meta"].pop("schemaVersion")
        self.data["pages"]["home"]["legacyExtension"] = "kept"
        self.assertEqual(0, self.validate().returncode)
        self.data = valid_map()
        self.data["pages"]["home"]["acs"][0]["isHint"] = True
        self.assertEqual(0, self.validate().returncode)


if __name__ == "__main__":
    unittest.main()
