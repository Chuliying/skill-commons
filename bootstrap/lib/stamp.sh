# Content-derived stamp helpers. Source this file.

_sha256_hex() {
  # reads stdin, prints hex digest
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    echo "ERROR: need sha256sum or shasum" >&2
    return 1
  fi
}

compute_stamp() {
  # $1 = file path -> prints 12-char stamp, or errors (rc!=0) if missing
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "ERROR: file not found: $file" >&2
    return 1
  fi
  _sha256_hex < "$file" | cut -c1-12
}
