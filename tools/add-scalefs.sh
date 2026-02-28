#!/bin/sh
set -eu

. ./common.sh

ROOT="${ROOT:-}"
NAME="${NAME:-}"
ZFS_POOL="${ZFS_POOL:-}"   # optional override

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

printf "Available roots:\n"
load_roots

if [ -z "$ROOT" ]; then
  printf "Select root: "
  read ROOT
fi

PATHVAL="$(load_roots | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
[ -n "$PATHVAL" ] || die "unknown root alias: $ROOT"

if [ -z "$NAME" ]; then
  printf "Name: "
  read NAME
fi

NAME="$(normalize_name "$NAME")"
[ -n "$NAME" ] || die "invalid name"

ID="$(gen_shortid)"
SID="$ID"
FULL="$NAME.$ID"

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

# ---- ZFS path (best effort) ----
if detect_zfs; then
  POOL=""

  # 1) If PATHVAL is a dataset mountpoint, find its dataset name
  #    Works on FreeBSD/Linux with zfs get -H -o value -s local,received mountpoint
  POOL="$(zfs list -H -o name,mountpoint 2>/dev/null | awk -v mp="$PATHVAL" '$2==mp{print $1; exit}' || true)"

  # If found dataset at PATHVAL, pool is its top-level pool (first component)
  if [ -n "$POOL" ]; then
    POOL="$(printf "%s" "$POOL" | cut -d'/' -f1)"
  fi

  # 2) If still empty, use override env
  if [ -z "$POOL" ] && [ -n "$ZFS_POOL" ]; then
    POOL="$ZFS_POOL"
  fi

  if [ -n "$POOL" ]; then
    BASE="$POOL/scalefs"
    DS="$BASE/$NAME-$ID"

    # ensure parents + dataset exist
    zfs create -p "$BASE" >/dev/null 2>&1 || true
    zfs create -p "$DS"   >/dev/null 2>&1 || true

    # set mountpoint to DIR/main
    zfs set mountpoint="$DIR/main" "$DS" >/dev/null 2>&1 || true
    zfs mount "$DS" >/dev/null 2>&1 || true

    # write zfs stanza
    tmp="$DIR/scalefs.ini.tmp"
    awk '
      BEGIN{in=0}
      /^\[zfs\]/{in=1; print; next}
      in==1 && /^enabled=/{print "enabled=true"; next}
      in==1 && /^pool=/{print "pool='"$POOL"'"; next}
      in==1 && /^dataset=/{print "dataset='"$DS"'"; next}
      {print}
    ' "$DIR/scalefs.ini" > "$tmp"
    mv "$tmp" "$DIR/scalefs.ini"
  fi
fi

say "Created $FULL"