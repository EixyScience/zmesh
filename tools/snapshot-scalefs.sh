#!/bin/sh
set -eu

# tools/snapshot-scalefs.sh
# ZFS-only: create snapshot for scalefs dataset and record state
#
# Resolve target by:
#  -p/--path PATH      (body dir, "." allowed)
#  -i/--id ID [-r ROOT]
#
# Snapshot name: zmesh-<unixms>-<node>
# Records:
#   scalefs.state/replication/last_snapshot
#   scalefs.state/replication/history.log (append)

ID=""
ROOT=""
PATHV=""
NODE="${NODE_ID:-}"         # optional env
SNAP_NAME=""                # optional override
YES=0

usage() {
cat <<'EOF'
snapshot-scalefs.sh - create ZFS snapshot for a scalefs body (ZFS-only)

USAGE
  snapshot-scalefs.sh (-p PATH | -i ID [-r ROOT]) [-N NODE] [-S SNAPNAME] [-y]

OPTIONS
  -p, --path PATH         Scalefs body path (e.g. "." or "/scalefsroot/democell.28e671")
  -i, --id ID             Scalefs id (name.shortid)
  -r, --root ALIAS        Root alias (to disambiguate ID)
  -N, --node NODE         Node id for snapshot naming (default: $NODE_ID or hostname)
  -S, --snap SNAPNAME     Snapshot name override (default: zmesh-<unixms>-<node>)
  -y, --yes               Do not prompt
  -h, --help              Show help

EXAMPLES
  # Create snapshot for current body directory (no prompt)
  snapshot-scalefs.sh -p . -y

  # Snapshot by ID resolved under a root alias
  snapshot-scalefs.sh -i democell.28e671 -r test -N node-01 -y
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path) PATHV="${2:-}"; shift 2;;
    -i|--id) ID="${2:-}"; shift 2;;
    -r|--root) ROOT="${2:-}"; shift 2;;
    -N|--node) NODE="${2:-}"; shift 2;;
    -S|--snap) SNAP_NAME="${2:-}"; shift 2;;
    -y|--yes) YES=1; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 2;;
  esac
done

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_DIR="$BASE_DIR/tools"
. "$TOOLS_DIR/common.sh"

die(){ echo "ERROR: $*" >&2; exit 1; }

resolve_body_path() {
  if [ -n "$PATHV" ]; then
    if [ "$PATHV" = "." ]; then
      pwd
    else
      (cd "$PATHV" 2>/dev/null && pwd) || die "not a directory: $PATHV"
    fi
    return 0
  fi

  [ -n "$ID" ] || die "require --path or --id"
  roots="$(load_roots || true)"
  [ -n "$roots" ] || die "no roots configured (ZCONF_DIR=$ZCONF_DIR)"

  if [ -n "$ROOT" ]; then
    p="$(printf "%s\n" "$roots" | awk -F'|' -v r="$ROOT" '$1==r{print $2; exit}')"
    [ -n "$p" ] || die "unknown root alias: $ROOT"
    d="$p/$ID"
    [ -d "$d" ] || die "not found: $d"
    (cd "$d" && pwd)
    return 0
  fi

  # unique match
  cands=""
  count=0
  printf "%s\n" "$roots" | while IFS='|' read a p; do
    [ -d "$p/$ID" ] || continue
    echo "$p/$ID"
  done > "/tmp/.zmesh_snapshot_candidates.$$" 2>/dev/null || true

  if [ -f "/tmp/.zmesh_snapshot_candidates.$$" ]; then
    count=$(wc -l < "/tmp/.zmesh_snapshot_candidates.$$" | tr -d ' ')
    if [ "$count" -eq 1 ]; then
      cands=$(cat "/tmp/.zmesh_snapshot_candidates.$$")
      rm -f "/tmp/.zmesh_snapshot_candidates.$$"
      (cd "$cands" && pwd)
      return 0
    fi
    rm -f "/tmp/.zmesh_snapshot_candidates.$$"
  fi

  die "could not resolve id=$ID uniquely (specify --root or --path)"
}

ini_get() {
  ini="$1"; sec="$2"; key="$3"
  awk -v SEC="[$sec]" -v KEY="$key" '
    $0==SEC {in=1; next}
    in && /^\[/ {exit}
    in && $0 ~ "^[[:space:]]*"KEY"[[:space:]]*=" {
      sub("^[[:space:]]*"KEY"[[:space:]]*=","",$0)
      gsub(/[[:space:]]*$/,"",$0)
      print $0
      exit
    }
  ' "$ini" || true
}

[ "$(detect_zfs && echo yes || echo no)" = "yes" ] || die "zfs command not found (ZFS-only)"

DIR="$(resolve_body_path)"
INI="$DIR/scalefs.ini"
[ -f "$INI" ] || die "missing scalefs.ini: $INI"

zfs_enabled="$(ini_get "$INI" zfs enabled)"
zfs_dataset="$(ini_get "$INI" zfs dataset)"
[ "$zfs_enabled" = "true" ] || die "zfs disabled in scalefs.ini ([zfs] enabled=true required)"
[ -n "$zfs_dataset" ] || die "missing [zfs] dataset in scalefs.ini"

if [ -z "$NODE" ]; then
  NODE="$(hostname 2>/dev/null || echo node)"
fi

now_ms="$(date +%s 2>/dev/null)000"
if [ -z "$SNAP_NAME" ]; then
  SNAP_NAME="zmesh-${now_ms}-${NODE}"
fi

echo "Target:"
echo "  body   : $DIR"
echo "  dataset: $zfs_dataset"
echo "Plan:"
echo "  snapshot: ${zfs_dataset}@${SNAP_NAME}"

if [ "$YES" -ne 1 ]; then
  printf "Proceed? (y/N): "
  read ans || true
  case "${ans:-}" in
    y|Y|yes|YES) : ;;
    *) echo "aborted"; exit 0;;
  esac
fi

# Create snapshot (fail loud)
zfs snapshot "${zfs_dataset}@${SNAP_NAME}"

# Record state
st_dir="$DIR/scalefs.state/replication"
mkdir -p "$st_dir"
printf "%s\n" "$SNAP_NAME" > "$st_dir/last_snapshot"
printf "%s\t%s\t%s\n" "$(date +%s)" "$zfs_dataset" "$SNAP_NAME" >> "$st_dir/history.log"

echo "OK snapshot created: ${zfs_dataset}@${SNAP_NAME}"