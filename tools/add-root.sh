#!/bin/sh
set -eu

. ./common.sh

ALIAS=""
PATHVAL=""

printf "Root alias: "
read ALIAS

printf "Path: "
read PATHVAL

mkdir -p "$PATHVAL"

CONF="$ZCONF_DIR/zmesh.d/$ALIAS.conf"

cat > "$CONF" <<EOF
[root "$ALIAS"]
path=$PATHVAL
EOF

echo "Created root $ALIAS"