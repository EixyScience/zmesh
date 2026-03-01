#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

mkdir -p "$ZCONF_DIR/zmesh.d"
mkdir -p "$ZCONF_DIR/virtualpath.d"

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
