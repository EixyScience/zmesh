#!/bin/sh
# Common helpers for zmesh/scalefs tools (POSIX sh)

set -eu

ZCONF_DIR="${ZCONF_DIR:-/usr/local/etc/zmesh}"

# ------------------------------------------------------------
# short id (6 hex-ish)
# ------------------------------------------------------------
gen_shortid() {
  s="$(date +%s)"
  if command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$s" | sha256sum | awk '{print $1}' | cut -c1-6
  elif command -v sha1sum >/dev/null 2>&1; then
    printf "%s" "$s" | sha1sum | awk '{print $1}' | cut -c1-6
  elif command -v shasum >/dev/null 2>&1; then
    printf "%s" "$s" | shasum -a 256 | awk '{print $1}' | cut -c1-6
  elif command -v openssl >/dev/null 2>&1; then
    # openssl dgst -sha256 prints: "(stdin)= <hash>" or "SHA2-256(stdin)= <hash>"
    printf "%s" "$s" | openssl dgst -sha256 | awk '{print $NF}' | cut -c1-6
  else
    # last resort: low entropy, but keeps working
    printf "%s" "$s" | tail -c 6
  fi
}

# ------------------------------------------------------------
# name normalization: lower + allow [a-z0-9._-] + trim non-alnum prefix
# ------------------------------------------------------------
normalize_name() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cd 'a-z0-9._-' \
    | sed 's/^[^a-z0-9]*//'
}

# ------------------------------------------------------------
# zfs available?
# ------------------------------------------------------------
detect_zfs() {
  command -v zfs >/dev/null 2>&1
}

# ------------------------------------------------------------
# load roots from $ZCONF_DIR/zmesh.d/*.conf
# expected format:
#   [root "alias"]
#   path=/some/path
# output:
#   alias|/some/path
# ------------------------------------------------------------
load_roots() {
  d="$ZCONF_DIR/zmesh.d"
  [ -d "$d" ] || return 0

  found=0
  for f in "$d"/*.conf; do
    [ -f "$f" ] || continue
    found=1
    awk '
      /^\[root "/ {
        gsub(/^\[root "/,"")
        gsub(/"\]/,"")
        name=$0
      }
      /^path=/ {
        path=substr($0,6)
        if (name != "" && path != "") {
          print name "|" path
        }
      }
    ' "$f"
  done

  # no files -> no output
  [ "$found" -eq 1 ] || true
}