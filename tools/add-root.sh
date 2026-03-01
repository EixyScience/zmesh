#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TOOLS_DIR/common.sh"

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
