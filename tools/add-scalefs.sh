#!/bin/sh
set -eu

. ./common.sh

ROOT="${ROOT:-}"
NAME="${NAME:-}"
ZFS_POOL="${ZFS_POOL:-}"   # optional override
ZFS_TRY="${ZFS_TRY:-1}"    # 1=try zfs best-effort, 0=skip zfs

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

printf "Available roots:\n"
resolve_root_path || true

if [ -z "$ROOT" ]; then
  printf "Select root: "
  # read can return non-zero on EOF; don't hard-fail under set -e
  IFS= read -r ROOT || ROOT=""
fi

#PATHVAL="$(load_roots 2>/dev/null | awk -F'|' -v #r="$ROOT" '$1==r{print $2; exit}' || true)"
#[ -n "$PATHVAL" ] || die "unknown root alias: $ROOT"

PATHVAL="$(resolve_root_path "$ROOT" || true)"
[ -n "$PATHVAL" ] || die "unknown root alias or path: $ROOT"


if [ -z "$NAME" ]; then
  printf "Name: "
  IFS= read -r NAME || NAME=""
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
# IMPORTANT:
# - `set -e` can abort on permission errors inside pipelines.
# - So we must guard zfs commands with `|| true` BEFORE piping.
if [ "$ZFS_TRY" = "1" ] && detect_zfs; then
  POOL=""

  # 1) If PATHVAL is a dataset mountpoint, find its dataset name.
  #    Guard zfs list so permission/no-pool doesn't abort.
  POOL="$(
    (zfs list -H -o name,mountpoint 2>/dev/null || true) \
      | awk -v mp="$PATHVAL" '$2==mp{print $1; exit}'
  )" || true

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

    # ensure parents + dataset exist (best-effort)
    zfs create -p "$BASE" >/dev/null 2>&1 || true
    zfs create -p "$DS"   >/dev/null 2>&1 || true

    # set mountpoint to DIR/main and try mount
    zfs set mountpoint="$DIR/main" "$DS" >/dev/null 2>&1 || true
    zfs mount "$DS" >/dev/null 2>&1 || true

    # write zfs stanza
    tmp="$DIR/scalefs.ini.tmp"
    awk '
      BEGIN{inz=0}
      /^\[zfs\]/{inz=1; print; next}
      inz==1 && /^enabled=/{print "enabled=true"; next}
      inz==1 && /^pool=/{print "pool='"$POOL"'"; next}
      inz==1 && /^dataset=/{print "dataset='"$DS"'"; next}
      {print}
    ' "$DIR/scalefs.ini" > "$tmp"
    mv "$tmp" "$DIR/scalefs.ini"
  fi
fi

say "Created $FULL"
exit 0