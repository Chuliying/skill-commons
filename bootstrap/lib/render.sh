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

upsert_block() {
  # $1 = target file, $2 = block file (output of render_block)
  local file="$1" blockfile="$2"
  if [ -f "$file" ] && grep -qF "$AP_START" "$file"; then
    awk -v start="$AP_START" -v end="$AP_END" -v bf="$blockfile" '
      $0 == start { while ((getline line < bf) > 0) print line; close(bf); skip=1; next }
      $0 == end { skip=0; next }
      skip { next }
      { print }
    ' "$file" > "$file.aptmp" && mv "$file.aptmp" "$file"
  else
    if [ -f "$file" ] && [ -s "$file" ]; then printf '\n' >> "$file"; fi
    cat "$blockfile" >> "$file"
  fi
}

render_cursor_rule() {
  # $1 = directive file, $2 = stamp ; writes full .mdc to stdout
  local dir="$1" stamp="$2"
  printf -- '---\nalwaysApply: true\n---\n'
  cat "$dir"
  printf '\n<!-- skill-commons-stamp: %s -->\n' "$stamp"
}
