#!/bin/sh
set -eu
. ./common.sh

VP="${VP:-}"

say(){ printf "%s\n" "$*"; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

if [ -z "$VP" ]; then
  printf "Virtual path (e.g. hobby/car): "
  read VP
fi
VP="$(echo "$VP" | sed 's#^/##' | sed 's#//*#/#g' | sed 's#/$##')"
[ -n "$VP" ] || die "virtual path required"

base="$(vp_to_filename "$VP")"
f="$ZCONF_DIR/virtualpath.d/vp.$base.conf"

if [ -f "$f" ]; then
  rm -f "$f"
  say "OK removed: $VP"
else
  say "not found: $VP"
fi