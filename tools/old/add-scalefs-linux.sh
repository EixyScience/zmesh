#!/usr/bin/env bash

#usage: 
# chmod +x ./add-scalefs.sh
# (zfs mode)
#./add-scalefs.sh /mnt/zmtest bodyA.organB.tissueC.cellD.ab12 zmtest/zmesh.bodyA.organB.tissueC.cellD.ab12
# (generic mode)
#./add-scalefs.sh /mnt/zmtest bodyA.organB.tissueC.cellD.ab12
#

set -euo pipefail

SCALEFS_ROOT="${1:-}"   # 例: /mnt/zmtest
NAME="${2:-}"           # 例: bodyA.organB.tissueC.cellD.ab12
ZFS_DATASET="${3:-}"    # 任意: 例: zmtest/zmesh.bodyA.organB.tissueC.cellD.ab12

if [[ -z "$SCALEFS_ROOT" || -z "$NAME" ]]; then
  echo "usage: $0 <scalefs_root_dir> <name> [zfs_dataset]" >&2
  echo "  example (zfs): $0 /mnt/zmtest bodyA.organB.tissueC.cellD.ab12 zmtest/zmesh.bodyA.organB.tissueC.cellD.ab12" >&2
  echo "  example (dir): $0 /mnt/zmtest bodyA.organB.tissueC.cellD.ab12" >&2
  exit 2
fi

SF="$SCALEFS_ROOT/$NAME"
MAIN="$SF/main"

mkdir -p "$SF/scalefs.runtime.d/scalefs.state" "$SF/scalefs.local.d" "$SF/scalefs.global.d"

# If ZFS dataset specified AND zfs command works -> create+mount at MAIN
if [[ -n "${ZFS_DATASET:-}" ]] && command -v zfs >/dev/null 2>&1; then
  if sudo -n true >/dev/null 2>&1; then
    SUDO="sudo -n"
  else
    SUDO="sudo"
  fi

  mkdir -p "$MAIN"
  # Create if not exists
  if ! $SUDO zfs list -H -o name "$ZFS_DATASET" >/dev/null 2>&1; then
    $SUDO zfs create -o mountpoint="$MAIN" "$ZFS_DATASET"
  else
    # Ensure mountpoint correct (best effort)
    $SUDO zfs set mountpoint="$MAIN" "$ZFS_DATASET" || true
    $SUDO zfs mount "$ZFS_DATASET" || true
  fi
else
  # Fallback: plain directory
  mkdir -p "$MAIN"
fi

INI="$SF/scalefs.ini"
if [[ ! -f "$INI" ]]; then
cat >"$INI" <<'EOF'
[paths]
main = ./main
state_dir = ./scalefs.runtime.d/scalefs.state
watch_root = ./main
watch_exclude = ./scalefs.runtime.d/**, ./scalefs.local.d/**, .shadow/**, .latest/**, .tmp/**, .snapshot/**, .git/**
EOF
fi

GI="$SF/.gitignore"
if [[ ! -f "$GI" ]]; then
cat >"$GI" <<'EOF'
scalefs.runtime.d/
scalefs.local.d/
.shadow/
.latest/
.tmp/
.snapshot/
EOF
fi

echo "ok: created scalefs=$NAME at $SF"
echo "watch_root = $MAIN"
[[ -n "${ZFS_DATASET:-}" ]] && echo "zfs_dataset = ${ZFS_DATASET:-<none>}"