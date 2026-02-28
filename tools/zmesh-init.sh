#!/bin/sh
set -eu

. ./common.sh

mkdir -p "$ZCONF_DIR/zmesh.d"

CONF="$ZCONF_DIR/zmesh.conf"

if [ -f "$CONF" ]; then
echo "Already exists: $CONF"
exit 0
fi

HOST="$(hostname)"
NODE="$(echo "$HOST" | cut -d. -f1)"
SITE="$(echo "$HOST" | cut -d. -f2-)"

printf "Node name [$NODE]: "
read IN
[ -n "$IN" ] && NODE="$IN"

printf "Site name [$SITE]: "
read IN
[ -n "$IN" ] && SITE="$IN"

cat > "$CONF" <<EOF
[node]
id=$NODE
site=$SITE

[include]
roots=$ZCONF_DIR/zmesh.d/*.conf
EOF

echo "Created $CONF"