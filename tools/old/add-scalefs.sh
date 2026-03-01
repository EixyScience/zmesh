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

if detect_zfs; then

POOL=$(zfs list -H -o name "$PATHVAL" 2>/dev/null || true)

if [ -n "$POOL" ]; then

zfs create "$POOL/$NAME.$ID" || true

zfs set mountpoint="$DIR/main" "$POOL/$NAME.$ID"

fi

fi

echo "Created $NAME.$ID"