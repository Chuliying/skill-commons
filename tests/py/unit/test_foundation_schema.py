"""S1 — closed schema + canonical JSON + envelope digest + typed errors.

Verifies the Foundation's deterministic serialization and closed-schema
fail-closed behavior (spec D-003/D-017, FR-002/FR-004). No git, no I/O.
"""

import unittest

from foundation import errors, schema


VALID_REF = {
    "repo_id": "repoA",
    "commit_oid": "a" * 40,
    "path": "docs/prd.md",
    "digest": "b" * 64,
    "artifact_kind": "prd",
}


class TestTypedErrors(unittest.TestCase):
    def test_error_codes_exist(self):
        for code in ("SCHEMA_ERROR", "STALE_HOME_REVISION", "PUBLICATION_CONFLICT"):
            self.assertTrue(hasattr(errors, code), f"missing error code {code}")

    def test_unresolvable_reasons_closed_set(self):
        expected = {
            "ref-unpublished",
            "object-missing",
            "digest-unverifiable",
            "repo-unregistered",
            "path-escape",
        }
        self.assertEqual(set(errors.UNRESOLVABLE_REASONS), expected)

    def test_foundation_error_carries_code(self):
        err = errors.FoundationError(errors.SCHEMA_ERROR, "bad")
        self.assertEqual(err.code, errors.SCHEMA_ERROR)
        self.assertIn("bad", str(err))


class TestArtifactRefSchema(unittest.TestCase):
    def test_valid_ref_normalized(self):
        out = schema.validate_artifact_ref(dict(VALID_REF))
        self.assertEqual(out, VALID_REF)

    def test_missing_field_fails_closed(self):
        for field in schema.ARTIFACT_REF_FIELDS:
            bad = dict(VALID_REF)
            del bad[field]
            with self.subTest(missing=field):
                with self.assertRaises(errors.FoundationError) as ctx:
                    schema.validate_artifact_ref(bad)
                self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_unknown_field_rejected_closed(self):
        bad = dict(VALID_REF, extra="x")
        with self.assertRaises(errors.FoundationError) as ctx:
            schema.validate_artifact_ref(bad)
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_repo_id_is_part_of_identity(self):
        # Same commit OID in two repos must be distinct refs (B1 fork/clone).
        ref_a = dict(VALID_REF, repo_id="repoA")
        ref_b = dict(VALID_REF, repo_id="repoB")
        self.assertNotEqual(
            schema.canonical_json(schema.validate_artifact_ref(ref_a)),
            schema.canonical_json(schema.validate_artifact_ref(ref_b)),
        )

    def test_empty_field_value_fails_closed(self):
        bad = dict(VALID_REF, repo_id="")
        with self.assertRaises(errors.FoundationError):
            schema.validate_artifact_ref(bad)

    def test_non_canonical_path_rejected(self):
        # One physical artifact must not get two Ref identities via non-canonical path
        # spellings (Fable nit #2); path must be canonical + repo-relative like collection_identity.
        for bad in ("./a.md", "a//b.md", "a/./b.md", "a/../b.md", "dir/", "/abs.md", "a\\b.md", "../x.md", "~/x.md"):
            with self.subTest(path=bad):
                with self.assertRaises(errors.FoundationError) as ctx:
                    schema.validate_artifact_ref(dict(VALID_REF, path=bad))
                self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_identity_formats_pinned(self):
        # M1: non-hex / abbreviated / upper-case OID and non-sha256 digest are rejected,
        # so one object cannot yield multiple Ref identities.
        for bad in (
            dict(VALID_REF, commit_oid="x" * 40),          # non-hex
            dict(VALID_REF, commit_oid="a" * 39),          # too short
            dict(VALID_REF, commit_oid="A" * 40),          # upper-case
            dict(VALID_REF, commit_oid="a" * 40 + "\n"),   # trailing-newline alias (fullmatch, not match)
            dict(VALID_REF, digest="b" * 63),              # not 64
            dict(VALID_REF, digest="Z" * 64),              # non-hex
            dict(VALID_REF, digest="b" * 64 + "\n"),       # trailing-newline alias
        ):
            with self.subTest(ref=bad):
                with self.assertRaises(errors.FoundationError) as ctx:
                    schema.validate_artifact_ref(bad)
                self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)


class TestCanonicalJson(unittest.TestCase):
    def test_deterministic_key_order(self):
        a = {"b": 1, "a": 2, "c": 3}
        b = {"c": 3, "a": 2, "b": 1}
        self.assertEqual(schema.canonical_json(a), schema.canonical_json(b))

    def test_no_trailing_newline_and_tight_separators(self):
        s = schema.canonical_json({"a": 1, "b": 2})
        self.assertFalse(s.endswith("\n"))
        self.assertNotIn(", ", s)
        self.assertNotIn(": ", s)

    def test_non_ascii_preserved(self):
        # ensure_ascii=False: a non-ASCII path stays as its bytes, not \uXXXX.
        s = schema.canonical_json({"path": "docs/需求.md"})
        self.assertIn("需求", s)


class TestEnvelopeDigest(unittest.TestCase):
    def test_collection_identity_is_repo_id_plus_repo_relative_path(self):
        self.assertEqual(
            schema.validate_collection_identity("home-repo/.git"),
            "home-repo/.git",
        )
        for invalid in ("c", "cid", "/absolute/home", "repo/../home", "repo//home", "repo/~"):
            with self.subTest(identity=invalid):
                with self.assertRaises(errors.FoundationError) as ctx:
                    schema.validate_collection_identity(invalid)
                self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def _rel(self, kind, repo):
        return {"kind": kind, "object": dict(VALID_REF, repo_id=repo)}

    def test_deterministic(self):
        d1 = schema.envelope_digest("home/one", dict(VALID_REF), [])
        d2 = schema.envelope_digest("home/one", dict(VALID_REF), [])
        self.assertEqual(d1, d2)
        self.assertEqual(len(d1), 64)  # sha256 hex

    def test_relation_order_independent(self):
        r1 = self._rel("derived-from", "x")
        r2 = self._rel("evidences", "y")
        self.assertEqual(
            schema.envelope_digest("home/root", dict(VALID_REF), [r1, r2]),
            schema.envelope_digest("home/root", dict(VALID_REF), [r2, r1]),
        )

    def test_relation_dedup(self):
        r = self._rel("derived-from", "x")
        self.assertEqual(
            schema.envelope_digest("home/root", dict(VALID_REF), [r]),
            schema.envelope_digest("home/root", dict(VALID_REF), [r, dict(r)]),
        )

    def test_collection_identity_scopes_digest(self):
        self.assertNotEqual(
            schema.envelope_digest("home/a", dict(VALID_REF), []),
            schema.envelope_digest("home/b", dict(VALID_REF), []),
        )

    def test_unknown_relation_kind_fails_closed(self):
        bad = {"kind": "requires", "object": dict(VALID_REF)}
        with self.assertRaises(errors.FoundationError) as ctx:
            schema.envelope_digest("home/root", dict(VALID_REF), [bad])
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_relations_non_list_fails_closed(self):
        # #7: a non-list relations value must not be silently coerced to an empty set.
        for bad in (False, 0, "", {}, "x"):
            with self.subTest(relations=bad):
                with self.assertRaises(errors.FoundationError) as ctx:
                    schema.publication_envelope("home/root", dict(VALID_REF), bad)
                self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)


if __name__ == "__main__":
    unittest.main()
