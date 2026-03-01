#!/bin/sh
set -eu

# clean-scalefs.sh
# - Clean runtime (default)
# - Optionally clean state
# - Optionally destroy zfs dataset (explicit)
# - Optionally remove entire body dir (explicit)

DIR="."
YES=0
DO_STATE=0
DO_DESTROY_ZFS=0
DO_DESTROY_BODY=0

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
clean-scalefs.sh - cleanup a scalefs body

USAGE
  clean-scalefs.sh [-p PATH] [-y] [--state] [--destroy-zfs] [--destroy-body] [-h]

DEFAULT BEHAVIOR
  - Removes scalefs.runtime.d/* only (safe).

OPTIONS
  -p, --path PATH        Path inside scalefs body (dir or file). Default: .
  -y, --yes              No confirmation
  --state                Also clear scalefs.state/*
  --destroy-zfs           Destroy ZFS dataset recorded in scalefs.ini (DANGEROUS)
  --destroy-body          Remove the whole body directory after cleanup (DANGEROUS)
  -h, --help             Show help

EXAMPLES
  # Safe: clear runtime only
  sh tools/clean-scalefs.sh -p /scalefsroot/democell.28e671 -y

  # Also clear state
  sh tools/clean-scalefs.sh -p . --state -y

  # Nuke everything (explicit)
  sh tools/clean-scalefs.sh -p /scalefsroot/democell.28e671 --destroy-zfs --destroy-body -y
EOF
}

# --- arg parse ---
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path) DIR="${2:-}"; shift 2 ;;
    -y|--yes) YES=1; shift ;;
    --state) DO_STATE=1; shift ;;
    --destroy-zfs) DO_DESTROY_ZFS=1; shift ;;
    --destroy-body) DO_DESTROY_BODY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1 (use -h)";;
  esac
done

resolve_body_dir() {
  p="$1"
  [ -n "$p" ] || p="."
  if [ -f "$p" ]; then
    d=$(CDPATH= cd -- "$(dirname -- "$p")" && pwd)
  else
    d=$(CDPATH= cd -- "$p" 2>/dev/null && pwd) || return 1
  fi
  cur="$d"
  while :; do
    [ -f "$cur/scalefs.ini" ] && { printf "%s\n" "$cur"; return 0; }
    parent=$(dirname -- "$cur")
    [ "$parent" = "$cur" ] && break
    cur="$parent"
  done
  return 1
}

BODY_DIR="$(resolve_body_dir "$DIR" || true)"
[ -n "$BODY_DIR" ] || die "missing scalefs.ini near: $DIR
HINT: run inside a scalefs body dir (contains scalefs.ini)."

INI="$BODY_DIR/scalefs.ini"

ini_get() {
  section="$1"
  key="$2"
  awk -v sec="[$section]" -v key="$key" '
    BEGIN{in=0}
    $0 ~ "^[[:space:]]*\\[" { in = ($0==sec) ? 1 : 0 }
    in==1 {
      sub(/\r$/, "", $0)
      if ($0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
        sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", $0)
        print $0
        exit
      }
    }
  ' "$INI"
}

zfs_enabled="$(ini_get zfs enabled)"
zfs_dataset="$(ini_get zfs dataset)"

say "Target: $BODY_DIR"
say "Plan:"
say "  - clear runtime: $BODY_DIR/scalefs.runtime.d/*"
[ "$DO_STATE" -eq 1 ] && say "  - clear state:   $BODY_DIR/scalefs.state/*"
[ "$DO_DESTROY_ZFS" -eq 1 ] && say "  - destroy zfs dataset: $zfs_dataset"
[ "$DO_DESTROY_BODY" -eq 1 ] && say "  - remove body dir: $BODY_DIR"

if [ "$YES" -ne 1 ]; then
  printf "Proceed? [y/N] "
  read ans || true
  case "$(printf "%s" "${ans:-}" | tr '[:upper:]' '[:lower:]')" in
    y|yes) :;;
    *) die "aborted";;
  esac
fi

# runtime cleanup
if [ -d "$BODY_DIR/scalefs.runtime.d" ]; then
  rm -rf "$BODY_DIR/scalefs.runtime.d/"* 2>/dev/null || true
fi

# state cleanup
if [ "$DO_STATE" -eq 1 ] && [ -d "$BODY_DIR/scalefs.state" ]; then
  rm -rf "$BODY_DIR/scalefs.state/"* 2>/dev/null || true
fi

# zfs destroy (explicit only)
if [ "$DO_DESTROY_ZFS" -eq 1 ]; then
  if command -v zfs >/dev/null 2>&1 && [ "$zfs_enabled" = "true" ] && [ -n "$zfs_dataset" ]; then
    # best-effort unmount + destroy
    zfs unmount -f "$zfs_dataset" >/dev/null 2>&1 || true
    zfs destroy -r "$zfs_dataset" || true
  else
    say "WARN: zfs destroy skipped (zfs missing or zfs.enabled!=true or dataset empty)"
  fi
fi

# remove body dir (explicit only)
if [ "$DO_DESTROY_BODY" -eq 1 ]; then
  rm -rf "$BODY_DIR" || true
fi

say "OK"