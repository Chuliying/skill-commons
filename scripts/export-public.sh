#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/export-public.sh <target-dir> [--force] [--include-worktree]

Create a clean public payload from the committed HEAD of this private
development repo. The export respects .gitattributes export-ignore rules.

The target may be:
  - a new or empty directory; or
  - an existing Git checkout when --force is provided.

The script never commits, pushes, creates a remote, or changes this repo's
origin. If the target is a Git checkout, its .git directory is preserved.

Options:
  --force             Replace files in an existing Git checkout target.
  --include-worktree  Export a temporary tree from the current working tree.
                      Use this for local dry-runs before committing.
EOF
}

TARGET_INPUT=""
FORCE=0
INCLUDE_WORKTREE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --force)
      FORCE=1
      ;;
    --include-worktree|--worktree)
      INCLUDE_WORKTREE=1
      ;;
    --*)
      usage
      exit 2
      ;;
    *)
      if [ -n "$TARGET_INPUT" ]; then
        usage
        exit 2
      fi
      TARGET_INPUT="$1"
      ;;
  esac
  shift
done

if [ -z "$TARGET_INPUT" ]; then
  usage
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
REPO="$(cd "$REPO" && pwd -P)"

resolve_target_path() {
  local input="$1"
  local path probe suffix next physical_base

  if [ -e "$input" ]; then
    if [ ! -d "$input" ]; then
      echo "error: target exists but is not a directory: $input" >&2
      return 1
    fi
    cd "$input" && pwd -P
    return 0
  fi

  case "$input" in
    /*) path="$input" ;;
    *) path="$PWD/$input" ;;
  esac

  probe="$path"
  suffix=""
  while [ ! -e "$probe" ]; do
    suffix="/$(basename "$probe")$suffix"
    next="$(dirname "$probe")"
    if [ "$next" = "$probe" ]; then
      echo "error: cannot resolve target path: $input" >&2
      return 1
    fi
    probe="$next"
  done

  if [ ! -d "$probe" ]; then
    echo "error: target parent exists but is not a directory: $probe" >&2
    return 1
  fi

  physical_base="$(cd "$probe" && pwd -P)"
  printf '%s%s\n' "$physical_base" "$suffix"
}

TARGET="$(resolve_target_path "$TARGET_INPUT")"

case "$TARGET/" in
  "$REPO/"|"$REPO"/*)
    echo "error: target must be outside the private development repo: $TARGET" >&2
    exit 1
    ;;
esac

TMP="$(mktemp -d)"
PAYLOAD="$TMP/payload"
mkdir -p "$PAYLOAD"
trap 'rm -rf "$TMP"' EXIT

if [ "$INCLUDE_WORKTREE" -eq 1 ]; then
  CANDIDATE_INDEX="$TMP/candidate.index"
  GIT_INDEX_FILE="$CANDIDATE_INDEX" git -C "$REPO" read-tree HEAD
  GIT_INDEX_FILE="$CANDIDATE_INDEX" git -C "$REPO" add -A -- .
  CANDIDATE_TREE="$(GIT_INDEX_FILE="$CANDIDATE_INDEX" git -C "$REPO" write-tree)"
  git -C "$REPO" archive --worktree-attributes "$CANDIDATE_TREE" | tar -x -C "$PAYLOAD"
elif [ -n "$(git -C "$REPO" status --short)" ]; then
  echo "warning: exporting committed HEAD; uncommitted changes are not included" >&2
  git -C "$REPO" archive --worktree-attributes HEAD | tar -x -C "$PAYLOAD"
else
  git -C "$REPO" archive --worktree-attributes HEAD | tar -x -C "$PAYLOAD"
fi

# This belt-and-braces list must stay paired with .gitattributes export-ignore.
for forbidden in \
  "_archive" \
  "docs/work" \
  "docs/STATUS.md" \
  "docs/superpowers" \
  "docs/work-summary.html" \
  "docs/ai-harness-engineering-anthropic.md" \
  "docs/anthropic-skill-system.md" \
  "docs/shared-skill-onboarding-checklist.md" \
  "docs/skill-eval-sop.md"
do
  if [ -e "$PAYLOAD/$forbidden" ]; then
    echo "error: public export contains private path: $forbidden" >&2
    exit 1
  fi
done

private_reorg_entry="$(find "$PAYLOAD/docs/skills-reorg" -mindepth 1 \
  ! -name decisions.md \
  -print -quit 2>/dev/null || true)"
if [ -n "$private_reorg_entry" ]; then
  echo "error: public export contains private skills-reorg material: ${private_reorg_entry#$PAYLOAD/}" >&2
  exit 1
fi

mkdir -p "$TARGET"

target_payload_entry="$(find "$TARGET" -mindepth 1 -maxdepth 1 ! -name .git -print -quit)"
target_has_git=0
if [ -e "$TARGET/.git" ]; then
  target_has_git=1
fi

if [ "$target_has_git" -eq 1 ] && [ "$FORCE" -ne 1 ]; then
  echo "error: target Git checkout exists; rerun with --force to replace its working tree" >&2
  exit 1
fi

if [ -n "$target_payload_entry" ]; then
  if [ "$target_has_git" -ne 1 ]; then
    echo "error: target is a non-empty non-Git directory: $TARGET" >&2
    exit 1
  fi
fi

for target_entry in "$TARGET"/* "$TARGET"/.[!.]* "$TARGET"/..?*; do
  [ -e "$target_entry" ] || [ -L "$target_entry" ] || continue
  if [ "$(basename "$target_entry")" = ".git" ]; then
    continue
  fi
  rm -rf "$target_entry"
done

(
  cd "$PAYLOAD"
  tar -cf - .
) | (
  cd "$TARGET"
  tar -xf -
)

echo "public export written to: $TARGET"
if [ "$target_has_git" -eq 1 ]; then
  echo "next: cd \"$TARGET\" && git status --short"
else
  echo "next: cd \"$TARGET\" && git init && git status --short"
fi
