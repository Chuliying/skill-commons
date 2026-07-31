"""In-process monotonic timing helper for the python test layers.

NOTE: verify.sh does NOT use this module. It inlines `time.time()` (epoch) for
per-suite timing, because each shell-out is a separate process and monotonic's
reference point is per-process / undefined, so cross-process deltas are invalid.
monotonic() here is valid only within a single process. Stdlib only.
"""
import time


def now() -> float:
    return time.monotonic()


def elapsed(start: float) -> float:
    return time.monotonic() - start


if __name__ == "__main__":
    # Ad-hoc in-process reading (not used by verify.sh).
    print(f"{now():.6f}")
