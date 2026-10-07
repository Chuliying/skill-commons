"""Executable regressions for the OUI review's false accepts, not UI-quality scores."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / "prototype/scripts"
TEMPLATES = ROOT / "prototype/templates"


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

    def verify(self):
        return subprocess.run(["python3", str(SCRIPTS / "verify-freeze.py"),
                               "--map", str(self.map), "--html", str(self.html)],
                              capture_output=True, text=True)

    def fixture(self):
        self.write_map()
        (self.root / "state.json").write_text(json.dumps({sid: {} for sid in self.data["routes"]}))
        (self.root / "frames.js").write_text(
            'var FRAME_REGISTRY = {"frame-home": function(ctx) {'
            'return "<button class=\\"c-welcome\\">Welcome</button>";}};')
        (self.root / "library.css").write_text(".c-welcome {padding: 1rem;}")
        result = subprocess.run(["python3", str(SCRIPTS / "prototype_bundle.py"),
                                 "--map", str(self.map), "--state", str(self.root / "state.json"),
                                 "--frames", str(self.root / "frames.js"),
                                 "--library", str(self.root / "library.css"),
                                 "--output", str(self.root)], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        result = self.verify()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

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
            "prototype key": lambda m: m["pages"].update(__proto__=m["pages"]["home"]),
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
 classList:{add(){},remove(){}},querySelectorAll:()=>[]});
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

    def test_legacy_map_and_supported_hint(self):
        self.data["meta"].pop("schemaVersion")
        self.data["pages"]["home"]["legacyExtension"] = "kept"
        self.assertEqual(0, self.validate().returncode)
        self.data = valid_map()
        self.data["pages"]["home"]["acs"][0]["isHint"] = True
        self.assertEqual(0, self.validate().returncode)


if __name__ == "__main__":
    unittest.main()
