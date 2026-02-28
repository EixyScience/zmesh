#!/bin/sh
set -eu

# List virtualpath rules from $ZCONF_DIR/virtualpath.d/*.conf

ZCONF_DIR="${ZCONF_DIR:-/usr/local/etc/zmesh}"
CONF_DIR="$ZCONF_DIR/virtualpath.d"

say(){ printf "%s\n" "$*"; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
cat <<'EOF'
list-virtualpath.sh - list virtual path rules

USAGE
  list-virtualpath.sh [--file NAME.conf] [--format table|raw]

OPTIONS
  -f, --file NAME         Only read a specific file under virtualpath.d/
  --format table|raw      table(default)=vpath target file, raw=print blocks as-is
  -h, --help              Show help

ENV
  ZCONF_DIR               Config directory (default: /usr/local/etc/zmesh)

EXAMPLES
  ZCONF_DIR=/usr/local/etc/zmesh ./tools/list-virtualpath.sh
  ZCONF_DIR=/usr/local/etc/zmesh ./tools/list-virtualpath.sh --file virtualpath.local.conf
  ZCONF_DIR=/usr/local/etc/zmesh ./tools/list-virtualpath.sh --format raw
EOF
}

FILE=""
FMT="table"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -f|--file) FILE="${2:-}"; shift 2;;
    --file=*) FILE="${1#*=}"; shift 1;;
    --format) FMT="${2:-}"; shift 2;;
    --format=*) FMT="${1#*=}"; shift 1;;
    *) die "unknown arg: $1 (use --help)";;
  esac
done

[ -d "$CONF_DIR" ] || { say "(no config dir) $CONF_DIR"; exit 0; }

files=""
if [ -n "$FILE" ]; then
  p="$CONF_DIR/$FILE"
  [ -f "$p" ] || die "missing file: $p"
  files="$p"
else
  # shellcheck disable=SC2086
  files=$(ls -1 "$CONF_DIR"/*.conf 2>/dev/null || true)
fi

[ -n "$files" ] || { say "(no rules)"; exit 0; }

if [ "$FMT" = "raw" ]; then
  for f in $files; do
    say "== $f =="
    cat "$f"
    say ""
  done
  exit 0
fi

# Table format
say "vpath | target | file"
say "----- | ------ | ----"

for f in $files; do
  awk -v file="$f" '
  function trim(s){ gsub(/^[ \t\r\n]+/,"",s); gsub(/[ \t\r\n]+$/,"",s); return s }
  BEGIN{ v=""; t=""; }
  {
    line=$0
    sub(/[ \t\r]+$/,"",line)
    if (line ~ /^[ \t]*([#;]|$)/) next
    if (match(line, /^\[vpath[ \t]+"([^"]+)"\][ \t]*$/, m)) {
      # flush previous
      if (v!="" && t!="") printf "%s | %s | %s\n", v, t, file
      v=m[1]; t=""
      next
    }
    if (v!="" && match(line, /^target[ \t]*=[ \t]*(.*)$/, m2)) {
      t=trim(m2[1]); next
    }
  }
  END{ if (v!="" && t!="") printf "%s | %s | %s\n", v, t, file }
  ' "$f"
done