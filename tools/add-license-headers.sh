#!/bin/sh
set -eu

# add-license-headers.sh
# Adds Apache-2.0 style headers to:
#   - *.go
#   - *.ps1
#   - *.sh (shebang preserved)
#
# Safe defaults:
#   - skips .git/, tools/old/, vendor/
#   - skips files already containing "Licensed under the Apache License"
#   - dry-run by default. Use --apply to modify.

APPLY=0
ROOT="."
YEAR="${YEAR:-2026}"
NAME1="${NAME1:-Satoshi Takashima}"
NAME2="${NAME2:-EixyScience, Inc.}"

TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TOOLS_DIR/common.sh"


usage() {
  cat <<EOF
Usage: $0 [--apply] [--root DIR]

Environment:
  YEAR=2026
  NAME1="Satoshi Takashima"
  NAME2="EixyScience, Inc."

Examples:
  # Dry run
  sh tools/add-license-headers.sh

  # Apply
  sh tools/add-license-headers.sh --apply

  # Apply with different names
  YEAR=2026 NAME1="..." NAME2="..." sh tools/add-license-headers.sh --apply
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --root) ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

has_apache_marker() {
  # $1 file
  grep -qi "Licensed under the Apache License" "$1" 2>/dev/null
}

add_go_header() {
  f="$1"
  has_apache_marker "$f" && return 0

  hdr="$(cat <<EOF
// Copyright $YEAR $NAME1
// Copyright $YEAR $NAME2
//
// Licensed under the Apache License, Version 2.0
// http://www.apache.org/licenses/LICENSE-2.0

EOF
)"
  if [ "$APPLY" -eq 0 ]; then
    say "DRY  go  $f"
    return 0
  fi

  tmp="$f.tmp.$$"
  # Preserve possible build tags by inserting after them:
  # Go build tags may be in first comment block and must be first line(s).
  # We'll detect lines starting with //go:build or +build and keep them at top.
  awk -v HDR="$hdr" '
    BEGIN{inserted=0}
    NR==1{
      # if first line is //go:build or // +build (legacy), keep scanning build tags
    }
    {
      lines[NR]=$0
      if ($0 ~ /^\/\/go:build / || $0 ~ /^\/\/ \+build / || $0 ~ /^\/\/\+build /) {
        buildtags[NR]=1
      }
    }
    END{
      # find last build tag line at file top
      last=0
      for(i=1;i<=NR;i++){
        if (i==1 && buildtags[i]==1) { last=i; continue }
        if (last>0 && buildtags[i]==1 && i==last+1) { last=i; continue }
        # stop when first non-buildtag encountered after contiguous build tags
        if (last>0 && i>last) break
      }
      if (last>0) {
        for(i=1;i<=last;i++) print lines[i]
        print ""  # blank line after build tags
        printf "%s", HDR
        for(i=last+1;i<=NR;i++) print lines[i]
      } else {
        printf "%s", HDR
        for(i=1;i<=NR;i++) print lines[i]
      }
    }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
  say "APPL go  $f"
}

add_ps1_header() {
  f="$1"
  has_apache_marker "$f" && return 0

  hdr="$(cat <<EOF
# Copyright $YEAR $NAME1
# Copyright $YEAR $NAME2
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0

EOF
)"
  if [ "$APPLY" -eq 0 ]; then
    say "DRY  ps1 $f"
    return 0
  fi

  tmp="$f.tmp.$$"
  # PS1: if file starts with BOM or "param(" or "#requires", header must be first non-BOM line.
  # We'll just prepend; PS tolerates comment header before param().
  { printf "%s" "$hdr"; cat "$f"; } > "$tmp" && mv "$tmp" "$f"
  say "APPL ps1 $f"
}

add_sh_header() {
  f="$1"
  has_apache_marker "$f" && return 0

  hdr="$(cat <<EOF
# Copyright $YEAR $NAME1
# Copyright $YEAR $NAME2
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0

EOF
)"
  if [ "$APPLY" -eq 0 ]; then
    say "DRY  sh  $f"
    return 0
  fi

  tmp="$f.tmp.$$"
  first="$(head -n 1 "$f" || true)"
  if printf "%s" "$first" | grep -q '^#!'; then
    # preserve shebang as first line
    { printf "%s\n" "$first"; printf "%s" "$hdr"; tail -n +2 "$f"; } > "$tmp" && mv "$tmp" "$f"
  else
    { printf "%s" "$hdr"; cat "$f"; } > "$tmp" && mv "$tmp" "$f"
  fi
  say "APPL sh  $f"
}

# Collect files. Keep it portable (BSD find compatible).
# Skip: .git, tools/old, vendor
find "$ROOT" \
  \( -path "*/.git/*" -o -path "*/tools/old/*" -o -path "*/vendor/*" \) -prune -o \
  -type f \( -name "*.go" -o -name "*.ps1" -o -name "*.sh" \) -print | \
while IFS= read -r f; do
  case "$f" in
    *.go) add_go_header "$f" ;;
    *.ps1) add_ps1_header "$f" ;;
    *.sh) add_sh_header "$f" ;;
  esac
done

say "DONE"
say "Mode: $([ "$APPLY" -eq 1 ] && echo APPLY || echo DRY-RUN)"