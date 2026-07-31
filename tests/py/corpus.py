"""Table-driven adversarial corpus runner (spec FR-003 / D-005).

New counterexample = one data row. `run_corpus` iterates rows via `subTest` so a
failure localizes to the offending row. An empty corpus is fail-closed (raises
CorpusError) -- it must never silently pass. Stdlib only.
"""
import unittest
from typing import Callable, Mapping, Sequence


class CorpusError(RuntimeError):
    """Raised when a corpus is empty (fail-closed; refuses to pass silently)."""


def run_corpus(
    case: unittest.TestCase,
    rows: Sequence[Mapping],
    check: Callable[[Mapping], None],
) -> None:
    if not rows:
        raise CorpusError("empty corpus: 0 rows (fail-closed, refusing silent pass)")
    for row in rows:
        with case.subTest(id=row.get("id", "?")):
            check(row)
