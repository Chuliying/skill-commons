import unittest

from tests.py import corpus


class TestCorpus(unittest.TestCase):
    def test_rows_iterated_in_order_and_localized(self):
        seen = []
        rows = [{"id": "a", "v": 1}, {"id": "b", "v": 2}]
        corpus.run_corpus(self, rows, lambda r: seen.append(r["id"]))
        self.assertEqual(seen, ["a", "b"])

    def test_adding_one_row_is_one_entry(self):
        rows = [{"id": "only", "v": 1}]
        count = []
        corpus.run_corpus(self, rows, lambda r: count.append(1))
        self.assertEqual(len(count), 1)

    def test_empty_corpus_is_fail_closed(self):
        with self.assertRaises(corpus.CorpusError):
            corpus.run_corpus(self, [], lambda r: None)


if __name__ == "__main__":
    unittest.main()
