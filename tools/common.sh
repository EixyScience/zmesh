#!/bin/sh
set -eu

# ------------------------------------------------------------
# common helpers for zmesh/scalefs tools (POSIX sh)
# - robust sourcing regardless of current working directory
# ------------------------------------------------------------

# If this file is sourced, $0 points to the caller.
# We keep COMMON_DIR as "the directory where common.sh exists".
# Prefer BASH_SOURCE-like behavior is not available in POSIX sh,
# so each tool should source common.sh using: . "$SCRIPT_DIR/common.sh"
COMMON_DIR="${COMMON_DIR:-}"

# Default config dir
ZCONF_DIR="${ZCONF_DIR:-/usr/local/etc/zmesh}"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

# -------- id helpers --------
gen_shortid() {
  s="$(date +%s)"
  if command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$s" | sha256sum | cut -c1-6
  elif command -v sha1sum >/dev/null 2>&1; then
    printf "%s" "$s" | sha1sum | cut -c1-6
  elif command -v shasum >/dev/null 2>&1; then
    printf "%s" "$s" | shasum -a 256 | cut -c1-6
  elif command -v openssl >/dev/null 2>&1; then
    printf "%s" "$s" | openssl dgst -sha256 | awk '{print $2}' | cut -c1-6
  else
    # 最終手段（衝突リスクは上がる）
    printf "%s" "$s" | tail -c 6
  fi
}

normalize_name() {
  echo "${1:-}" |
    tr '[:upper:]' '[:lower:]' |
    tr -cd 'a-z0-9._-' |
    sed 's/^[^a-z0-9]*//'
}

detect_zfs() {
  command -v zfs >/dev/null 2>&1
}

# -------- config roots --------
load_roots() {
  # root conf format:
  #   [root "NAME"]
  #   path=/some/dir
  # This function prints: NAME|/some/dir
  for f in "$ZCONF_DIR"/zmesh.d/*.conf; do
    [ -f "$f" ] || continue
    awk '
      /^\[root "/ {
        gsub(/^\[root "/,"")
        gsub(/"\]/,"")
        name=$0
      }
      /^path=/ {
        path=substr($0,6)
        print name "|" path
      }
    ' "$f"
  done
}

# -------- path helpers --------
abspath() {
  # abspath <path>
  p="${1:-}"
  [ -n "$p" ] || return 0
  case "$p" in
    /*) printf "%s\n" "$p";;
    *)  printf "%s\n" "$(pwd)/$p";;
  esac
}