#!/bin/sh
set -eu
. ./common.sh

VP="${VP:-}"
SCALEFS="${SCALEFS:-}"
SUBPATH="${SUBPATH:-/}"
MODE="${MODE:-link}"
READONLY="${READONLY:-false}"

say(){ printf "%s\n" "$*"; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

mkdir -p "$ZCONF_DIR/virtualpath.d"

if [ -z "$VP" ]; then
  printf "Virtual path (e.g. hobby/car): "
  read VP
fi
VP="$(echo "$VP" | sed 's#^/##' | sed 's#//*#/#g' | sed 's#/$##')"
[ -n "$VP" ] || die "virtual path required"

if [ -z "$SCALEFS" ]; then
  printf "Scalefs id (e.g. democell.28e671): "
  read SCALEFS
fi
SCALEFS="$(normalize_name "$SCALEFS")"
[ -n "$SCALEFS" ] || die "scalefs id required"

# filename
base="$(vp_to_filename "$VP")"
f="$ZCONF_DIR/virtualpath.d/vp.$base.conf"

cat > "$f" <<EOF
[virtualpath]
path=$VP
scalefs=$SCALEFS
subpath=$SUBPATH
mode=$MODE
readonly=$READONLY
EOF

say "OK virtualpath added: $VP -> $SCALEFS ($SUBPATH)"
say "  file: $f"