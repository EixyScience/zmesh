#!/bin/sh
set -eu

. ./common.sh

ID=""
ROOT=""
PATHVAL=""
DO_STATE=0
DO_DESTROY_ZFS=0
DO_DESTROY_BODY=0
YES=0

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: clean-scalefs.sh [options]

Options:
  -h, --help          Show help
  -i, --id ID         Target by id (name.shortid)
  -r, --root ALIAS    Root alias (used with -i)
  -p, --path PATH     Target by explicit body path
  --state             Also clear scalefs.state contents
  --destroy-zfs        Destroy ZFS dataset if configured in scalefs.ini
  --destroy-body       Remove the whole body directory
  --yes               Skip confirmation

Examples:
  clean-scalefs.sh -p /mnt/zmtest/scalefsroot/democell.28e671 --yes
  clean-scalefs.sh -i democell.28e671 -r test --state --yes
  clean-scalefs.sh -p /mnt/zmtest/scalefsroot/democell.28e671 --destroy-zfs --destroy-body --yes
EOF
}

confirm() {
  msg="$1"
  if [ "$YES" -eq 1 ]; then return 0; fi
  printf "%s [y/N]: " "$msg"
  read ans || true
  case "${ans:-}" in
    y|Y|yes|YES) return 0;;
    *) return 1;;
  esac
}

# parse
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -i|--id) ID="${2:-}"; shift 2;;
    -r|--root) ROOT="${2:-}"; shift 2;;
    -p|--path) PATHVAL="${2:-}"; shift 2;;
    --state) DO_STATE=1; shift;;
    --destroy-zfs) DO_DESTROY_ZFS=1; shift;;
    --destroy-body) DO_DESTROY_BODY=1; shift;;
    --yes) YES=1; shift;;
    *) die "unknown arg: $1";;
  esac
done

# resolve DIR
if [ -n "$PATHVAL" ]; then
  DIR="$PATHVAL"
else
  [ -n "$ID" ] || die "require --path or --id"
  if [ -z "$ROOT" ]; then
    found=""
    resolve_root_path | while IFS='|' read alias path; do
      [ -d "$path/$ID" ] && printf "%s\n" "$path/$ID"
    done > /tmp/.zmesh_clean_candidates.$$ 2>/dev/null || true
    if [ -f /tmp/.zmesh_clean_candidates.$$ ]; then
      n="$(wc -l < /tmp/.zmesh_clean_candidates.$$ | tr -d ' ')"
      if [ "$n" -eq 1 ]; then
        found="$(cat /tmp/.zmesh_clean_candidates.$$)"
      fi
      rm -f /tmp/.zmesh_clean_candidates.$$ || true
    fi
    [ -n "$found" ] || die "could not resolve id=$ID (specify --root or --path)"
    DIR="$found"
  else
    base="$(resolve_root_path | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
    [ -n "$base" ] || die "unknown root alias: $ROOT"
    DIR="$base/$ID"
  fi
fi

case "$DIR" in
  .) DIR="$(pwd)";;
esac

[ -d "$DIR" ] || die "not a directory: $DIR"
INI="$DIR/scalefs.ini"
[ -f "$INI" ] || die "missing scalefs.ini: $INI"

get_ini_kv() {
  sec="$1"; key="$2"
  awk -v sec="[$sec]" -v key="$key" '
    BEGIN{in=0}
    $0==sec{in=1; next}
    in==1 && /^\[/{exit}
    in==1{
      if ($0 ~ "^[[:space:]]*"key"[[:space:]]*=") {
        sub("^[[:space:]]*"key"[[:space:]]*=","")
        gsub("\r","")
        print
        exit
      }
    }
  ' "$INI"
}

zfs_enabled="$(get_ini_kv zfs enabled)"
zfs_dataset="$(get_ini_kv zfs dataset)"

# plan
say "Target: $DIR"
say "Plan:"
say "  - clear runtime: scalefs.runtime.d/*"
if [ "$DO_STATE" -eq 1 ]; then
  say "  - clear state:   scalefs.state/*"
fi
if [ "$DO_DESTROY_ZFS" -eq 1 ]; then
  say "  - destroy zfs dataset (if any): $zfs_dataset"
fi
if [ "$DO_DESTROY_BODY" -eq 1 ]; then
  say "  - remove body directory: $DIR"
fi

confirm "Proceed?" || die "aborted"

# 1) runtime cleanup
if [ -d "$DIR/scalefs.runtime.d" ]; then
  rm -rf "$DIR/scalefs.runtime.d"/* 2>/dev/null || true
fi

# 2) optional state cleanup
if [ "$DO_STATE" -eq 1 ] && [ -d "$DIR/scalefs.state" ]; then
  rm -rf "$DIR/scalefs.state"/* 2>/dev/null || true
fi

# 3) optional zfs destroy
if [ "$DO_DESTROY_ZFS" -eq 1 ]; then
  if [ "${zfs_enabled:-false}" = "true" ] && [ -n "${zfs_dataset:-}" ] && detect_zfs; then
    # best effort unmount then destroy
    zfs unmount "$zfs_dataset" >/dev/null 2>&1 || true
    zfs destroy -r "$zfs_dataset" >/dev/null 2>&1 || true
  fi
fi

# 4) optional body removal
if [ "$DO_DESTROY_BODY" -eq 1 ]; then
  # if mounted, this may fail; that's OK for best-effort.
  rm -rf "$DIR" 2>/dev/null || true
fi

say "OK"