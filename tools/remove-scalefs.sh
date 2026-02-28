#!/bin/sh
set -eu
. ./common.sh

printf "Name (e.g. democell.17ded8): "
read NAME

removed_any=0

load_roots | while IFS='|' read alias path
do
  DIR="$path/$NAME"
  [ -d "$DIR" ] || continue

  # If marker exists and zfs is available, destroy dataset first.
  marker="$(scalefs_dataset_marker "$DIR")"
  if detect_zfs && [ -f "$marker" ]; then
    DS="$(sed -n '1p' "$marker" | tr -d '\r\n' || true)"
    if [ -n "$DS" ]; then
      # Best effort unmount (ignore errors), then destroy.
      zfs unmount "$DS" >/dev/null 2>&1 || true
      zfs destroy -r "$DS" >/dev/null 2>&1 || true
    fi
  fi

  # Now remove directory
  rm -rf "$DIR"
  echo "removed: $DIR"
  removed_any=1
done

# If nothing removed, exit non-zero for scripts
[ "$removed_any" -eq 1 ] || { echo "not found: $NAME" >&2; exit 1; }