#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

# tools/clean-scalefs.sh
# cleanup runtime/state; optionally destroy zfs dataset; optionally remove body dir

ID=""
ROOT=""
PATHV=""
DO_STATE=0
DO_DESTROY_ZFS=0
DO_DESTROY_BODY=0
YES=0

usage() {
cat <<'EOF'
clean-scalefs.sh - cleanup scalefs runtime/state and optionally destroy zfs/body

USAGE
  clean-scalefs.sh (-p PATH | -i ID [-r ROOT]) [--state] [--destroy-zfs] [--destroy-body] [-y]

OPTIONS
  -p, --path PATH         Scalefs body path (e.g. "." or "/scalefsroot/democell.28e671")
  -i, --id ID             Scalefs id (name.shortid)
  -r, --root ALIAS        Root alias (to disambiguate ID)
      --state             Also clear scalefs.state/*
      --destroy-zfs        Destroy ZFS dataset from scalefs.ini (if enabled=true)
      --destroy-body       Remove whole body directory after cleanup
  -y, --yes               Do not prompt
  -h, --help              Show help

EXAMPLES
  clean-scalefs.sh -p . -y
  clean-scalefs.sh -i democell.28e671 -r test --state -y
  clean-scalefs.sh -p /scalefsroot/democell.28e671 --destroy-zfs --destroy-body -y
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path) PATHV="${2:-}"; shift 2;;
    -i|--id) ID="${2:-}"; shift 2;;
    -r|--root) ROOT="${2:-}"; shift 2;;
    --state) DO_STATE=1; shift 1;;
    --destroy-zfs) DO_DESTROY_ZFS=1; shift 1;;
    --destroy-body) DO_DESTROY_BODY=1; shift 1;;
    -y|--yes) YES=1; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 2;;
  esac
done

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TOOLS_DIR/common.sh"

die(){ echo "ERROR: $*" >&2; exit 1; }

resolve_body_path() {
  if [ -n "$PATHV" ]; then
    if [ "$PATHV" = "." ]; then pwd; else (cd "$PATHV" && pwd) || die "not a directory: $PATHV"; fi
    return 0
  fi
  [ -n "$ID" ] || die "require --path or --id"
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

  # unique match
  cands=""
  count=0
  for line in $(printf "%s\n" "$roots" | awk -F'|' '{print $2}'); do
    [ -d "$line/$ID" ] || continue
    cands="$cands $line/$ID"
    count=$((count+1))
  done
  [ "$count" -eq 1 ] || die "could not resolve id=$ID uniquely (specify --root or --path)"
  # shellcheck disable=SC2086
  (cd $cands && pwd)
}

ini_get() {
  ini="$1"; sec="$2"; key="$3"
  awk -v SEC="[$sec]" -v KEY="$key" '
    $0==SEC {in=1; next}
    in && /^\[/ {exit}
    in && $0 ~ "^[[:space:]]*"KEY"[[:space:]]*=" {
      sub("^[[:space:]]*"KEY"[[:space:]]*=","",$0)
      gsub(/[[:space:]]*$/,"",$0)
      print $0
      exit
    }
  ' "$ini" || true
}

DIR="$(resolve_body_path)"
INI="$DIR/scalefs.ini"
[ -f "$INI" ] || die "missing scalefs.ini: $INI"

zfs_enabled="$(ini_get "$INI" zfs enabled)"
zfs_dataset="$(ini_get "$INI" zfs dataset)"

echo "Target: $DIR"
echo "Plan:"
echo "  - clear runtime: scalefs.runtime.d/*"
[ "$DO_STATE" -eq 1 ] && echo "  - clear state:   scalefs.state/*"
[ "$DO_DESTROY_ZFS" -eq 1 ] && echo "  - destroy zfs dataset (if enabled=true): $zfs_dataset"
[ "$DO_DESTROY_BODY" -eq 1 ] && echo "  - remove body directory: $DIR"

if [ "$YES" -ne 1 ]; then
  printf "Proceed? (y/N): "
  read ans || true
  case "${ans:-}" in
    y|Y|yes|YES) : ;;
    *) echo "aborted"; exit 0;;
  esac
fi

# runtime
rm -rf "$DIR/scalefs.runtime.d/"* 2>/dev/null || true

# state
if [ "$DO_STATE" -eq 1 ]; then
  rm -rf "$DIR/scalefs.state/"* 2>/dev/null || true
fi

# destroy zfs dataset
if [ "$DO_DESTROY_ZFS" -eq 1 ]; then
  if detect_zfs && [ "$zfs_enabled" = "true" ] && [ -n "$zfs_dataset" ]; then
    zfs unmount -f "$zfs_dataset" >/dev/null 2>&1 || true
    zfs destroy -r "$zfs_dataset" >/dev/null 2>&1 || true
  fi
fi

# remove body dir
if [ "$DO_DESTROY_BODY" -eq 1 ]; then
  rm -rf "$DIR" 2>/dev/null || true
fi

echo "OK"