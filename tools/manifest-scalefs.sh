#!/bin/sh
set -eu

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
cat <<'EOF'
manifest-scalefs.sh - print scalefs body manifest (json or ini)

USAGE
  sh tools/manifest-scalefs.sh [options]

OPTIONS
  -p, --path PATH     Path inside a scalefs body (body dir OR any subdir)
  -f, --format FMT    json (default) | ini
  -h, --help          Show help

EXAMPLES
  # Run inside a scalefs body:
  cd /path/to/democell.28e671 && sh /path/to/zmesh/tools/manifest-scalefs.sh -p .

  # Or point to any subdir (it will walk up):
  sh tools/manifest-scalefs.sh -p /path/to/democell.28e671/main -f ini
EOF
}

PATH_IN="."
FMT="json"

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path) PATH_IN="${2:-}"; shift 2;;
    -f|--format) FMT="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1 (use -h)";;
  esac
done

case "$FMT" in
  json|ini) ;;
  *) die "invalid format: $FMT (json|ini)";;
esac

# Resolve to absolute path
if [ "$PATH_IN" = "." ]; then
  CUR="$(pwd)"
else
  CUR="$PATH_IN"
fi

# Find scalefs.ini by walking up
find_body_dir() {
  d="$1"
  # normalize
  if command -v realpath >/dev/null 2>&1; then
    d="$(realpath "$d" 2>/dev/null || printf "%s" "$d")"
  fi

  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -f "$d/scalefs.ini" ]; then
      printf "%s\n" "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}

BODY="$(find_body_dir "$CUR" || true)"
[ -n "$BODY" ] || die "missing scalefs.ini near: $CUR
HINT: run inside a scalefs body dir (contains scalefs.ini), e.g.
  cd /path/to/<name>.<shortid> && sh tools/manifest-scalefs.sh -p .
or point to a subdir inside it:
  sh tools/manifest-scalefs.sh -p /path/to/<name>.<shortid>/main"

INI="$BODY/scalefs.ini"

ini_get() {
  sec="$1"; key="$2"
  awk -v sec="[$sec]" -v key="$key" '
    BEGIN{in=0}
    $0 ~ /^[[:space:]]*\[/ { in=0 }
    $0 ~ "^[[:space:]]*"sec"[[:space:]]*$" { in=1; next }
    in==1 {
      # strip comments
      sub(/[;#].*$/,"")
      if ($0 ~ "^[[:space:]]*"key"[[:space:]]*=") {
        sub("^[[:space:]]*"key"[[:space:]]*=","")
        gsub(/^[[:space:]]+|[[:space:]]+$/,"")
        print; exit
      }
    }
  ' "$INI"
}

ID="$(ini_get scalefs id)"
NAME="$(ini_get scalefs name)"
SID="$(ini_get scalefs shortid)"

STATE_DIR="$(ini_get paths state_dir)"
WATCH_ROOT="$(ini_get paths watch_root)"

ZFS_EN="$(ini_get zfs enabled)"
ZFS_POOL="$(ini_get zfs pool)"
ZFS_DS="$(ini_get zfs dataset)"

NOW="$(date +%s)"
OS="$(uname -s 2>/dev/null || echo unknown)"

MAIN="$BODY/main"
STATE="$BODY/scalefs.state"
GD="$BODY/scalefs.global.d"
LD="$BODY/scalefs.local.d"
RD="$BODY/scalefs.runtime.d"

if [ "$FMT" = "ini" ]; then
  cat <<EOF
[manifest]
generated_unix=$NOW
os=$OS
path=$BODY

[scalefs]
id=$ID
name=$NAME
shortid=$SID

[paths]
main=$MAIN
state=$STATE
global_d=$GD
local_d=$LD
runtime_d=$RD

[config]
state_dir=$STATE_DIR
watch_root=$WATCH_ROOT

[zfs]
enabled=$ZFS_EN
pool=$ZFS_POOL
dataset=$ZFS_DS
EOF
  exit 0
fi

# json (minimal, no jq dependency)
# escape helper
json_escape() { printf "%s" "$1" | awk '
  BEGIN{ORS=""}
  {
    gsub(/\\/,"\\\\");
    gsub(/"/,"\\\"");
    gsub(/\r/,"\\r");
    gsub(/\n/,"\\n");
    gsub(/\t/,"\\t");
    print
  }'
}

cat <<EOF
{
  "ok": true,
  "generated_unix": $NOW,
  "os": "$(json_escape "$OS")",
  "path": "$(json_escape "$BODY")",
  "scalefs": {
    "id": "$(json_escape "$ID")",
    "name": "$(json_escape "$NAME")",
    "shortid": "$(json_escape "$SID")"
  },
  "paths": {
    "main": "$(json_escape "$MAIN")",
    "state": "$(json_escape "$STATE")",
    "global_d": "$(json_escape "$GD")",
    "local_d": "$(json_escape "$LD")",
    "runtime_d": "$(json_escape "$RD")"
  },
  "config": {
    "state_dir": "$(json_escape "$STATE_DIR")",
    "watch_root": "$(json_escape "$WATCH_ROOT")"
  },
  "zfs": {
    "enabled": "$(json_escape "$ZFS_EN")",
    "pool": "$(json_escape "$ZFS_POOL")",
    "dataset": "$(json_escape "$ZFS_DS")"
  }
}
EOF