#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
manifest-scalefs.sh - print a scalefs "manifest" (resolved paths + zfs info)

USAGE
  manifest-scalefs.sh [-i ID] [-r ROOT] [-p PATH] [-f json|ini] [-h]

OPTIONS
  -i, --id ID         scalefs id (name.shortid)
  -r, --root ROOT     root alias (needed if id is not unique across roots)
  -p, --path PATH     body path (use "." for current dir)
  -f, --format FMT    json (default) | ini
  -h, --help          show help

EXAMPLES
  manifest-scalefs.sh -p .
  manifest-scalefs.sh -i democell.28e671 -r test
  manifest-scalefs.sh -p /path/to/democell.28e671 -f ini
EOF
}

die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

FMT="json"
ID=""
ROOT=""
PATH_IN=""

# ---------------------------
# args
# ---------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -f|--format) FMT="${2:-}"; shift 2;;
    -i|--id) ID="${2:-}"; shift 2;;
    -r|--root) ROOT="${2:-}"; shift 2;;
    -p|--path) PATH_IN="${2:-}"; shift 2;;
    *) die "unknown arg: $1";;
  esac
done

[ "$FMT" = "json" ] || [ "$FMT" = "ini" ] || die "bad --format: $FMT"

# ---------------------------
# ini reader (simple)
# ---------------------------
ini_get() {
  _file="$1"; _sec="$2"; _key="$3"
  awk -v sec="[$_sec]" -v key="$_key" '
    BEGIN{in=0}
    $0 ~ /^[[:space:]]*#/ {next}
    $0 ~ /^[[:space:]]*;/{next}
    $0 ~ /^[[:space:]]*\[/{
      in = ($0==sec)?1:0
      next
    }
    in==1 {
      # key = value
      match($0, "^[[:space:]]*"key"[[:space:]]*=[[:space:]]*(.*)$", m)
      if (m[1]!="") { print m[1]; exit }
    }
  ' "$_file"
}

resolve_body_dir() {
  # If -p is given, use it.
  if [ -n "$PATH_IN" ]; then
    if [ "$PATH_IN" = "." ]; then
      pwd
      return 0
    fi
    # best-effort realpath
    if command -v realpath >/dev/null 2>&1; then
      realpath "$PATH_IN"
    else
      # fallback
      (cd "$PATH_IN" 2>/dev/null && pwd) || die "cannot resolve path: $PATH_IN"
    fi
    return 0
  fi

  [ -n "$ID" ] || die "require -p PATH or -i ID"

  # If -r root is given, resolve directly
  if [ -n "$ROOT" ]; then
    PATHVAL="$(load_roots | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
    [ -n "$PATHVAL" ] || die "unknown root alias: $ROOT"
    echo "$PATHVAL/$ID"
    return 0
  fi

  # otherwise: unique match across all roots
  cands=""
  load_roots | while IFS='|' read -r alias path; do
    [ -n "$path" ] || continue
    d="$path/$ID"
    if [ -d "$d" ]; then
      printf "%s\n" "$d"
    fi
  done > "${TMPDIR:-/tmp}/zmesh.cands.$$"

  n="$(wc -l < "${TMPDIR:-/tmp}/zmesh.cands.$$" | tr -d ' ')"
  if [ "$n" -ne 1 ]; then
    rm -f "${TMPDIR:-/tmp}/zmesh.cands.$$"
    die "could not resolve id=$ID uniquely (use -r ROOT or -p PATH)"
  fi
  cat "${TMPDIR:-/tmp}/zmesh.cands.$$"
  rm -f "${TMPDIR:-/tmp}/zmesh.cands.$$"
}

DIR="$(resolve_body_dir)"
[ -d "$DIR" ] || die "not a directory: $DIR"

INI="$DIR/scalefs.ini"
[ -f "$INI" ] || die "missing scalefs.ini: $INI"

# read scalefs.ini
IDV="$(ini_get "$INI" scalefs id)"
NAME="$(ini_get "$INI" scalefs name)"
SID="$(ini_get "$INI" scalefs shortid)"

STATE_DIR="$(ini_get "$INI" paths state_dir)"
WATCH_ROOT="$(ini_get "$INI" paths watch_root)"

ZFS_ENABLED="$(ini_get "$INI" zfs enabled)"
ZFS_POOL="$(ini_get "$INI" zfs pool)"
ZFS_DATASET="$(ini_get "$INI" zfs dataset)"

NOW_UNIX="$(date -u +%s 2>/dev/null || date +%s)"

MAIN_PATH="$DIR/main"
STATE_PATH="$DIR/scalefs.state"
GD_PATH="$DIR/scalefs.global.d"
LD_PATH="$DIR/scalefs.local.d"
RD_PATH="$DIR/scalefs.runtime.d"

# OS label
OS="unix"
uname_s="$(uname -s 2>/dev/null || true)"
case "$uname_s" in
  FreeBSD) OS="freebsd";;
  Linux) OS="linux";;
esac

if [ "$FMT" = "ini" ]; then
  cat <<EOF
[manifest]
generated_unix=$NOW_UNIX
os=$OS
path=$DIR

[scalefs]
id=$IDV
name=$NAME
shortid=$SID

[paths]
main=$MAIN_PATH
state=$STATE_PATH
global_d=$GD_PATH
local_d=$LD_PATH
runtime_d=$RD_PATH

[config]
state_dir=$STATE_DIR
watch_root=$WATCH_ROOT

[zfs]
enabled=$ZFS_ENABLED
pool=$ZFS_POOL
dataset=$ZFS_DATASET
EOF
  exit 0
fi

# json (no jq dependency)
json_escape() {
  # minimal JSON string escaper (quotes/backslashes/newlines)
  printf "%s" "$1" | awk '
    BEGIN{ORS=""}
    {
      gsub(/\\/,"\\\\")
      gsub(/"/,"\\\"")
      gsub(/\r/,"\\r")
      gsub(/\n/,"\\n")
      print
    }'
}

cat <<EOF
{
  "ok": true,
  "generated_unix": $NOW_UNIX,
  "os": "$(json_escape "$OS")",
  "path": "$(json_escape "$DIR")",
  "scalefs": { "id": "$(json_escape "$IDV")", "name": "$(json_escape "$NAME")", "shortid": "$(json_escape "$SID")" },
  "paths": {
    "main": "$(json_escape "$MAIN_PATH")",
    "state": "$(json_escape "$STATE_PATH")",
    "global_d": "$(json_escape "$GD_PATH")",
    "local_d": "$(json_escape "$LD_PATH")",
    "runtime_d": "$(json_escape "$RD_PATH")"
  },
  "config": { "state_dir": "$(json_escape "$STATE_DIR")", "watch_root": "$(json_escape "$WATCH_ROOT")" },
  "zfs": { "enabled": "$(json_escape "$ZFS_ENABLED")", "pool": "$(json_escape "$ZFS_POOL")", "dataset": "$(json_escape "$ZFS_DATASET")" }
}
EOF