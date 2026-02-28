#!/bin/sh
set -e

. ./common.sh

ROOT="${ROOT-}"
NAME="${NAME-}"
ZFS_POOL="${ZFS_POOL-}"   # optional override

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

say "Available roots:"
load_roots

if [ -z "$ROOT" ]; then
  printf "Select root: "
  IFS= read -r ROOT || die "failed to read root"
fi

PATHVAL="$(load_roots | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
[ -n "$PATHVAL" ] || die "unknown root alias: $ROOT"

if [ -z "$NAME" ]; then
  printf "Name: "
  IFS= read -r NAME || die "failed to read name"
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

  # 1) PATHVAL が dataset の mountpoint なら、その pool 名を引く
  #    (zfs list -o name,mountpoint) の mountpoint が PATHVAL と一致する行を探す
  ds_at_mp="$(zfs list -H -o name,mountpoint 2>/dev/null | awk -v mp="$PATHVAL" '$2==mp{print $1; exit}')"
  if [ -n "${ds_at_mp:-}" ]; then
    POOL="$(printf "%s" "$ds_at_mp" | cut -d'/' -f1)"
  fi

  # 2) override
  if [ -z "$POOL" ] && [ -n "$ZFS_POOL" ]; then
    POOL="$ZFS_POOL"
  fi

  if [ -n "$POOL" ]; then
    BASE="$POOL/scalefs"
    DS="$BASE/$NAME-$ID"

    # ensure parents + dataset exist
    zfs create -p "$BASE" >/dev/null 2>&1 || true
    zfs create -p "$DS"   >/dev/null 2>&1 || true

    # set mountpoint
    zfs set mountpoint="$DIR/main" "$DS" >/dev/null 2>&1 || true
    zfs mount "$DS" >/dev/null 2>&1 || true

    # patch scalefs.ini [zfs] section
    tmp="$DIR/scalefs.ini.tmp"
    awk -v pool="$POOL" -v ds="$DS" '
      BEGIN{inz=0}
      /^\[zfs\]/{inz=1; print; next}
      inz==1 && /^enabled=/{print "enabled=true"; next}
      inz==1 && /^pool=/{print "pool=" pool; next}
      inz==1 && /^dataset=/{print "dataset=" ds; next}
      {print}
    ' "$DIR/scalefs.ini" > "$tmp"
    mv "$tmp" "$DIR/scalefs.ini"
  fi
fi

say "Created $FULL"