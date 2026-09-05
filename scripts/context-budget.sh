#!/usr/bin/env bash
# Readable, repository-owned context surface meter.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/context-budget.py" "$@"
