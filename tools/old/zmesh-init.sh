#!/bin/sh
set -eu

CONFIG_DIR="${ZMESHDIR:-/usr/local/etc/zmesh}"

mkdir -p "$CONFIG_DIR/zmesh.d"

CONF="$CONFIG_DIR/zmesh.conf"

if [ ! -f "$CONF" ]; then

NODE="$(hostname | cut -d. -f1)"
SITE="$(hostname | cut -d. -f2-)"

cat > "$CONF" <<EOF
[node]
id=$NODE
site=${SITE:-default}

[include]
roots=$CONFIG_DIR/zmesh.d/*.conf
EOF

echo "Created $CONF"

fi

echo
echo "Add root example:"
echo
echo "[root \"fast\"]"
echo "path=/tank/scalefs"
echo
echo "Save as $CONFIG_DIR/zmesh.d/fast.conf"
echo