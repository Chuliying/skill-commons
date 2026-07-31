"""AC-004 proof-of-use: two ported behavioral counterexamples run end-to-end on
the harness (factory + corpus + e2e layer), proving the foundation is usable and
"new counterexample = one row". (spec I07)"""
import subprocess
import unittest

from tests.py import corpus, factory


class TestProofOfUse(unittest.TestCase):
    def test_corpus_over_factory_fixtures_end_to_end(self):
        # Ported representative counterexamples: git HEAD resolvability must match
        # expectation across a clean fixture vs a fault-injected (broken-git) one.
        rows = [
            {"id": "clean-repo-has-head", "break": False, "expect_head": True},
            {"id": "broken-git-has-no-head", "break": True, "expect_head": False},
        ]

        def check(row):
            with factory.make_repo({"a.txt": "x\n"}) as fx:
                if row["break"]:
                    factory.inject_broken_git(fx)
                rc = subprocess.run(
                    ["git", "rev-parse", "HEAD"],
                    cwd=str(fx.path),
                    capture_output=True,
                )
                self.assertEqual(rc.returncode == 0, row["expect_head"])

        corpus.run_corpus(self, rows, check)


if __name__ == "__main__":
    unittest.main()
