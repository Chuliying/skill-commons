"""S9 — Foundation vertical-slice journey (spec I03 V01, has_e2e).

One multi-repo journey exercising the whole contract end to end: register two
repos, publish a provenance chain (prd -> spec derived-from prd -> qa evidences
spec across repos), resolve verified bytes, query provenance both directions,
and read a change-fact. Real git = independent oracle.
"""

import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import core, home


def _make_git(prefix):
    d = tempfile.mkdtemp(prefix=prefix)
    for a in (["init", "-q"], ["config", "user.email", "t@e"], ["config", "user.name", "t"]):
        subprocess.run(["git", "-C", d, *a], check=True, capture_output=True)
    return d


def _commit(work, rel, content):
    with open(os.path.join(work, rel), "w", encoding="utf-8") as fh:
        fh.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True, capture_output=True)
    subprocess.run(["git", "-C", work, "commit", "-q", "-m", "x"], check=True, capture_output=True)
    oid = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
    return oid, hashlib.sha256(content.encode()).hexdigest()


class JourneyTest(unittest.TestCase):
    def setUp(self):
        self.hw = _make_git("fdn-journey-home-")
        self.home = os.path.join(self.hw, ".git")
        self.aw = _make_git("fdn-journey-A-")
        self.bw = _make_git("fdn-journey-B-")
        for d in (self.hw, self.aw, self.bw):
            self.addCleanup(shutil.rmtree, d, ignore_errors=True)

    def _ref(self, repo, oid, dg, path, kind):
        return {"repo_id": repo, "commit_oid": oid, "path": path, "digest": dg, "artifact_kind": kind}

    def test_publish_resolve_query_change_fact_journey(self):
        # register two repos
        core.register(self.home, "repoA", os.path.join(self.aw, ".git"), home.read_head(self.home))
        core.register(self.home, "repoB", os.path.join(self.bw, ".git"), home.read_head(self.home))

        # prd (repoA)
        o_prd, d_prd = _commit(self.aw, "prd.md", "PRD body\n")
        prd = self._ref("repoA", o_prd, d_prd, "prd.md", "prd")
        core.publish(self.home, "home/collection", prd, [], home.read_head(self.home))

        # spec (repoA) derived-from prd
        o_spec, d_spec = _commit(self.aw, "spec.md", "SPEC body\n")
        spec = self._ref("repoA", o_spec, d_spec, "spec.md", "spec")
        core.publish(
            self.home,
            "home/collection",
            spec,
            [{"kind": "derived-from", "object": prd}],
            home.read_head(self.home),
        )

        # qa (repoB) evidences spec
        o_qa, d_qa = _commit(self.bw, "qa.md", "QA body\n")
        qa = self._ref("repoB", o_qa, d_qa, "qa.md", "qa")
        core.publish(
            self.home,
            "home/collection",
            qa,
            [{"kind": "evidences", "object": spec}],
            home.read_head(self.home),
        )

        # resolve verified bytes for each, across repos
        self.assertEqual(core.resolve(self.home, prd)["bytes"], b"PRD body\n")
        self.assertEqual(core.resolve(self.home, spec)["bytes"], b"SPEC body\n")
        self.assertEqual(core.resolve(self.home, qa)["bytes"], b"QA body\n")

        # query spec provenance: out = derived-from prd; in = evidences from qa (repoB)
        edges = core.query(self.home, spec)["direct_edges"]
        out = {(e["kind"], e["object"]["repo_id"]) for e in edges["out"]}
        inn = {(e["kind"], e["subject"]["repo_id"]) for e in edges["in"]}
        self.assertIn(("derived-from", "repoA"), out)
        self.assertIn(("evidences", "repoB"), inn)

        # transitive derived-from from spec reaches prd
        trans = core.query(self.home, spec, kind="derived-from")["transitive"]["edges"]
        self.assertIn(("spec", "prd"), {(e["subject"]["artifact_kind"], e["object"]["artifact_kind"]) for e in trans})

        # change-fact: prd resolvable, no verdict fields
        fact = core.change_fact(self.home, prd)
        self.assertEqual(fact["resolvability"], "RESOLVABLE")


if __name__ == "__main__":
    unittest.main()
