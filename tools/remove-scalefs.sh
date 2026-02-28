#!/bin/sh
set -eu
. ./common.sh

NAME="${NAME:-}"     # name.shortid
YES="${YES:-0}"      # 1 => no prompt

usage() {
  cat <<EOF
Usage:
  remove-scalefs.sh --name <name.shortid> [--yes]
  remove-scalefs.sh            (interactive)

Env:
  NAME=<name.shortid>
  YES=1
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --name|-n) NAME="$2"; shift 2;;
    --yes|-y) YES=1; shift 1;;
    --help|-h) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 1;;
  esac
done

if [ -z "$NAME" ]; then
  printf "Name (name.shortid): "
  read NAME
fi

NAME="$(normalize_name "$NAME")"
[ -n "$NAME" ] || { echo "empty name" >&2; exit 1; }

# locate scalefs dir under any root
found=""
found_root=""
resolve_root_path | while IFS='|' read alias path; do
  [ -n "$path" ] || continue
  d="$path/$NAME"
  if [ -d "$d" ]; then
    echo "$alias|$d"
    exit 0
  fi
done > /tmp/.zmesh_rm_match.$$ 2>/dev/null || true

if [ -s /tmp/.zmesh_rm_match.$$ ]; then
  line="$(cat /tmp/.zmesh_rm_match.$$ | head -n 1)"
  found_root="$(echo "$line" | cut -d'|' -f1)"
  found="$(echo "$line" | cut -d'|' -f2-)"
fi
rm -f /tmp/.zmesh_rm_match.$$ 2>/dev/null || true

[ -n "$found" ] || { echo "not found: $NAME" >&2; exit 1; }

main="$found/main"

# detect dataset by mountpoint
ds="$(zfs_dataset_for_mountpoint "$main" 2>/dev/null || true)"

echo "Target:"
echo "  root=$found_root"
echo "  dir =$found"
[ -n "$ds" ] && echo "  zfs =$ds"

if [ "$YES" -ne 1 ]; then
  printf "Proceed? [y/N]: "
  read ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "cancelled"; exit 0;;
  esac
fi

# 1) destroy dataset if present
if [ -n "$ds" ]; then
  echo "zfs destroy -r $ds"
  # best effort unmount first (some platforms)
  zfs unmount -f "$ds" 2>/dev/null || true
  zfs destroy -r "$ds"
fi

# 2) best effort umount if still mounted
try_unmount_if_mounted "$main"

# 3) remove directory
rm -rf "$found"
echo "OK removed: $NAME"