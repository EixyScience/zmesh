#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

ID="${ID:-}"
YES="${YES:-0}"

usage() {
  cat <<'EOF'
remove-scalefs.sh - remove scalefs body safely (best-effort)

USAGE
  sh remove-scalefs.sh [-i ID] [-y]

OPTIONS
  -i, --id ID     Scalefs id (name.shortid)
  -y, --yes       Do not prompt

EXAMPLES
  sh tools/remove-scalefs.sh -i democell.28e671
  sh tools/remove-scalefs.sh -i democell.28e671 -y
EOF
}

# args
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -i|--id) ID="${2:-}"; shift 2;;
    -y|--yes) YES=1; shift;;
    *) die "unknown arg: $1";;
  esac
done

if [ -z "$ID" ]; then
  printf "ID (name.shortid): "
  IFS= read -r ID
fi

ID="$(normalize_name "$ID")"
[ -n "$ID" ] || die "empty id"

# locate body dir across roots
TARGET=""
load_roots | while IFS='|' read -r alias path; do
  d="$path/$ID"
  if [ -d "$d" ] && [ -z "$TARGET" ]; then
    echo "$d"
    break
  fi
done >"/tmp/zmesh.rm.$$" 2>/dev/null || true

if [ -f "/tmp/zmesh.rm.$$" ]; then
  TARGET="$(cat "/tmp/zmesh.rm.$$" 2>/dev/null || true)"
  rm -f "/tmp/zmesh.rm.$$" >/dev/null 2>&1 || true
fi

[ -n "$TARGET" ] || die "not found: $ID (searched all roots)"

say "Target: $TARGET"

if [ "$YES" -ne 1 ]; then
  printf "Proceed? (y/N): "
  IFS= read -r ans
  case "$(printf "%s" "$ans" | tr '[:upper:]' '[:lower:]')" in
    y|yes) ;;
    *) say "cancelled"; exit 0;;
  esac
fi

MAIN="$TARGET/main"

# try zfs destroy if mounted dataset corresponds to MAIN mountpoint
if detect_zfs; then
  ds="$(zfs list -H -o name,mountpoint 2>/dev/null | awk -v mp="$MAIN" '$2==mp{print $1; exit}' || true)"
  if [ -n "$ds" ]; then
    say "zfs: found dataset for main: $ds"
    zfs unmount -f "$ds" >/dev/null 2>&1 || true
    zfs destroy -r "$ds" >/dev/null 2>&1 || true
  fi
fi

rm -rf "$TARGET"
say "OK removed: $ID"