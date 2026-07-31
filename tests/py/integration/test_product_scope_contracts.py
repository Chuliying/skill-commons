"""Product Scope contract layer (S-PSG-01 TC-002/003/006/009/010).

The contracts are canonical and closed: an unknown field or a reordered list must
not produce a second identity for the same decision, because identity is what the
activation CAS keys on.
"""

import unittest

from productscope import contracts, errors


def _ref(path="prd.md", kind="prd"):
    return {
        "repo_id": "repoA",
        "commit_oid": "a" * 40,
        "path": path,
        "digest": "b" * 64,
        "artifact_kind": kind,
    }


class EnvelopeShape(unittest.TestCase):
    def _envelope(self, kind="team-prd"):
        return {
            "product_id": "prod",
            "proposal_id": "p1",
            "base_scope_revision": "c" * 40,
            "source_artifact_ref": _ref(),
            "requirement_changes": [{"requirement_id": "R2", "operation": "ADD"},
                                    {"requirement_id": "R1", "operation": "ADD"}],
            "declared_relations": [],
            "proposal_kind": kind,
        }

    def test_tc002_both_authoring_kinds_share_one_shape(self):
        team = contracts.validate_envelope(self._envelope("team-prd"))
        personal = contracts.validate_envelope(self._envelope("personal-change"))
        self.assertEqual(set(team), set(personal))
        self.assertNotEqual(team["proposal_kind"], personal["proposal_kind"])

    def test_tc010_digest_is_order_independent_and_stable(self):
        a = self._envelope()
        b = self._envelope()
        b["requirement_changes"] = list(reversed(b["requirement_changes"]))
        self.assertEqual(contracts.envelope_digest(a), contracts.envelope_digest(b))
        self.assertEqual(contracts.envelope_digest(a), contracts.envelope_digest(a))

    def test_unknown_field_is_rejected(self):
        bad = self._envelope()
        bad["extra"] = "x"
        with self.assertRaises(errors.ProductScopeError):
            contracts.validate_envelope(bad)

    def test_unknown_proposal_kind_is_rejected(self):
        with self.assertRaises(errors.ProductScopeError):
            contracts.validate_envelope(self._envelope("smuggled-kind"))


class AnalysisSeparation(unittest.TestCase):
    def test_tc003_advisory_candidate_never_enters_accepted_relations(self):
        analysis = contracts.build_analysis(
            envelope_digest="d" * 64,
            base_scope_revision="c" * 40,
            deterministic_matches=[{"requirement_id": "R1", "basis": "stable-id"}],
            advisory_candidates=[{"requirement_id": "R9", "confidence": 0.9}],
            canonical_diff={"added": ["R1"], "modified": [], "superseded": [],
                            "removed": [], "unchanged": []},
            conflicts=[],
            impact_candidates=[],
        )
        # The two classes stay in separate keys and advisory is not promoted.
        self.assertIn("advisory_candidates", analysis)
        self.assertIn("deterministic_matches", analysis)
        delta = contracts.validate_delta({
            "product_id": "prod",
            "proposal_ref": "d" * 64,
            "parent_scope_revision": "c" * 40,
            "accepted_changes": [{"requirement_id": "R1", "operation": "ADD"}],
            "accepted_relations": [],
            "requirement_impact": [],
            "decision_context": {"mode": "team-gate-1", "source_package_path": "pkg.md",
                                 "source_package_digest": "e" * 64,
                                 "decided_at": "2026-07-25T00:00:00+08:00"},
            "delta_digest": "f" * 64,
        })
        for candidate in analysis["advisory_candidates"]:
            self.assertNotIn(candidate, delta["accepted_relations"])

    def test_tc003_an_unaccepted_advisory_candidate_is_refused(self):
        """The real enforcement. The assertion above is satisfied by any delta whose
        accepted_relations happen to be empty, so on its own it proves nothing about
        the system -- only about the fixture. This drives the rejection path."""
        candidate = {"kind": "relates-to", "target": "R9", "confidence": 0.9}
        analysis = contracts.build_analysis(
            envelope_digest="d" * 64, base_scope_revision="c" * 40,
            deterministic_matches=[], advisory_candidates=[candidate],
            canonical_diff={"added": [], "modified": [], "superseded": [],
                            "removed": [], "unchanged": []},
            conflicts=[], impact_candidates=[],
        )
        smuggled = {
            "product_id": "prod", "proposal_ref": "d" * 64,
            "parent_scope_revision": "c" * 40,
            "accepted_changes": [{"requirement_id": "R1", "operation": "ADD"}],
            "accepted_relations": [candidate],          # never accepted at a gate
            "requirement_impact": [],
            "decision_context": {"mode": "team-gate-1", "source_package_path": "pkg.md",
                                 "source_package_digest": "e" * 64,
                                 "decided_at": "2026-07-25T00:00:00+08:00"},
            "delta_digest": "f" * 64,
        }
        with self.assertRaises(errors.ProductScopeError) as caught:
            contracts.validate_delta_against_analysis(smuggled, analysis)
        self.assertEqual(caught.exception.code, errors.ADVISORY_NOT_ACCEPTED)

        # The same candidate passes once the owner explicitly accepted it.
        accepted = contracts.validate_delta_against_analysis(
            smuggled, analysis, explicitly_accepted=[candidate])
        self.assertEqual(accepted["accepted_relations"], [candidate])

    def test_unavailable_semantic_service_does_not_block_a_delta(self):
        analysis = contracts.build_analysis(
            envelope_digest="d" * 64, base_scope_revision="c" * 40,
            deterministic_matches=[], advisory_candidates=None,
            canonical_diff={"added": [], "modified": [], "superseded": [],
                            "removed": [], "unchanged": []},
            conflicts=[], impact_candidates=[],
        )
        delta = {
            "product_id": "prod", "proposal_ref": "d" * 64,
            "parent_scope_revision": "c" * 40,
            "accepted_changes": [{"requirement_id": "R1", "operation": "ADD"}],
            "accepted_relations": [], "requirement_impact": [],
            "decision_context": {"mode": "personal-apply", "source_package_path": "p.md",
                                 "source_package_digest": "e" * 64,
                                 "decided_at": "2026-07-25T00:00:00+08:00"},
            "delta_digest": "f" * 64,
        }
        self.assertEqual(
            contracts.validate_delta_against_analysis(delta, analysis)["product_id"],
            "prod")

    def test_missing_semantic_service_still_yields_deterministic_analysis(self):
        analysis = contracts.build_analysis(
            envelope_digest="d" * 64,
            base_scope_revision="c" * 40,
            deterministic_matches=[{"requirement_id": "R1", "basis": "stable-id"}],
            advisory_candidates=None,
            canonical_diff={"added": ["R1"], "modified": [], "superseded": [],
                            "removed": [], "unchanged": []},
            conflicts=[],
            impact_candidates=[],
        )
        self.assertEqual(analysis["advisory_candidates"], {"status": "unavailable"})
        self.assertEqual(analysis["deterministic_matches"][0]["requirement_id"], "R1")


class DeltaAndProjection(unittest.TestCase):
    def _delta(self, mode="team-gate-1"):
        return {
            "product_id": "prod",
            "proposal_ref": "d" * 64,
            "parent_scope_revision": "c" * 40,
            "accepted_changes": [{"requirement_id": "R1", "operation": "ADD"}],
            "accepted_relations": [],
            "requirement_impact": [],
            "decision_context": {"mode": mode, "source_package_path": "pkg.md",
                                 "source_package_digest": "e" * 64,
                                 "decided_at": "2026-07-25T00:00:00+08:00"},
            "delta_digest": "f" * 64,
        }

    def test_tc006_decision_mode_is_closed(self):
        contracts.validate_delta(self._delta("team-gate-1"))
        contracts.validate_delta(self._delta("personal-apply"))
        with self.assertRaises(errors.ProductScopeError):
            contracts.validate_delta(self._delta("team-gate-2"))

    def test_tc009_projection_requires_an_owner_boundary(self):
        with self.assertRaises(errors.ProductScopeError):
            contracts.validate_initiative_scope({
                "initiative_scope_id": "is1",
                "source_kind": "accepted-scope-delta",
                "product_id": "prod",
                "scope_revision": "c" * 40,
                "requirements": [],
                "requirement_topology": [],
                "scope_digest": "f" * 64,
            })

    def test_initiative_source_kind_is_closed(self):
        base = {
            "initiative_scope_id": "is1",
            "source_kind": "manual-initiative-scope",
            "product_id": "prod",
            "scope_revision": "c" * 40,
            "requirements": [{"requirement_id": "R1", "version": "1",
                              "content_artifact_ref": _ref(), "digest": "b" * 64}],
            "requirement_topology": [],
            "scope_digest": "f" * 64,
        }
        contracts.validate_initiative_scope(base)
        bad = dict(base, source_kind="whatever")
        with self.assertRaises(errors.ProductScopeError):
            contracts.validate_initiative_scope(bad)


if __name__ == "__main__":
    unittest.main()
