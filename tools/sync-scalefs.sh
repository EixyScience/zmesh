#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

# tools/sync-scalefs.sh
# ZFS-only: zfs send | ssh ... zfs recv で push レプリケーション
#
# Required:
#   --peer user@host      (ssh target)
#   --dest DATASET        (remote dataset to receive into)
#
# Target resolution:
#   -p PATH or -i ID [-r ROOT]
#
# Snapshot selection:
#   -S SNAPNAME  : send this snapshot (existing) (recommended with snapshot-scalefs.sh)
#   -A           : auto-create snapshot first, then send it
#
# Records:
#   scalefs.state/replication/peers/<peer_key>.last_sent

ID=""
ROOT=""
PATHV=""

PEER=""
DEST=""
SSH="ssh"
NODE="${NODE_ID:-}"
SNAP_NAME=""
AUTO_SNAP=0
YES=0

usage() {
cat <<'EOF'
sync-scalefs.sh - push ZFS snapshot to peer (ZFS-only)

USAGE
  sync-scalefs.sh (-p PATH | -i ID [-r ROOT]) --peer USER@HOST --dest DATASET [options]

REQUIRED
  --peer USER@HOST        SSH destination (e.g. root@10.0.0.12)
  --dest DATASET          Remote dataset to receive into (e.g. zpool/scalefs/democell-28e671)

TARGET
  -p, --path PATH         Scalefs body path (e.g. "." or "/scalefsroot/democell.28e671")
  -i, --id ID             Scalefs id (name.shortid)
  -r, --root ALIAS        Root alias (to disambiguate ID)

SNAPSHOT
  -S, --snap SNAPNAME     Send this snapshot name (must exist locally)
  -A, --auto-snap         Create a new snapshot first (like snapshot-scalefs.sh)

OTHER OPTIONS
  --ssh CMD               SSH command (default: ssh). Example: --ssh "ssh -p 2222"
  -N, --node NODE         Node id used when auto-snap naming
  -y, --yes               Do not prompt
  -h, --help              Show help

EXAMPLES
  # Create snapshot then send to peer (no prompt)
  sync-scalefs.sh -p . -A --peer root@10.0.0.12 --dest zroot/scalefs/democell-28e671 -y

  # Send an existing snapshot
  sync-scalefs.sh -i democell.28e671 -r test -S zmesh-1772170886000-node-01 \
    --peer root@10.0.0.12 --dest zroot/scalefs/democell-28e671 -y
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path) PATHV="${2:-}"; shift 2;;
    -i|--id) ID="${2:-}"; shift 2;;
    -r|--root) ROOT="${2:-}"; shift 2;;

    --peer) PEER="${2:-}"; shift 2;;
    --dest) DEST="${2:-}"; shift 2;;
    --ssh) SSH="${2:-}"; shift 2;;

    -S|--snap) SNAP_NAME="${2:-}"; shift 2;;
    -A|--auto-snap) AUTO_SNAP=1; shift 1;;

    -N|--node) NODE="${2:-}"; shift 2;;
    -y|--yes) YES=1; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 2;;
  esac
done

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_DIR="$BASE_DIR/tools"
. "$TOOLS_DIR/common.sh"

die(){ echo "ERROR: $*" >&2; exit 1; }

[ "$(detect_zfs && echo yes || echo no)" = "yes" ] || die "zfs command not found (ZFS-only)"
[ -n "$PEER" ] || die "require --peer"
[ -n "$DEST" ] || die "require --dest"

resolve_body_path() {
  if [ -n "$PATHV" ]; then
    if [ "$PATHV" = "." ]; then pwd; else (cd "$PATHV" 2>/dev/null && pwd) || die "not a directory: $PATHV"; fi
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
  printf "%s\n" "$roots" | while IFS='|' read a p; do
    [ -d "$p/$ID" ] || continue
    echo "$p/$ID"
  done > "/tmp/.zmesh_sync_candidates.$$" 2>/dev/null || true

  if [ -f "/tmp/.zmesh_sync_candidates.$$" ]; then
    c=$(wc -l < "/tmp/.zmesh_sync_candidates.$$" | tr -d ' ')
    if [ "$c" -eq 1 ]; then
      d=$(cat "/tmp/.zmesh_sync_candidates.$$")
      rm -f "/tmp/.zmesh_sync_candidates.$$"
      (cd "$d" && pwd)
      return 0
    fi
    rm -f "/tmp/.zmesh_sync_candidates.$$"
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

peer_key() {
  # file-safe key
  printf "%s" "$1" | tr '/:@' '___' | tr -cd 'a-zA-Z0-9._-'
}

snap_exists() {
  ds="$1"; sn="$2"
  zfs list -H -t snapshot -o name "${ds}@${sn}" >/dev/null 2>&1
}

DIR="$(resolve_body_path)"
INI="$DIR/scalefs.ini"
[ -f "$INI" ] || die "missing scalefs.ini: $INI"

zfs_enabled="$(ini_get "$INI" zfs enabled)"
zfs_dataset="$(ini_get "$INI" zfs dataset)"
[ "$zfs_enabled" = "true" ] || die "zfs disabled in scalefs.ini ([zfs] enabled=true required)"
[ -n "$zfs_dataset" ] || die "missing [zfs] dataset in scalefs.ini"

# Determine snapshot to send
if [ "$AUTO_SNAP" -eq 1 ]; then
  if [ -z "$NODE" ]; then NODE="$(hostname 2>/dev/null || echo node)"; fi
  now_ms="$(date +%s 2>/dev/null)000"
  SNAP_NAME="zmesh-${now_ms}-${NODE}"
  zfs snapshot "${zfs_dataset}@${SNAP_NAME}"
  mkdir -p "$DIR/scalefs.state/replication"
  printf "%s\n" "$SNAP_NAME" > "$DIR/scalefs.state/replication/last_snapshot"
fi

if [ -z "$SNAP_NAME" ]; then
  # fallback to last_snapshot
  lsnap="$DIR/scalefs.state/replication/last_snapshot"
  [ -f "$lsnap" ] || die "require --snap or --auto-snap (no last_snapshot found)"
  SNAP_NAME="$(cat "$lsnap" | tr -d '\r\n')"
fi

snap_exists "$zfs_dataset" "$SNAP_NAME" || die "snapshot not found: ${zfs_dataset}@${SNAP_NAME}"

# Determine incremental base (per peer)
st_dir="$DIR/scalefs.state/replication/peers"
mkdir -p "$st_dir"
pkey="$(peer_key "$PEER")"
sent_file="$st_dir/$pkey.last_sent"
prev=""
if [ -f "$sent_file" ]; then
  prev="$(cat "$sent_file" | tr -d '\r\n')"
fi

# If prev exists and still present locally, do incremental; else full
MODE="full"
SEND_ARGS=""
if [ -n "$prev" ] && snap_exists "$zfs_dataset" "$prev"; then
  MODE="incremental"
  SEND_ARGS="-i ${zfs_dataset}@${prev} ${zfs_dataset}@${SNAP_NAME}"
else
  SEND_ARGS="${zfs_dataset}@${SNAP_NAME}"
fi

echo "Target:"
echo "  body    : $DIR"
echo "  dataset : $zfs_dataset"
echo "Peer:"
echo "  peer    : $PEER"
echo "  dest    : $DEST"
echo "Plan:"
echo "  mode    : $MODE"
echo "  send    : zfs send $SEND_ARGS"
echo "  recv    : $SSH $PEER zfs recv -u -F $DEST"

if [ "$YES" -ne 1 ]; then
  printf "Proceed? (y/N): "
  read ans || true
  case "${ans:-}" in
    y|Y|yes|YES) : ;;
    *) echo "aborted"; exit 0;;
  esac
fi

# Remote: ensure dataset exists (create parents), then recv
# NOTE: zfs create -p for filesystem datasets; you can adjust later for volumes.
# -u: do not mount automatically
# -F: rollback/destroy conflicting snapshots on destination dataset
# shellcheck disable=SC2086
$SSH "$PEER" "zfs create -p '$DEST' >/dev/null 2>&1 || true"

# Transfer
# shellcheck disable=SC2086
zfs send $SEND_ARGS | $SSH "$PEER" "zfs recv -u -F '$DEST'"

# Record state
printf "%s\n" "$SNAP_NAME" > "$sent_file"
printf "%s\tpeer=%s\tdest=%s\tmode=%s\tsnap=%s\n" "$(date +%s)" "$PEER" "$DEST" "$MODE" "$SNAP_NAME" >> "$st_dir/$pkey.log"

echo "OK synced: ${zfs_dataset}@${SNAP_NAME} -> ${PEER}:${DEST} ($MODE)"