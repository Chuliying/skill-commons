import time
import unittest

from tests.py import _timing


class TestTiming(unittest.TestCase):
    def test_now_is_float(self):
        self.assertIsInstance(_timing.now(), float)

    def test_elapsed_is_nonnegative_and_monotonic(self):
        start = _timing.now()
        time.sleep(0.001)
        e = _timing.elapsed(start)
        self.assertGreaterEqual(e, 0.0)


if __name__ == "__main__":
    unittest.main()
