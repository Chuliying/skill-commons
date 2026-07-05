import unittest

from src.greet import greet


class GreetTest(unittest.TestCase):
    def test_greeting(self) -> None:
        self.assertEqual("hello Codex", greet("Codex"))


if __name__ == "__main__":
    unittest.main()
