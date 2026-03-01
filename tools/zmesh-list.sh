#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TOOLS_DIR/common.sh"

# prefer repo root scalefs wrapper
if [ -x "$BASE_DIR/scalefs" ]; then
  exec "$BASE_DIR/scalefs" list "$@"
fi
if [ -x "$BASE_DIR/tools/scalefs" ]; then
  exec "$BASE_DIR/tools/scalefs" list "$@"
fi

echo "missing scalefs entry" >&2
exit 127