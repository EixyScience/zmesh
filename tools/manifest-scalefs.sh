#!/bin/sh
set -eu

# Manifest exporter for a scalefs body
# - Path指定 or (-i id + -r rootalias) で解決
# - output: json (default) or ini

. ./common.sh

ID=""
ROOT=""
PATHARG="."
FORMAT="json"

usage() {
  cat <<'EOF'
manifest-scalefs.sh - export a scalefs manifest (json/ini)

USAGE
  manifest-scalefs.sh [-p PATH] [-f json|ini]
  manifest-scalefs.sh -i ID [-r ROOT] [-f json|ini]

OPTIONS
  -p, --path PATH      Scalefs body path (default: .)
  -i, --id ID          Scalefs id (name.shortid)
  -r, --root NAME      Root alias (required if id is not unique across roots)
  -f, --format FMT     json (default) | ini
  -h, --help           Show help

EXAMPLES
  # From inside a scalefs directory
  (cd /path/to/democell.28e671 && ./manifest-scalefs.sh)

  # Explicit path
  ./manifest-scalefs.sh -p /scalefsroot/democell.28e671 -f ini

  # Resolve by id + root
  ./manifest-scalefs.sh -i democell.28e671 -r test
EOF
}

die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path) PATHARG="$2"; shift 2;;
    -i|--id) ID="$2"; shift 2;;
    -r|--root) ROOT="$2"; shift 2;;
    -f|--format) FORMAT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1";;
  esac
done

resolve_body_path() {
  if [ -n "$PATHARG" ] && [ "$PATHARG" != "." ]; then
    # best effort resolve
    (cd "$PATHARG" 2>/dev/null && pwd) || die "not a directory: $PATHARG"
    return 0
  fi

  if [ "$PATHARG" = "." ] && [ -f "./scalefs.ini" ]; then
    pwd
    return 0
  fi

  [ -n "$ID" ] || die "require -p PATH or -i ID"
  # resolve by roots
  cands=""
  if [ -n "$ROOT" ]; then
    p="$(load_roots | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
    [ -n "$p" ] || die "unknown root alias: $ROOT"
    d="$p/$ID"
    [ -d "$d" ] || die "not found: $d"
    (cd "$d" && pwd)
    return 0
  fi

  # search unique
  found=""
  count=0
  load_roots | while IFS='|' read -r alias path; do
    d="$path/$ID"
    if [ -d "$d" ]; then
      printf "%s\n" "$d"
    fi
  done >"/tmp/.zmesh_manifest_cands.$$" 2>/dev/null || true

  if [ ! -f "/tmp/.zmesh_manifest_cands.$$" ]; then
    die "internal temp failed"
  fi
  count="$(wc -l < "/tmp/.zmesh_manifest_cands.$$" | tr -d ' ')"
  if [ "$count" -ne 1 ]; then
    rm -f "/tmp/.zmesh_manifest_cands.$$" || true
    die "could not resolve id=$ID uniquely (specify -r ROOT or -p PATH)"
  fi
  found="$(head -n 1 "/tmp/.zmesh_manifest_cands.$$")"
  rm -f "/tmp/.zmesh_manifest_cands.$$" || true

  (cd "$found" && pwd)
}

ini_get() {
  # ini_get <file> <section> <key>
  f="$1"; sec="$2"; key="$3"
  awk -v sec="[$sec]" -v key="$key" '
    BEGIN{in=0}
    $0==sec{in=1; next}
    in==1 && /^\[/{exit}
    in==1 {
      # key=value
      split($0,a,"=")
      k=a[1]
      sub(/^[ \t]+/,"",k); sub(/[ \t]+$/,"",k)
      if (k==key) {
        v=substr($0, index($0,"=")+1)
        sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v)
        print v
        exit
      }
    }
  ' "$f"
}

DIR="$(resolve_body_path)"
INI="$DIR/scalefs.ini"
[ -f "$INI" ] || die "missing scalefs.ini: $INI"

idv="$(ini_get "$INI" scalefs id)"
name="$(ini_get "$INI" scalefs name)"
sid="$(ini_get "$INI" scalefs shortid)"

state_dir="$(ini_get "$INI" paths state_dir)"
watch_root="$(ini_get "$INI" paths watch_root)"

zfs_enabled="$(ini_get "$INI" zfs enabled)"
zfs_pool="$(ini_get "$INI" zfs pool)"