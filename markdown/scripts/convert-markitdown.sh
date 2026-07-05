#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  convert-markitdown.sh <input-file> [output-file]

Converts a local workspace file to Markdown using the optional MarkItDown CLI.
Supports PDF, Office, and images (PNG, JPG, JPEG, WebP, GIF) when markitdown is installed.

Safety defaults:
  - local files only, no URI inputs
  - input and output must stay under PROJECT_ROOT or the current git root
  - existing output files are not overwritten unless MARKITDOWN_OVERWRITE=1
  - MarkItDown plugins are not enabled
  - pandas placeholder values like "Unnamed: 0" and empty-cell "NaN" are stripped unless MARKITDOWN_KEEP_TABLE_NOISE=1

Runtime:
  - Python 3.10+
  - markitdown CLI, suggested package: markitdown[pdf,docx,pptx,xlsx]==0.1.5
USAGE
}

fail() {
  printf 'convert-markitdown: %s\n' "$*" >&2
  exit 1
}

resolve_existing_file() {
  local target="$1"
  local dir
  local base
  dir="$(dirname -- "$target")"
  base="$(basename -- "$target")"

  [[ -d "$dir" ]] || fail "directory does not exist: $dir"
  [[ -f "$target" ]] || fail "input file does not exist: $target"

  (cd "$dir" && printf '%s/%s\n' "$(pwd -P)" "$base")
}

resolve_path() {
  local target="$1"
  local dir
  local base
  dir="$(dirname -- "$target")"
  base="$(basename -- "$target")"

  [[ -d "$dir" ]] || fail "output directory does not exist: $dir"

  (cd "$dir" && printf '%s/%s\n' "$(pwd -P)" "$base")
}

is_under_root() {
  local path="$1"
  local root="$2"
  [[ "$path" == "$root" || "$path" == "$root"/* ]]
}

clean_markdown_noise() {
  local target="$1"

  [[ "${MARKITDOWN_KEEP_TABLE_NOISE:-0}" != "1" ]] || return 0

  if ! command -v perl >/dev/null 2>&1; then
    fail "perl is required to strip table noise (set MARKITDOWN_KEEP_TABLE_NOISE=1 to skip cleanup)"
  fi

  perl -0pi -e '
    s/\bUnnamed:\s*\d+(?:\.\d+)?(?:_level_\d+)?\b//g;
    1 while s/(?<=\|)\s*NaN\s*(?=\|)/ /g;
  ' "$target"
}

find_python_310() {
  local candidate
  for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" - "$candidate" <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
PY
      then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  done
  return 1
}

[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || {
  usage
  exit 0
}

[[ $# -ge 1 && $# -le 2 ]] || {
  usage
  exit 2
}

input="$1"
output="${2:-}"

if [[ "$input" =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]]; then
  fail "URI inputs are not allowed; provide a local workspace file"
fi

project_root="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
project_root_abs="$(cd "$project_root" && pwd -P)"
input_abs="$(resolve_existing_file "$input")"

is_under_root "$input_abs" "$project_root_abs" || fail "input must be under project root: $project_root_abs"

if [[ -z "$output" ]]; then
  output="${input%.*}.md"
fi

if [[ "$output" =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]]; then
  fail "URI outputs are not allowed; provide a local workspace path"
fi

output_abs="$(resolve_path "$output")"
is_under_root "$output_abs" "$project_root_abs" || fail "output must be under project root: $project_root_abs"

if [[ -e "$output_abs" && "${MARKITDOWN_OVERWRITE:-0}" != "1" ]]; then
  fail "output already exists: $output_abs (set MARKITDOWN_OVERWRITE=1 to replace it)"
fi

python_bin="$(find_python_310)" || fail "Python 3.10+ is required. Install Python 3.10+ and MarkItDown, for example: python3.12 -m pip install 'markitdown[pdf,docx,pptx,xlsx]==0.1.5'"

if ! command -v markitdown >/dev/null 2>&1; then
  fail "markitdown CLI not found. Suggested install: $python_bin -m pip install 'markitdown[pdf,docx,pptx,xlsx]==0.1.5'"
fi

markitdown "$input_abs" -o "$output_abs"
clean_markdown_noise "$output_abs"
printf 'Converted %s -> %s\n' "$input_abs" "$output_abs"
