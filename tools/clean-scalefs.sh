#!/bin/sh
set -eu

# Clean scalefs runtime/state and optionally destroy zfs/body.
# Safe by default: clears runtime only.

. ./common.sh

ID=""
ROOT=""
PATHARG="."
STATE=0
DESTROY_ZFS=0
DESTROY_BODY=0
YES=0

usage() {
  cat <<'EOF'
clean-scalefs.sh - cleanup scalefs runtime/state (and optionally destroy)

USAGE
  clean-scalefs.sh [-p PATH] [--state] [--yes]
  clean-scalefs.sh -i ID [-r ROOT] [--state] [--destroy-zfs] [--destroy-body] [--yes]

OPTIONS
  -p, --path PATH         Scalefs body path (default: .)
  -i, --id ID             Scalefs id (name.shortid)
  -r, --root NAME         Root alias (required if id is not unique)
      --state             Also clear scalefs.state/*
      --destroy-zfs        Destroy ZFS dataset if enabled in scalefs.ini
      --destroy-body       Remove body directory after cleanup (dangerous)
  -y, --yes               Do not prompt
  -h, --help              Show help

EXAMPLES
  # Clear runtime only (safe)
  ./clean-scalefs.sh -p /scalefsroot/democell.28e671

  # Clear runtime + state
  ./clean-scalefs.sh -i democell.28e671 -r test --state

  # Full wipe (dataset + dir)
  ./clean-scalefs.sh -i democell.28e671 -r test --destroy-zfs --destroy-body -y
EOF
}

die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path) PATHARG="$2"; shift 2;;
    -i|--id) ID="$2"; shift 2;;
    -r|--root) ROOT="$2"; shift 2;;
    --state) STATE=1; shift;;
    --destroy-zfs) DESTROY_ZFS=1; shift;;
    --destroy-body) DESTROY_BODY=1; shift;;
    -y|--yes) YES=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1";;
  esac
done

resolve_body_path() {
  if [ -n "$PATHARG" ] && [ "$PATHARG" != "." ]; then
    (cd "$PATHARG" 2>/dev/null && pwd) || die "not a directory: $PATHARG"
    return 0
  fi
  if [ "$PATHARG" = "." ] && [ -f "./scalefs.ini" ]; then
    pwd
    return 0
  fi

  [ -n "$ID" ] || die "require -p PATH or -i ID"
  if [ -n "$ROOT" ]; then
    p="$(load_roots | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
    [ -n "$p" ] || die "unknown root alias: $ROOT"
    d="$p/$ID"
    [ -d "$d" ] || die "not found: $d"
    (cd "$d" && pwd)
    return 0
  fi

  load_roots | while IFS='|' read -r alias path; do
    d="$path/$ID"
    [ -d "$d" ] && printf "%s\n" "$d"
  done >"/tmp/.zmesh_clean_cands.$$" 2>/dev/null || true

  count="$(wc -l < "/tmp/.zmesh_clean_cands.$$" | tr -d ' ')"
  if [ "$count" -ne 1 ]; then
    rm -f "/tmp/.zmesh_clean_cands.$$" || true
    die "could not resolve id=$ID uniquely (specify -r ROOT or -p PATH)"
  fi
  found="$(head -n 1 "/tmp/.zmesh_clean_cands.$$")"
  rm -f "/tmp/.zmesh_clean_cands.$$" || true
  (cd "$found" && pwd)
}

ini_get() {
  f="$1"; sec="$2"; key="$3"
  awk -v sec="[$sec]" -v key="$key" '
    BEGIN{in=0}
    $0==sec{in=1; next}
    in==1 && /^\[/{exit}
    in==1 {
      split($0,a,"=")
      k=a[1]
      sub(/^[ \t]+/,"",k); sub(/[ \t]+$/,"",k)
      if (k==key) {
        v=substr($0, index($0,"=")+1)
        sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v)
        print v
        exit
      }
    }
  ' "$f"
}

confirm() {
  [ "$YES" -eq 1 ] && return 0
  printf "%s [y/N]: " "$1"
  IFS= read -r ans || return 1
  case "$(printf %s "$ans" | tr '[:upper:]' '[:lower:]')" in
    y|yes) return 0;;
    *) return 1;;
  esac
}

DIR="$(resolve_body_path)"
INI="$DIR/scalefs.ini"
[ -f "$INI" ] || die "missing scalefs.ini: $INI"

zfs_enabled="$(ini_get "$INI" zfs enabled)"
zfs_dataset="$(ini_get "$INI" zfs dataset)"

printf "Target: %s\n" "$DIR"
printf "Plan:\n"
printf "  - clear runtime: %s\n" "$DIR/scalefs.runtime.d/*"
[ "$STATE" -eq 1 ] && printf "  - clear state:   %s\n" "$DIR/scalefs.state/*"
[ "$DESTROY_ZFS" -eq 1 ] && printf "  - destroy zfs dataset (if any): %s\n" "${zfs_dataset:-}"
[ "$DESTROY_BODY" -eq 1 ] && printf "  - remove body directory: %s\n" "$DIR"

confirm "Proceed?" || die "aborted"

# runtime
if [ -d "$DIR/scalefs.runtime.d" ]; then
  rm -rf "$DIR/scalefs.runtime.d/"* 2>/dev/null || true
fi

# state
if [ "$STATE" -eq 1 ] && [ -d "$DIR/scalefs.state" ]; then
  rm -rf "$DIR/scalefs.state/"* 2>/dev/null || true
fi

# zfs destroy
if [ "$DESTROY_ZFS" -eq 1 ] && [ "${zfs_enabled:-}" = "true" ] && [ -n "${zfs_dataset:-}" ] && detect_zfs; then
  zfs unmount -f "$zfs_dataset" >/dev/null 2>&1 || true
  zfs destroy -r "$zfs_dataset" >/dev/null 2>&1 || true
fi

# body destroy
if [ "$DESTROY_BODY" -eq 1 ]; then
  rm -rf "$DIR"
fi

echo "OK"