#!/bin/sh
set -eu

# manifest-scalefs.sh
# - Print scalefs body manifest in JSON (default) or INI
# - You must run inside a scalefs body dir (has scalefs.ini), OR pass -p
# - If -p points to a file inside body, it will walk up to find scalefs.ini

DIR="."
FORMAT="json"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
manifest-scalefs.sh - show manifest for a scalefs body

USAGE
  manifest-scalefs.sh [-p PATH] [-f json|ini] [-h]

OPTIONS
  -p, --path PATH     Path inside scalefs body (dir or file). Default: .
  -f, --format FMT    json (default) or ini
  -h, --help          Show help

EXAMPLES
  # Run inside a scalefs body directory
  cd /path/to/democell.28e671
  sh tools/manifest-scalefs.sh -p .

  # From anywhere, point to the body directory
  sh tools/manifest-scalefs.sh -p /scalefsroot/democell.28e671 -f json
EOF
}

# --- arg parse ---
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path)   DIR="${2:-}"; shift 2 ;;
    -f|--format) FORMAT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1 (use -h)";;
  esac
done

case "$FORMAT" in
  json|ini) :;;
  *) die "invalid format: $FORMAT (json|ini)";;
esac

# --- resolve scalefs.ini by walking up ---
resolve_body_dir() {
  p="$1"
  [ -n "$p" ] || p="."

  # normalize
  if [ -f "$p" ]; then
    d=$(CDPATH= cd -- "$(dirname -- "$p")" && pwd)
  else
    d=$(CDPATH= cd -- "$p" 2>/dev/null && pwd) || return 1
  fi

  cur="$d"
  while :; do
    if [ -f "$cur/scalefs.ini" ]; then
      printf "%s\n" "$cur"
      return 0
    fi
    parent=$(dirname -- "$cur")
    [ "$parent" = "$cur" ] && break
    cur="$parent"
  done
  return 1
}

BODY_DIR="$(resolve_body_dir "$DIR" || true)"
[ -n "$BODY_DIR" ] || die "missing scalefs.ini near: $DIR
HINT: run inside a scalefs body dir (contains scalefs.ini), e.g.
  cd /path/to/<name>.<shortid> && sh tools/manifest-scalefs.sh -p ."

INI="$BODY_DIR/scalefs.ini"

# --- ini reader (section/key) ---
ini_get() {
  section="$1"
  key="$2"
  awk -v sec="[$section]" -v key="$key" '
    BEGIN{in=0}
    $0 ~ "^[[:space:]]*\\[" {
      in = ($0==sec) ? 1 : 0
    }
    in==1 {
      # strip CR
      sub(/\r$/, "", $0)
      if ($0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
        sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", $0)
        print $0
        exit
      }
    }
  ' "$INI"
}

id="$(ini_get scalefs id)"
name="$(ini_get scalefs name)"
sid="$(ini_get scalefs shortid)"

state_dir="$(ini_get paths state_dir)"
watch_root="$(ini_get paths watch_root)"

zfs_enabled="$(ini_get zfs enabled)"
zfs_pool="$(ini_get zfs pool)"
zfs_dataset="$(ini_get zfs dataset)"

now="$(date +%s 2>/dev/null || echo 0)"
os="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo unknown)"

main_path="$BODY_DIR/main"
state_path="$BODY_DIR/scalefs.state"
global_d="$BODY_DIR/scalefs.global.d"
local_d="$BODY_DIR/scalefs.local.d"
runtime_d="$BODY_DIR/scalefs.runtime.d"

if [ "$FORMAT" = "ini" ]; then
  cat <<EOF
[manifest]
generated_unix=$now
os=$os
path=$BODY_DIR

[scalefs]
id=$id
name=$name
shortid=$sid

[paths]
main=$main_path
state=$state_path
global_d=$global_d
local_d=$local_d
runtime_d=$runtime_d

[config]
state_dir=$state_dir
watch_root=$watch_root

[zfs]
enabled=$zfs_enabled
pool=$zfs_pool
dataset=$zfs_dataset
EOF
  exit 0
fi

# json
escape_json() {
  # minimal escape
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

cat <<EOF
{
  "ok": true,
  "generated_unix": $now,
  "os": "$(escape_json "$os")",
  "path": "$(escape_json "$BODY_DIR")",
  "scalefs": { "id": "$(escape_json "$id")", "name": "$(escape_json "$name")", "shortid": "$(escape_json "$sid")" },
  "paths": {
    "main": "$(escape_json "$main_path")",
    "state": "$(escape_json "$state_path")",
    "global_d": "$(escape_json "$global_d")",
    "local_d": "$(escape_json "$local_d")",
    "runtime_d": "$(escape_json "$runtime_d")"
  },
  "config": { "state_dir": "$(escape_json "$state_dir")", "watch_root": "$(escape_json "$watch_root")" },
  "zfs": { "enabled": "$(escape_json "$zfs_enabled")", "pool": "$(escape_json "$zfs_pool")", "dataset": "$(escape_json "$zfs_dataset")" }
}
EOF