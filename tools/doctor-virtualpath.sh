#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

# Doctor for virtualpath config:
# - validates parseability
# - optionally checks target existence
# - shows summary counts

ZCONF_DIR="${ZCONF_DIR:-/usr/local/etc/zmesh}"
CONF_DIR="$ZCONF_DIR/virtualpath.d"

TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TOOLS_DIR/common.sh"

say(){ printf "%s\n" "$*"; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
cat <<'EOF'
doctor-virtualpath.sh - validate virtualpath configuration

USAGE
  doctor-virtualpath.sh [--check-targets] [--strict] [--file NAME.conf]

OPTIONS
  --check-targets     Check that each target path exists
  --strict            Fail if any problem is found (otherwise best-effort + warnings)
  -f, --file NAME     Only validate a specific file
  -h, --help          Show help

ENV
  ZCONF_DIR           Config directory (default: /usr/local/etc/zmesh)

EXAMPLES
  ZCONF_DIR=/usr/local/etc/zmesh ./tools/doctor-virtualpath.sh
  ZCONF_DIR=/usr/local/etc/zmesh ./tools/doctor-virtualpath.sh --check-targets --strict
EOF
}

CHECK=0
STRICT=0
FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --check-targets) CHECK=1; shift 1;;
    --strict) STRICT=1; shift 1;;
    -f|--file) FILE="${2:-}"; shift 2;;
    --file=*) FILE="${1#*=}"; shift 1;;
    *) die "unknown arg: $1 (use --help)";;
  esac
done

[ -d "$CONF_DIR" ] || die "missing config dir: $CONF_DIR"

files=""
if [ -n "$FILE" ]; then
  p="$CONF_DIR/$FILE"
  [ -f "$p" ] || die "missing file: $p"
  files="$p"
else
  # shellcheck disable=SC2086
  files=$(ls -1 "$CONF_DIR"/*.conf 2>/dev/null || true)
fi

[ -n "$files" ] || { say "(no virtualpath rules)"; exit 0; }

warn=0
err=0
count=0

say "[doctor] conf=$CONF_DIR check_targets=$CHECK strict=$STRICT"

for f in $files; do
  say "== $f =="

  # parse and detect issues: missing target, duplicate sections (not fatal), empty vpath
  awk '
  function trim(s){ gsub(/^[ \t\r\n]+/,"",s); gsub(/[ \t\r\n]+$/,"",s); return s }
  BEGIN{ v=""; t=""; n=0; }
  {
    line=$0
    sub(/[ \t\r]+$/,"",line)
    if (line ~ /^[ \t]*([#;]|$)/) next
    if (match(line, /^\[vpath[ \t]+"([^"]+)"\][ \t]*$/, m)) {
      if (v!="" && t=="") { printf "E missing target for vpath=%s\n", v; }
      v=m[1]; t=""; n++
      next
    }
    if (v!="" && match(line, /^target[ \t]*=[ \t]*(.*)$/, m2)) {
      t=trim(m2[1]); next
    }
  }
  END{
    if (v!="" && t=="") { printf "E missing target for vpath=%s\n", v; }
    printf "I sections=%d\n", n;
  }' "$f" > /tmp/zmesh-vpath-doctor.$$ 2>/dev/null || true

  while IFS= read -r line; do
    case "$line" in
      E\ *) say "$line"; err=$((err+1));;
      I\ *) say "$line";;
      *) :;;
    esac
  done < /tmp/zmesh-vpath-doctor.$$

  rm -f /tmp/zmesh-vpath-doctor.$$ >/dev/null 2>&1 || true

  # check targets existence if requested
  if [ "$CHECK" -eq 1 ]; then
    awk '
    function trim(s){ gsub(/^[ \t\r\n]+/,"",s); gsub(/[ \t\r\n]+$/,"",s); return s }
    BEGIN{ v=""; }
    {
      line=$0
      sub(/[ \t\r]+$/,"",line)
      if (line ~ /^[ \t]*([#;]|$)/) next
      if (match(line, /^\[vpath[ \t]+"([^"]+)"\]/, m)) { v=m[1]; next }
      if (v!="" && match(line, /^target[ \t]*=[ \t]*(.*)$/, m2)) {
        t=trim(m2[1])
        print v "|" t
      }
    }' "$f" | while IFS='|' read -r v t
    do
      [ -n "$t" ] || continue
      if [ ! -e "$t" ]; then
        say "W target missing: vpath=$v target=$t"
        warn=$((warn+1))
      fi
      count=$((count+1))
    done
  else
    # still count rules
    c=$(awk '
      function trim(s){ gsub(/^[ \t\r\n]+/,"",s); gsub(/[ \t\r\n]+$/,"",s); return s }
      BEGIN{ v=""; c=0 }
      {
        line=$0
        sub(/[ \t\r]+$/,"",line)
        if (line ~ /^[ \t]*([#;]|$)/) next
        if (match(line, /^\[vpath[ \t]+"([^"]+)"\]/, m)) { v=m[1]; next }
        if (v!="" && match(line, /^target[ \t]*=/)) c++
      }
      END{ print c }' "$f")
    count=$((count + c))
  fi
done

say "[summary] rules=$count warnings=$warn errors=$err"

if [ "$STRICT" -eq 1 ] && { [ "$err" -gt 0 ] || [ "$warn" -gt 0 ]; }; then
  die "doctor failed (strict)"
fi

exit 0