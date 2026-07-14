#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/docs/work/skill-bundle-effect-benchmark/benchmark/test_benchmark.py"
python3 "$ROOT/docs/work/skill-bundle-effect-benchmark/benchmark/test_blind_packet_gate.py"
python3 "$ROOT/docs/work/skill-bundle-effect-benchmark/benchmark/test_luna_high_runner.py"
python3 "$ROOT/docs/work/skill-bundle-effect-benchmark/benchmark/test_prepare_viewer.py"
