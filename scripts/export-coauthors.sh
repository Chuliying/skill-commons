#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/export-coauthors.sh [-C <repo>] [--exclude <email>]... <since> [<until>]

Emit Co-authored-by trailers for every author of commits in <since>..<until>
(<until> defaults to HEAD), one line per unique email. Paste the output into
the public snapshot commit message so contributors to the private dev repo
stay visible on the public export.

The author running the export is excluded by default (the repo's
`git config user.email`); pass --exclude to drop additional addresses.
The script is read-only: it never commits, tags, or writes anything.

Options:
  -C <repo>          Scan this repo instead of the one containing the script.
  --exclude <email>  Also exclude this author email (repeatable).
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
EXCLUDES=()
SINCE=""
UNTIL="HEAD"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -C)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      REPO="$2"
      shift
      ;;
    --exclude)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      EXCLUDES+=("$2")
      shift
      ;;
    --*)
      usage
      exit 2
      ;;
    *)
      if [ -z "$SINCE" ]; then
        SINCE="$1"
      elif [ "$UNTIL" = "HEAD" ]; then
        UNTIL="$1"
      else
        usage
        exit 2
      fi
      ;;
  esac
  shift
done

if [ -z "$SINCE" ]; then
  usage
  exit 2
fi

git -C "$REPO" rev-parse --verify --quiet "$SINCE^{commit}" >/dev/null || {
  echo "error: unknown since ref: $SINCE" >&2
  exit 1
}
git -C "$REPO" rev-parse --verify --quiet "$UNTIL^{commit}" >/dev/null || {
  echo "error: unknown until ref: $UNTIL" >&2
  exit 1
}

SELF_EMAIL="$(git -C "$REPO" config user.email || true)"
[ -n "$SELF_EMAIL" ] && EXCLUDES+=("$SELF_EMAIL")

# macOS awk rejects newlines in -v strings, so the exclude list rides ENVIRON.
export COAUTHOR_EXCLUDES="$(printf '%s\n' "${EXCLUDES[@]-}" | tr '[:upper:]' '[:lower:]')"

git -C "$REPO" log --format='%ae%x09%an' "$SINCE..$UNTIL" |
  awk -F '\t' '
    BEGIN {
      n = split(ENVIRON["COAUTHOR_EXCLUDES"], list, "\n")
      for (i = 1; i <= n; i++) if (list[i] != "") skip[list[i]] = 1
    }
    {
      email = tolower($1)
      if (email in skip || email in seen) next
      seen[email] = 1
      printf "Co-authored-by: %s <%s>\n", $2, $1
    }
  ' | sort
