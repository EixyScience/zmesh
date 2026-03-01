#!/usr/bin/env bash
set -euo pipefail

SCALEFS_ROOT="${1:-}"
NAME_IN="${2:-}"
ZFS_DATASET_BASE="${3:-}"   # 任意: 例 zmtest もしくは zmtest/zmeshbase など
NO_SHORTID="${NO_SHORTID:-0}"

if [[ -z "$SCALEFS_ROOT" || -z "$NAME_IN" ]]; then
  echo "usage: $0 <scalefs_root_dir> <name> [zfs_dataset_base]" >&2
  echo " env: NO_SHORTID=1 to disable .<shortid>" >&2
  exit 2
fi

normalize() {
  local s="$1"
  s="$(echo "$s" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [[ -z "$s" ]] && { echo "scalefs"; return; }

  # separators -> dot
  s="$(echo "$s" | sed -E 's#[\\/:;,]+#.#g')"
  # spaces -> dash
  s="$(echo "$s" | sed -E 's/[[:space:]]+/-/g')"
  # allow a-z0-9._-
  s="$(echo "$s" | sed -E 's/[^a-z0-9._-]//g')"
  # collapse ..
  while echo "$s" | grep -q '\.\.'; do s="${s//../.}"; done
  # trim leading/trailing .-_
  s="$(echo "$s" | sed -E 's/^[._-]+//; s/[._-]+$//')"
  [[ -z "$s" ]] && s="scalefs"
  echo "$s"
}

shortid() {
  # 6 chars from a-z2-7
  local n=6
  tr -dc 'a-z2-7' </dev/urandom | head -c "$n"
}

NORM="$(normalize "$NAME_IN")"
SID=""
if [[ "$NO_SHORTID" != "1" ]]; then
  SID="$(shortid)"
fi

FINAL="$NORM"
[[ -n "$SID" ]] && FINAL="${NORM}.${SID}"

SF="${SCALEFS_ROOT}/${FINAL}"
MAIN="${SF}/main"

if [[ -e "$SF" ]]; then
  echo "already exists: $SF" >&2
  exit 1
fi

mkdir -p "$SF/scalefs.runtime.d/scalefs.state" "$SF/scalefs.local.d" "$SF/scalefs.global.d"

# ZFS: if base specified and zfs exists -> create dataset at mountpoint MAIN
if [[ -n "${ZFS_DATASET_BASE:-}" ]] && command -v zfs >/dev/null 2>&1; then
  if sudo -n true >/dev/null 2>&1; then SUDO="sudo -n"; else SUDO="sudo"; fi
  mkdir -p "$MAIN"

  # dataset name: <base>/<final>  (base may already include slash)
  DATASET="${ZFS_DATASET_BASE%/}/${FINAL}"

  if ! $SUDO zfs list -H -o name "$DATASET" >/dev/null 2>&1; then
    $SUDO zfs create -o mountpoint="$MAIN" "$DATASET"
  else
    $SUDO zfs set mountpoint="$MAIN" "$DATASET" || true
    $SUDO zfs mount "$DATASET" || true
  fi
else
  mkdir -p "$MAIN"
fi

cat >"${SF}/scalefs.ini" <<'EOF'
[paths]
main = ./main
state_dir = ./scalefs.runtime.d/scalefs.state
watch_root = ./main
watch_exclude = ./scalefs.runtime.d/**, ./scalefs.local.d/**, .shadow/**, .latest/**, .tmp/**, .snapshot/**, .git/**
EOF

cat >"${SF}/.gitignore" <<'EOF'
scalefs.runtime.d/
scalefs.local.d/
.shadow/
.latest/
.tmp/
.snapshot/
EOF

echo "ok: created scalefs=${FINAL}"
echo "path: ${SF}"
echo "watch_root: ${MAIN}"