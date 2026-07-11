# Render + upsert managed blocks. Source this file.

AP_START="<!-- skill-commons:start (generated, do not edit; run onboard.sh) -->"
AP_END="<!-- skill-commons:end -->"

render_block() {
  # $1 = directive file, $2 = stamp ; writes block to stdout
  local dir="$1" stamp="$2"
  printf '%s\n' "$AP_START"
  cat "$dir"
  printf '\n<!-- skill-commons-stamp: %s -->\n' "$stamp"
  printf '%s\n' "$AP_END"
}

portable_file_mode() {
  # macOS/BSD stat first, GNU stat second.
  local mode
  mode="$(stat -f '%Lp' "$1" 2>/dev/null)" || mode=""
  case "$mode" in ''|*[!0-7]*) ;; *) printf '%s' "$mode"; return 0 ;; esac
  mode="$(stat -c '%a' "$1" 2>/dev/null)" || mode=""
  case "$mode" in ''|*[!0-7]*) return 1 ;; *) printf '%s' "$mode" ;; esac
}

preserve_file_mode() {
  # $1 = existing destination, $2 = staged replacement
  local mode
  [ -e "$1" ] || return 0
  [ -f "$1" ] && [ ! -L "$1" ] || {
    echo "ERROR: managed file is not a regular file: $1" >&2
    return 1
  }
  mode="$(portable_file_mode "$1")" || {
    echo "ERROR: cannot read managed file mode: $1" >&2
    return 1
  }
  chmod "$mode" "$2"
}

atomic_publish_file() {
  # $1 = same-directory staged file, $2 = destination
  local staged="$1" destination="$2" mask mode
  [ -f "$staged" ] && [ ! -L "$staged" ] || {
    echo "ERROR: staged replacement is not a regular file: $staged" >&2
    return 1
  }
  [ "$(dirname "$staged")" = "$(dirname "$destination")" ] || {
    echo "ERROR: staged replacement is not in the destination directory: $staged" >&2
    return 1
  }
  if [ -e "$destination" ]; then
    preserve_file_mode "$destination" "$staged" || return 1
  else
    # mktemp intentionally starts restrictive; match normal file-creation mode
    # for a newly published text file while respecting the caller's umask.
    mask="$(umask)"
    mode="$((0666 & ~(8#$mask)))"
    chmod "$(printf '%03o' "$mode")" "$staged" || return 1
  fi
  mv -f "$staged" "$destination"
}

upsert_block() {
  # $1 = target file, $2 = block file (output of render_block)
  local file="$1" blockfile="$2" tmp
  mkdir -p "$(dirname "$file")"
  if [ -e "$file" ] || [ -L "$file" ]; then
    [ -f "$file" ] && [ ! -L "$file" ] || {
      echo "ERROR: managed shim is not a regular file: $file" >&2
      return 1
    }
  fi
  tmp="$(mktemp "$file.skill-commons.XXXXXX")" || return 1
  if [ -f "$file" ] && { grep -qF "$AP_START" "$file" || grep -qF "$AP_END" "$file"; }; then
    if ! validate_managed_block "$file"; then
      echo "ERROR: managed shim block is malformed: $file" >&2
      rm -f -- "$tmp"
      return 1
    fi
    if ! awk -v start="$AP_START" -v end="$AP_END" -v bf="$blockfile" '
        $0 == start { while ((getline line < bf) > 0) print line; close(bf); skip=1; next }
        $0 == end { skip=0; next }
        skip { next }
        { print }
      ' "$file" > "$tmp"; then
      rm -f -- "$tmp"
      return 1
    fi
  else
    if [ -f "$file" ]; then cat "$file" > "$tmp" || { rm -f -- "$tmp"; return 1; }; fi
    if [ -f "$file" ] && [ -s "$file" ]; then printf '\n' >> "$tmp"; fi
    cat "$blockfile" >> "$tmp" || { rm -f -- "$tmp"; return 1; }
  fi
  if ! validate_managed_block "$tmp"; then
    echo "ERROR: staged managed shim block is malformed: $file" >&2
    rm -f -- "$tmp"
    return 1
  fi
  atomic_publish_file "$tmp" "$file" || { rm -f -- "$tmp"; return 1; }
}

validate_managed_block() {
  local file="$1" start_count end_count
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  start_count="$(grep -Fxc "$AP_START" "$file" 2>/dev/null || true)"
  end_count="$(grep -Fxc "$AP_END" "$file" 2>/dev/null || true)"
  [ "$start_count" = 1 ] && [ "$end_count" = 1 ] || return 1
  awk -v start="$AP_START" -v end="$AP_END" '
    $0 == start { if (open || closed) exit 1; open=1; next }
    $0 == end { if (!open || closed) exit 1; closed=1; open=0; next }
    END { if (open || !closed) exit 1 }
  ' "$file"
}

# Call only after validate_managed_block() has passed for every uninstall shim.
remove_managed_block() {
  local file="$1" tmp
  validate_managed_block "$file" || {
    echo "ERROR: managed shim block is missing or malformed: $file" >&2
    return 1
  }
  tmp="$(mktemp "$file.skill-commons.XXXXXX")" || return 1
  if ! awk -v start="$AP_START" -v end="$AP_END" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if grep -qF "$AP_START" "$tmp" || grep -qF "$AP_END" "$tmp"; then
    echo "ERROR: staged shim removal still contains a managed fence: $file" >&2
    rm -f -- "$tmp"
    return 1
  fi
  atomic_publish_file "$tmp" "$file" || { rm -f -- "$tmp"; return 1; }
}

render_cursor_rule() {
  # $1 = directive file, $2 = stamp ; writes full .mdc to stdout
  local dir="$1" stamp="$2"
  printf -- '---\nalwaysApply: true\n---\n'
  cat "$dir"
  printf '\n<!-- skill-commons-stamp: %s -->\n' "$stamp"
}
