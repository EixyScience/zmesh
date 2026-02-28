#!/bin/sh
set -eu

. ./common.sh

ID=""
ROOT=""
PATHVAL=""
FMT="json"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: manifest-scalefs.sh [options]

Options:
  -h, --help              Show help
  -i, --id ID             Target by id (name.shortid)
  -r, --root ALIAS        Root alias (used with -i)
  -p, --path PATH         Target by explicit body path
  -f, --format FMT        json|ini (default: json)

Examples:
  manifest-scalefs.sh -p .
  manifest-scalefs.sh -i democell.28e671 -r test
  manifest-scalefs.sh -p /mnt/zmtest/scalefsroot/democell.28e671 -f ini
EOF
}

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -i|--id) ID="${2:-}"; shift 2;;
    -r|--root) ROOT="${2:-}"; shift 2;;
    -p|--path) PATHVAL="${2:-}"; shift 2;;
    -f|--format) FMT="${2:-}"; shift 2;;
    *) die "unknown arg: $1";;
  esac
done

# resolve target dir
if [ -n "$PATHVAL" ]; then
  DIR="$PATHVAL"
else
  [ -n "$ID" ] || die "require --path or --id"
  if [ -z "$ROOT" ]; then
    # allow unique match across all roots
    found=""
    resolve_root_path | while IFS='|' read alias path; do
      [ -d "$path/$ID" ] && printf "%s\n" "$path/$ID"
    done > /tmp/.zmesh_manifest_candidates.$$ 2>/dev/null || true
    if [ -f /tmp/.zmesh_manifest_candidates.$$ ]; then
      n="$(wc -l < /tmp/.zmesh_manifest_candidates.$$ | tr -d ' ')"
      if [ "$n" -eq 1 ]; then
        found="$(cat /tmp/.zmesh_manifest_candidates.$$)"
      fi
      rm -f /tmp/.zmesh_manifest_candidates.$$ || true
    fi
    [ -n "$found" ] || die "could not resolve id=$ID (specify --root or --path)"
    DIR="$found"
  else
    base="$(resolve_root_path | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
    [ -n "$base" ] || die "unknown root alias: $ROOT"
    DIR="$base/$ID"
  fi
fi

# normalize
case "$DIR" in
  .) DIR="$(pwd)";;
esac

[ -d "$DIR" ] || die "not a directory: $DIR"
INI="$DIR/scalefs.ini"
[ -f "$INI" ] || die "missing scalefs.ini: $INI"

# collect fields (best-effort ini parse)
get_ini_kv() {
  sec="$1"; key="$2"
  awk -v sec="[$sec]" -v key="$key" '
    BEGIN{in=0}
    $0==sec{in=1; next}
    in==1 && /^\[/{exit}
    in==1{
      if ($0 ~ "^[[:space:]]*"key"[[:space:]]*=") {
        sub("^[[:space:]]*"key"[[:space:]]*=","")
        gsub("\r","")
        print
        exit
      }
    }
  ' "$INI"
}

id="$(get_ini_kv scalefs id)"
name="$(get_ini_kv scalefs name)"
shortid="$(get_ini_kv scalefs shortid)"

state_dir="$(get_ini_kv paths state_dir)"
watch_root="$(get_ini_kv paths watch_root)"

zfs_enabled="$(get_ini_kv zfs enabled)"
zfs_pool="$(get_ini_kv zfs pool)"
zfs_dataset="$(get_ini_kv zfs dataset)"

main="$DIR/main"
state="$DIR/scalefs.state"
gdir="$DIR/scalefs.global.d"
ldir="$DIR/scalefs.local.d"
rdir="$DIR/scalefs.runtime.d"

now="$(date +%s 2>/dev/null || true)"
os="$(uname -s 2>/dev/null || echo unknown)"

# output
if [ "$FMT" = "ini" ]; then
  cat <<EOF
[manifest]
generated_unix=$now
os=$os
path=$DIR

[scalefs]
id=$id
name=$name
shortid=$shortid

[paths]
main=$main
state=$state
global_d=$gdir
local_d=$ldir
runtime_d=$rdir

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

# default json (no jq dependency)
esc() {
  # minimal JSON escaping for \ and "
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

cat <<EOF
{
  "ok": true,
  "generated_unix": $now,
  "os": "$(esc "$os")",
  "path": "$(esc "$DIR")",
  "scalefs": {
    "id": "$(esc "$id")",
    "name": "$(esc "$name")",
    "shortid": "$(esc "$shortid")"
  },
  "paths": {
    "main": "$(esc "$main")",
    "state": "$(esc "$state")",
    "global_d": "$(esc "$gdir")",
    "local_d": "$(esc "$ldir")",
    "runtime_d": "$(esc "$rdir")"
  },
  "config": {
    "state_dir": "$(esc "$state_dir")",
    "watch_root": "$(esc "$watch_root")"
  },
  "zfs": {
    "enabled": "$(esc "$zfs_enabled")",
    "pool": "$(esc "$zfs_pool")",
    "dataset": "$(esc "$zfs_dataset")"
  }
}
EOF