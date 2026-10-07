"""AC-006 / AC-005 (declaration level): frozen S0 subset of verify.sh --list S1,
each once, run-all absent from the canonical roster. (spec I06)"""
import pathlib
import subprocess
import unittest

REPO = pathlib.Path(__file__).resolve().parents[3]
VERIFY = REPO / "tests" / "verify.sh"

# Frozen literal S0 floor: the distinct suites the old three callers ran (8 top-level
# + 7 bootstrap), de-duped; bootstrap/test_e2e.sh was later merged into test_check.sh.
# S7 removes the old rosters from CLAUDE.md/AGENTS.md/ci.yml, so this literal is the only executable S0 source (spec D-004 / F5).
S0 = {
    "suite tests/test_artifact_contract.sh",
    "suite tests/test_gate_automation.sh",
    "suite tests/test_journey_evals.sh",
    "suite tests/test_plan_sync.sh",
    "suite tests/test_profiles.sh",
    "suite tests/test_release_convergence.sh",
    "suite tests/test_skills_reorg.sh",
    "suite tests/test_work_items.sh",
    "suite tests/bootstrap/test_check.sh",
    "suite tests/bootstrap/test_manifest.sh",
    "suite tests/bootstrap/test_onboard.sh",
    "suite tests/bootstrap/test_platform.sh",
    "suite tests/bootstrap/test_render.sh",
    "suite tests/bootstrap/test_stamp.sh",
}


def _list_lines():
    r = subprocess.run(
        ["bash", str(VERIFY), "--list"], cwd=str(REPO), capture_output=True, text=True
    )
    assert r.returncode == 0, r.stderr
    return [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]


class TestCoverageRoster(unittest.TestCase):
    def test_s0_subset_of_s1_and_no_duplicate_entries(self):
        lines = _list_lines()
        s1 = set(lines)
        self.assertEqual(len(lines), len(s1), "duplicate roster entries (exactly-once)")
        self.assertEqual(S0 - s1, set(), f"S0 not subset of S1; missing: {S0 - s1}")

    def test_run_all_absent_from_canonical_roster(self):
        self.assertFalse(
            any("run-all" in e for e in _list_lines()),
            "run-all.sh must not be a canonical roster entry (flatten kills the dup class)",
        )

    def test_python_layers_present(self):
        s1 = set(_list_lines())
        for layer in ("layer unit", "layer integration", "layer e2e"):
            self.assertIn(layer, s1)


if __name__ == "__main__":
    unittest.main()
