#!/usr/bin/env bash
# Stable CLI; the executable v1/v2 contract lives alongside this entrypoint.
set -euo pipefail
exec python3 "$(cd "$(dirname "$0")" && pwd)/prototype_contract.py" "$@"
