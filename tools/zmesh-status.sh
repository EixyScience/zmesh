#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

# tools/zmesh-status.sh
# quick status (no destructive ops)

say(){ printf "%s\n" "$*"; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TOOLS_DIR/common.sh"


# config dir used by common.sh
ZCONF_DIR="${ZCONF_DIR:-/usr/local/etc/zmesh}"
# if not exists, prefer ~/.zmesh
if [ ! -d "$ZCONF_DIR" ] && [ -d "$HOME/.zmesh" ]; then
  ZCONF_DIR="$HOME/.zmesh"
fi
export ZCONF_DIR

if [ -f "$TOOLS_DIR/common.sh" ]; then
  . "$TOOLS_DIR/common.sh"
else
  die "missing common.sh"
fi

say "zmesh status"
say "  repo:   $BASE_DIR"
say "  zconf:  $ZCONF_DIR"

# zmesh.conf presence (optional)
if [ -f "$BASE_DIR/zmesh.conf" ]; then
  say "  conf:   $BASE_DIR/zmesh.conf"
elif [ -f "$ZCONF_DIR/zmesh.conf" ]; then
  say "  conf:   $ZCONF_DIR/zmesh.conf"
else
  say "  conf:   (not found)"
fi

# tool availability
if command -v zfs >/dev/null 2>&1; then
  say "  zfs:    yes ($(zfs version 2>/dev/null | head -n 1 || true))"
else
  say "  zfs:    no"
fi

# roots
roots="$(load_roots || true)"
cnt_roots=$(printf "%s\n" "$roots" | awk 'NF{c++} END{print c+0}')
say "  roots:  $cnt_roots"
if [ "$cnt_roots" -gt 0 ]; then
  printf "%s\n" "$roots" | awk -F'|' '{printf "    - %s -> %s\n",$1,$2}'
fi

# scalefs count (cheap scan)
cnt_bodies=0
if [ "$cnt_roots" -gt 0 ]; then
  while IFS='|' read a p; do
    [ -d "$p" ] || continue
    n=$(find "$p" -maxdepth 1 -type d 2>/dev/null | while read d; do [ -f "$d/scalefs.ini" ] && echo x; done | wc -l | tr -d ' ')
    cnt_bodies=$((cnt_bodies + n))
  done <<EOF
$roots
EOF
fi
say "  scalefs: $cnt_bodies (dirs containing scalefs.ini)"

# agent process (best-effort)
if command -v pgrep >/dev/null 2>&1; then
  if pgrep -f "cmd/zmesh.*agent" >/dev/null 2>&1; then
    say "  agent:  running"
  else
    say "  agent:  not found"
  fi
else
  say "  agent:  (pgrep not available)"
fi