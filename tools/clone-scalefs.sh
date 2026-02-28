#!/bin/sh
set -eu

SRC="$1"
DST="$2"

cp -a "$SRC" "$DST"

echo cloned