#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

# tools/manifest-scalefs.sh
# Outputs manifest in JSON (default) or INI
# Resolve by -p PATH or -i ID with optional -r ROOT_ALIAS

FORMAT="json"
ID=""
ROOT=""
PATHV=""

usage() {
cat <<'EOF'
manifest-scalefs.sh - print scalefs manifest (json/ini)

USAGE
  manifest-scalefs.sh [-p PATH] [-i ID [-r ROOT]] [-f json|ini]

OPTIONS
  -p, --path PATH       Scalefs body path (e.g. "." or "/scalefsroot/democell.28e671")
  -i, --id ID           Scalefs id (name.shortid)
  -r, --root ALIAS      Root alias (to disambiguate ID)
  -f, --format FMT      "json" (default) or "ini"
  -h, --help            Show help

EXAMPLES
  manifest-scalefs.sh -p .
  manifest-scalefs.sh -i democell.28e671 -r test
  manifest-scalefs.sh -p /scalefsroot/democell.28e671 -f ini
EOF
}

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path) PATHV="${2:-}"; shift 2;;
    -i|--id) ID="${2:-}"; shift 2;;
    -r|--root) ROOT="${2:-}"; shift 2;;
    -f|--format) FORMAT="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 2;;
  esac
done

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_DIR="$BASE_DIR/tools"

# common.sh provides load_roots and normalize_name
. "$TOOLS_DIR/common.sh"

die(){ echo "ERROR: $*" >&2; exit 1; }

# resolve body path
resolve_body_path() {
  if [ -n "$PATHV" ]; then
    if [ "$PATHV" = "." ]; then
      pwd
    else
      # keep as-is but normalize
      (cd "$PATHV" 2>/dev/null && pwd) || die "not a directory: $PATHV"
    fi
    return 0
  fi

  [ -n "$ID" ] || die "require --path or --id"
  # search roots
  roots="$(load_roots || true)"
  [ -n "$roots" ] || die "no roots configured (ZCONF_DIR=$ZCONF_DIR)"

  if [ -n "$ROOT" ]; then
    p="$(printf "%s\n" "$roots" | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
    [ -n "$p" ] || die "unknown root alias: $ROOT"
    d="$p/$ID"
    [ -d "$d" ] || die "not found: $d"
    (cd "$d" && pwd)
    return 0
  fi

  # unique match across roots
  found=""
  count=0
  printf "%s\n" "$roots" | while IFS='|' read a p; do
    [ -d "$p/$ID" ] || continue
    echo "$p/$ID"
  done > /tmp/.zmesh_manifest_candidates.$$ 2>/dev/null || true

  if [ -f /tmp/.zmesh_manifest_candidates.$$ ]; then
    count=$(wc -l < /tmp/.zmesh_manifest_candidates.$$ | tr -d ' ')
    if [ "$count" -eq 1 ]; then
      found=$(cat /tmp/.zmesh_manifest_candidates.$$)
      rm -f /tmp/.zmesh_manifest_candidates.$$
      (cd "$found" && pwd)
      return 0
    fi
    rm -f /tmp/.zmesh_manifest_candidates.$$
  fi

  die "could not resolve id=$ID uniquely (specify --root or --path)"
}

DIR="$(resolve_body_path)"
INI="$DIR/scalefs.ini"
[ -f "$INI" ] || die "missing scalefs.ini: $INI"

# INI read helper (section/key)
ini_get() {
  sec="$1"; key="$2"
  awk -v SEC="[$sec]" -v KEY="$key" '
    $0==SEC {in=1; next}
    in && /^\[/ {exit}
    in && $0 ~ "^[[:space:]]*"KEY"[[:space:]]*=" {
      sub("^[[:space:]]*"KEY"[[:space:]]*=","",$0)
      gsub(/[[:space:]]*$/,"",$0)
      print $0
      exit
    }
  ' "$INI" || true
}

idv="$(ini_get scalefs id)"
namev="$(ini_get scalefs name)"
sidv="$(ini_get scalefs shortid)"
state_dir="$(ini_get paths state_dir)"
watch_root="$(ini_get paths watch_root)"
zfs_enabled="$(ini_get zfs enabled)"
zfs_pool="$(ini_get zfs pool)"
zfs_dataset="$(ini_get zfs dataset)"

now="$(date +%s)"
os="unix"

mainp="$DIR/main"
statep="$DIR/scalefs.state"
globalp="$DIR/scalefs.global.d"
localp="$DIR/scalefs.local.d"
runtimep="$DIR/scalefs.runtime.d"

if [ "$FORMAT" = "ini" ]; then
  cat <<EOF
[manifest]
generated_unix=$now
os=$os
path=$DIR

[scalefs]
id=$idv
name=$namev
shortid=$sidv

[paths]
main=$mainp
state=$statep
global_d=$globalp
local_d=$localp
runtime_d=$runtimep

[config]
state_dir=$state_dir
watch_root=$watch_root

[zfs]
enabled=$zfs_enabled
pool=$zfs_pool
dataset=$zfs_dataset
EOF
  exit 0
fi

# JSON (minimal escaping: good enough for our fields)
json_escape() {
  printf "%s" "$1" | awk 'BEGIN{ORS=""}{
    gsub(/\\/,"\\\\"); gsub(/"/,"\\\"");
    gsub(/\r/,""); gsub(/\n/,"\\n");
    print
  }'
}

cat <<EOF
{
  "ok": true,
  "generated_unix": $now,
  "os": "$(json_escape "$os")",
  "path": "$(json_escape "$DIR")",
  "scalefs": {
    "id": "$(json_escape "$idv")",
    "name": "$(json_escape "$namev")",
    "shortid": "$(json_escape "$sidv")"
  },
  "paths": {
    "main": "$(json_escape "$mainp")",
    "state": "$(json_escape "$statep")",
    "global_d": "$(json_escape "$globalp")",
    "local_d": "$(json_escape "$localp")",
    "runtime_d": "$(json_escape "$runtimep")"
  },
  "config": {
    "state_dir": "$(json_escape "$state_dir")",
    "watch_root": "$(json_escape "$watch_root")"
  },
  "zfs": {
    "enabled": "$(json_escape "$zfs_enabled")",
    "pool": "$(json_escape "$zfs_pool")",
    "dataset": "$(json_escape "$zfs_dataset")"
  }
}
EOF