#!/bin/sh
set -eu

. ./common.sh

ROOT=""
NAME=""

printf "Available roots:\n"
load_roots

printf "Select root: "
read ROOT

PATHVAL=$(load_roots | grep "^$ROOT|" | cut -d'|' -f2)

printf "Name: "
read NAME

NAME=$(normalize_name "$NAME")
ID=$(gen_shortid)

DIR="$PATHVAL/$NAME.$ID"

mkdir -p "$DIR/main"
mkdir -p "$DIR/scalefs.state"
mkdir -p "$DIR/scalefs.global.d"
mkdir -p "$DIR/scalefs.local.d"
mkdir -p "$DIR/scalefs.runtime.d"

cat > "$DIR/scalefs.ini" <<EOF
id=$NAME.$ID
EOF

# If zfs is available AND PATHVAL is under some zfs mountpoint,
# create a child dataset and mount it at DIR/main.
if detect_zfs; then
  PARENT_DS="$(zfs_dataset_for_path "$PATHVAL" || true)"
  if [ -n "$PARENT_DS" ]; then
    DS="$PARENT_DS/$NAME.$ID"

    # create dataset (idempotent-ish)
    if zfs create "$DS" 2>/dev/null; then
      :
    else
      # If already exists, continue; otherwise fail hard.
      zfs list -H -o name "$DS" >/dev/null 2>&1 || true
    fi

    # Ensure mountpoint set (zfs will mount automatically if canmount=on)
    zfs set mountpoint="$DIR/main" "$DS"

    # record marker for reliable removal
    marker="$(scalefs_dataset_marker "$DIR")"
    printf "%s\n" "$DS" > "$marker"
  fi
fi

echo "Created $NAME.$ID"