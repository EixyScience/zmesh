#!/bin/sh
set -eu

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
cat <<'EOF'
clean-scalefs.sh - cleanup runtime/state and optionally destroy zfs/body

USAGE
  sh tools/clean-scalefs.sh [options]

OPTIONS
  -p, --path PATH         Path inside a scalefs body (body dir OR any subdir)
  --state                 Also clear scalefs.state/*
  --destroy-zfs            Destroy zfs dataset (if enabled in scalefs.ini)
  --destroy-body           Remove the body directory itself
  -y, --yes               No prompt
  -h, --help              Show help

EXAMPLES
  # Clean runtime only (safe):
  sh tools/clean-scalefs.sh -p /path/to/democell.28e671 -y

  # Also clear state:
  sh tools/clean-scalefs.sh -p /path/to/democell.28e671 --state -y

  # Nuke (danger):
  sh tools/clean-scalefs.sh -p /path/to/democell.28e671 --destroy-zfs --destroy-body -y
EOF
}

PATH_IN="."
DO_STATE=0
DO_ZFS=0
DO_BODY=0
YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path) PATH_IN="${2:-}"; shift 2;;
    --state) DO_STATE=1; shift;;
    --destroy-zfs) DO_ZFS=1; shift;;
    --destroy-body) DO_BODY=1; shift;;
    -y|--yes) YES=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1 (use -h)";;
  esac
done

if [ "$PATH_IN" = "." ]; then CUR="$(pwd)"; else CUR="$PATH_IN"; fi

find_body_dir() {
  d="$1"
  if command -v realpath >/dev/null 2>&1; then
    d="$(realpath "$d" 2>/dev/null || printf "%s" "$d")"
  fi
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -f "$d/scalefs.ini" ]; then
      printf "%s\n" "$d"; return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}

BODY="$(find_body_dir "$CUR" || true)"
[ -n "$BODY" ] || die "missing scalefs.ini near: $CUR
HINT: run inside a scalefs body dir (contains scalefs.ini)."

INI="$BODY/scalefs.ini"

ini_get() {
  sec="$1"; key="$2"
  awk -v sec="[$sec]" -v key="$key" '
    BEGIN{in=0}
    $0 ~ /^[[:space:]]*\[/ { in=0 }
    $0 ~ "^[[:space:]]*"sec"[[:space:]]*$" { in=1; next }
    in==1 {
      sub(/[;#].*$/,"")
      if ($0 ~ "^[[:space:]]*"key"[[:space:]]*=") {
        sub("^[[:space:]]*"key"[[:space:]]*=","")
        gsub(/^[[:space:]]+|[[:space:]]+$/,"")
        print; exit
      }
    }
  ' "$INI"
}

ZFS_EN="$(ini_get zfs enabled)"
ZFS_DS="$(ini_get zfs dataset)"

say "Target: $BODY"
say "Plan:"
say "  - clear runtime: scalefs.runtime.d/*"
[ "$DO_STATE" -eq 1 ] && say "  - clear state:   scalefs.state/*"
[ "$DO_ZFS" -eq 1 ] && say "  - destroy zfs dataset (if enabled): $ZFS_DS"
[ "$DO_BODY" -eq 1 ] && say "  - remove body dir: $BODY"

if [ "$YES" -ne 1 ]; then
  printf "Proceed? (y/N): "
  read ans
  case "$(printf "%s" "$ans" | tr '[:upper:]' '[:lower:]')" in
    y|yes) ;;
    *) die "aborted";;
  esac
fi

# runtime cleanup
if [ -d "$BODY/scalefs.runtime.d" ]; then
  rm -rf "$BODY/scalefs.runtime.d/"* 2>/dev/null || true
fi

# state cleanup
if [ "$DO_STATE" -eq 1 ] && [ -d "$BODY/scalefs.state" ]; then
  rm -rf "$BODY/scalefs.state/"* 2>/dev/null || true
fi

# zfs destroy (best effort)
if [ "$DO_ZFS" -eq 1 ]; then
  if command -v zfs >/dev/null 2>&1 && [ "$ZFS_EN" = "true" ] && [ -n "$ZFS_DS" ]; then
    zfs unmount -f "$ZFS_DS" >/dev/null 2>&1 || true
    zfs destroy -r "$ZFS_DS" >/dev/null 2>&1 || true
  fi
fi

# remove body dir
if [ "$DO_BODY" -eq 1 ]; then
  rm -rf "$BODY"
fi

say "OK"