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
clean-scalefs.sh - cleanup a scalefs body (runtime/state) and optionally destroy zfs/directory

USAGE
  clean-scalefs.sh [-i ID] [-r ROOT] [-p PATH] [--state] [--destroy-zfs] [--destroy-body] [-y] [-h]

OPTIONS
  -i, --id ID           scalefs id (name.shortid)
  -r, --root ROOT       root alias (needed if id is not unique across roots)
  -p, --path PATH       body path (use "." for current dir)
      --state           also clear scalefs.state/*
      --destroy-zfs      destroy zfs dataset referenced by scalefs.ini (best-effort)
      --destroy-body     remove body directory (after optional zfs destroy)
  -y, --yes             do not ask confirmation
  -h, --help            show help

EXAMPLES
  clean-scalefs.sh -p .                 # clear runtime only
  clean-scalefs.sh -i democell.28e671 --state
  clean-scalefs.sh -i democell.28e671 --destroy-zfs --destroy-body -y
EOF
}

die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

ID=""
ROOT=""
PATH_IN=""
DO_STATE=0
DO_DESTROY_ZFS=0
DO_DESTROY_BODY=0
YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -i|--id) ID="${2:-}"; shift 2;;
    -r|--root) ROOT="${2:-}"; shift 2;;
    -p|--path) PATH_IN="${2:-}"; shift 2;;
    --state) DO_STATE=1; shift 1;;
    --destroy-zfs) DO_DESTROY_ZFS=1; shift 1;;
    --destroy-body) DO_DESTROY_BODY=1; shift 1;;
    -y|--yes) YES=1; shift 1;;
    *) die "unknown arg: $1";;
  esac
done

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
      match($0, "^[[:space:]]*"key"[[:space:]]*=[[:space:]]*(.*)$", m)
      if (m[1]!="") { print m[1]; exit }
    }
  ' "$_file"
}

resolve_body_dir() {
  if [ -n "$PATH_IN" ]; then
    if [ "$PATH_IN" = "." ]; then
      pwd
      return 0
    fi
    if command -v realpath >/dev/null 2>&1; then
      realpath "$PATH_IN"
    else
      (cd "$PATH_IN" 2>/dev/null && pwd) || die "cannot resolve path: $PATH_IN"
    fi
    return 0
  fi

  [ -n "$ID" ] || die "require -p PATH or -i ID"

  if [ -n "$ROOT" ]; then
    PATHVAL="$(load_roots | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
    [ -n "$PATHVAL" ] || die "unknown root alias: $ROOT"
    echo "$PATHVAL/$ID"
    return 0
  fi

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

confirm() {
  msg="$1"
  if [ "$YES" -eq 1 ]; then return 0; fi
  printf "%s [y/N]: " "$msg"
  read ans || true
  case "$(printf "%s" "${ans:-}" | tr '[:upper:]' '[:lower:]')" in
    y|yes) return 0;;
  esac
  return 1
}

DIR="$(resolve_body_dir)"
[ -d "$DIR" ] || die "not a directory: $DIR"

INI="$DIR/scalefs.ini"
[ -f "$INI" ] || die "missing scalefs.ini: $INI"

ZFS_ENABLED="$(ini_get "$INI" zfs enabled)"
ZFS_DATASET="$(ini_get "$INI" zfs dataset)"

printf "Target: %s\n" "$DIR"
printf "Plan:\n"
printf "  - clear runtime: %s\n" "$DIR/scalefs.runtime.d/*"
if [ "$DO_STATE" -eq 1 ]; then printf "  - clear state:   %s\n" "$DIR/scalefs.state/*"; fi
if [ "$DO_DESTROY_ZFS" -eq 1 ]; then printf "  - destroy zfs dataset (if any): %s\n" "${ZFS_DATASET:-}"; fi
if [ "$DO_DESTROY_BODY" -eq 1 ]; then printf "  - remove body directory: %s\n" "$DIR"; fi

confirm "Proceed?" || die "aborted"

# runtime cleanup
if [ -d "$DIR/scalefs.runtime.d" ]; then
  rm -rf "$DIR/scalefs.runtime.d/"* 2>/dev/null || true
fi

# state cleanup
if [ "$DO_STATE" -eq 1 ] && [ -d "$DIR/scalefs.state" ]; then
  rm -rf "$DIR/scalefs.state/"* 2>/dev/null || true
fi

# zfs destroy (best-effort)
if [ "$DO_DESTROY_ZFS" -eq 1 ]; then
  if detect_zfs && [ "${ZFS_ENABLED:-}" = "true" ] && [ -n "${ZFS_DATASET:-}" ]; then
    # guard: don't allow destroying a pool root by mistake
    case "$ZFS_DATASET" in
      */*) : ;;
      *) die "refuse to destroy suspicious dataset name: $ZFS_DATASET";;
    esac

    zfs unmount -f "$ZFS_DATASET" >/dev/null 2>&1 || true
    zfs destroy -r "$ZFS_DATASET" >/dev/null 2>&1 || true
  fi
fi

# body removal
if [ "$DO_DESTROY_BODY" -eq 1 ]; then
  rm -rf "$DIR"
fi

printf "OK\n"