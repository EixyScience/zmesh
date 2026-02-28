#!/bin/sh
set -eu
. ./common.sh

say(){ printf "%s\n" "$*"; }
warn(){ printf "WARN: %s\n" "$*" >&2; }

d="$ZCONF_DIR/virtualpath.d"
[ -d "$d" ] || { say "OK: no virtualpath.d"; exit 0; }

dup="$(load_virtualpaths | awk -F'|' '{c[$1]++} END{for(k in c) if(c[k]>1) print k}')"
if [ -n "$dup" ]; then
  warn "duplicate vpath entries:"
  echo "$dup" | sed 's/^/  - /'
fi

# very lightweight: scalefs field looks like name.shortid
bad="$(load_virtualpaths | awk -F'|' '$2 !~ /^[a-z0-9._-]+\.[0-9a-f]{6,8}$/ {print $0}')"
if [ -n "$bad" ]; then
  warn "suspicious scalefs ids:"
  echo "$bad" | sed 's/^/  - /'
fi

say "OK: virtualpath.d checked"