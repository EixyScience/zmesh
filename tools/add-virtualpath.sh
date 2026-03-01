#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

# Add/Upsert a [vpath "..."] rule into a conf file under $ZCONF_DIR/virtualpath.d/
# Default target file: virtualpath.local.conf
#
# Non-interactive friendly:
#   add-virtualpath.sh --vpath "hobby/car" --target "/mnt/xxx/main" --yes
#
# Format:
#   [vpath "hobby/car"]
#   target=/path/to/main
#   type=symlink

ZCONF_DIR="${ZCONF_DIR:-/usr/local/etc/zmesh}"
CONF_DIR="$ZCONF_DIR/virtualpath.d"
DEFAULT_FILE="virtualpath.local.conf"

TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TOOLS_DIR/common.sh"

say(){ printf "%s\n" "$*"; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
cat <<'EOF'
add-virtualpath.sh - add or update a virtual path rule

USAGE
  add-virtualpath.sh --vpath <REL> --target <PATH> [--file <NAME.conf>] [--type symlink] [--yes] [--dry-run]

OPTIONS
  -v, --vpath REL         Virtual path relative to vroot (e.g. "hobby/car") (required)
  -t, --target PATH       Target path (e.g. "/scalefsroot/democell.xx/main") (required)
  -f, --file NAME         Conf filename under $ZCONF_DIR/virtualpath.d/ (default: virtualpath.local.conf)
  --type TYPE             Only "symlink" is currently supported (default: symlink)
  -y, --yes               Do not prompt
  -n, --dry-run            Print actions only

ENV
  ZCONF_DIR               Config directory (default: /usr/local/etc/zmesh)

EXAMPLES
  ZCONF_DIR=/usr/local/etc/zmesh ./tools/add-virtualpath.sh --vpath "hobby/car" --target "/mnt/zmtest/scalefs/a.b/main" --yes
  ZCONF_DIR=/usr/local/etc/zmesh ./tools/add-virtualpath.sh --vpath "work/docs" --target "/data/scalefs/x.y/main" --file virtualpath.site-a.conf --yes
EOF
}

VPATH=""
TARGET=""
FILE="$DEFAULT_FILE"
TYPE="symlink"
YES=0
DRYRUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -v|--vpath) VPATH="${2:-}"; shift 2;;
    --vpath=*)  VPATH="${1#*=}"; shift 1;;
    -t|--target) TARGET="${2:-}"; shift 2;;
    --target=*)  TARGET="${1#*=}"; shift 1;;
    -f|--file) FILE="${2:-}"; shift 2;;
    --file=*)  FILE="${1#*=}"; shift 1;;
    --type) TYPE="${2:-}"; shift 2;;
    --type=*) TYPE="${1#*=}"; shift 1;;
    -y|--yes) YES=1; shift 1;;
    -n|--dry-run|--dryrun) DRYRUN=1; shift 1;;
    *) die "unknown arg: $1 (use --help)";;
  esac
done

[ -n "$VPATH" ] || { usage; die "--vpath is required"; }
[ -n "$TARGET" ] || { usage; die "--target is required"; }
[ "$TYPE" = "symlink" ] || die "unsupported --type: $TYPE (only symlink)"

# normalize vpath: strip leading slashes, collapse //, remove trailing slash
VPATH=$(printf "%s" "$VPATH" | sed 's#^[ /]*##; s#//*#/#g; s#/*$##')

[ -n "$VPATH" ] || die "vpath becomes empty after normalization"

mkdirp() { [ "$DRYRUN" -eq 1 ] && { say "DRYRUN mkdir -p $1"; return 0; } mkdir -p "$1"; }

confirm() {
  [ "$YES" -eq 1 ] && return 0
  printf "%s [y/N]: " "$1"
  read ans || true
  case "$ans" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

mkdirp "$CONF_DIR"
CONF_PATH="$CONF_DIR/$FILE"

# Upsert strategy:
# - If section exists, remove it (block) then append new block at end.
# - If not exists, append.
TMP="${TMPDIR:-/tmp}/zmesh-vpath-add.$$"
trap 'rm -rf "$TMP" >/dev/null 2>&1 || true' EXIT INT TERM
mkdirp "$TMP"
OUT="$TMP/out.conf"

if [ -f "$CONF_PATH" ]; then
  # Remove existing block for this vpath
  awk -v vp="$VPATH" '
  function is_hdr(line,   m){ return match(line, /^vpath[ \t]+"([^"]+)"[ \t]*$/, m) && m[1]==vp }
  BEGIN{ skip=0 }
  {
    line=$0
    if (is_hdr(line)) { skip=1; next }
    if (skip && match(line, /^vpath[ \t]+"([^"]+)"[ \t]*$/)) { skip=0 }
    if (!skip) print $0
  }' "$CONF_PATH" > "$OUT"
else
  : > "$OUT"
fi

# Append new block
{
  printf "\n[vpath \"%s\"]\n" "$VPATH"
  printf "target=%s\n" "$TARGET"
  printf "type=%s\n" "$TYPE"
} >> "$OUT"

if [ "$DRYRUN" -eq 1 ]; then
  say "DRYRUN write: $CONF_PATH"
  say "-----"
  cat "$OUT"
  say "-----"
  exit 0
fi

# confirm overwrite if file doesn't exist? (optional)
if [ ! -f "$CONF_PATH" ] && [ "$YES" -ne