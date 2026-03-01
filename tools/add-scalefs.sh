#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

ROOT="${ROOT:-}"
NAME="${NAME:-}"
ZFS_POOL="${ZFS_POOL:-}"   # optional override

printf "Available roots:\n"
load_roots

if [ -z "$ROOT" ]; then
  printf "Select root: "
  IFS= read -r ROOT
fi

PATHVAL="$(load_roots | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
[ -n "$PATHVAL" ] || die "unknown root alias: $ROOT"

if [ -z "$NAME" ]; then
  printf "Name: "
  IFS= read -r NAME
fi

NAME="$(normalize_name "$NAME")"
[ -n "$NAME" ] || die "invalid name"

SID="$(gen_shortid)"
FULL="$NAME.$SID"
DIR="$PATHVAL/$FULL"

mkdir -p "$DIR/main" \
         "$DIR/scalefs.state" \
         "$DIR/scalefs.global.d" \
         "$DIR/scalefs.local.d" \
         "$DIR/scalefs.runtime.d"

cat > "$DIR/scalefs.ini" <<EOF
[scalefs]
id=$FULL
name=$NAME
shortid=$SID

[paths]
state_dir=./scalefs.state
watch_root=./main

[zfs]
enabled=false
pool=
dataset=
EOF

# ---- ZFS best-effort ----
if detect_zfs; then
  POOL=""

  # If PATHVAL is a dataset mountpoint, find dataset name then take pool part
  ds_at_root="$(zfs list -H -o name,mountpoint 2>/dev/null | awk -v mp="$PATHVAL" '$2==mp{print $1; exit}' || true)"
  if [ -n "$ds_at_root" ]; then
    POOL="$(printf "%s" "$ds_at_root" | cut -d'/' -f1)"
  fi

  # override
  if [ -z "$POOL" ] && [ -n "$ZFS_POOL" ]; then
    POOL="$ZFS_POOL"
  fi

  if [ -n "$POOL" ]; then
    BASE="$POOL/scalefs"
    DS="$BASE/$NAME-$SID"

    # parents + dataset
    zfs create -p "$BASE" >/dev/null 2>&1 || true
    zfs create -p "$DS"   >/dev/null 2>&1 || true

    # mountpoint to body/main
    zfs set mountpoint="$DIR/main" "$DS" >/dev/null 2>&1 || true
    zfs mount "$DS" >/dev/null 2>&1 || true

    # update ini
    tmp="$DIR/scalefs.ini.tmp"
    awk -v POOL="$POOL" -v DS="$DS" '
      BEGIN{in=0}
      /^\[zfs\]/{in=1; print; next}
      in==1 && /^enabled=/{print "enabled=true"; next}
      in==1 && /^pool=/{print "pool=" POOL; next}
      in==1 && /^dataset=/{print "dataset=" DS; next}
      {print}
    ' "$DIR/scalefs.ini" > "$tmp"
    mv "$tmp" "$DIR/scalefs.ini"
  fi
fi

say "Created $FULL"