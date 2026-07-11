#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  T01|T02) exit 0 ;;
  *) exit 2 ;;
esac
