#!/bin/sh
set -eu

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# prefer repo root scalefs wrapper
if [ -x "$BASE_DIR/scalefs" ]; then
  exec "$BASE_DIR/scalefs" list "$@"
fi
if [ -x "$BASE_DIR/tools/scalefs" ]; then
  exec "$BASE_DIR/tools/scalefs" list "$@"
fi

echo "missing scalefs entry" >&2
exit 127