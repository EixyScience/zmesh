#!/bin/sh

ZCONF_DIR="${ZCONF_DIR:-/usr/local/etc/zmesh}"

gen_shortid() {
  s="$(date +%s)"
  if command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$s" | sha256sum | cut -c1-6
  elif command -v sha1sum >/dev/null 2>&1; then
    printf "%s" "$s" | sha1sum | cut -c1-6
  elif command -v shasum >/dev/null 2>&1; then
    printf "%s" "$s" | shasum -a 256 | cut -c1-6
  elif command -v openssl >/dev/null 2>&1; then
    printf "%s" "$s" | openssl dgst -sha256 | awk '{print $2}' | cut -c1-6
  else
    printf "%s" "$s" | tail -c 6
  fi
}

normalize_name() {
  echo "$1" |
    tr '[:upper:]' '[:lower:]' |
    tr -cd 'a-z0-9._-' |
    sed 's/^[^a-z0-9]*//'
}

detect_zfs() {
  command -v zfs >/dev/null 2>&1 && command -v zpool >/dev/null 2>&1
}

# Return a pool name best-effort:
# 1) explicit pool passed in
# 2) detect by matching mountpoint (exact) via zfs list
# 3) detect by walking up parents and matching mountpoints
# 4) fallback: first pool from zpool list
detect_pool() {
  explicit="${1:-}"
  rootpath="${2:-}"

  if [ -n "$explicit" ]; then
    echo "$explicit"
    return 0
  fi

  if ! detect_zfs; then
    echo ""
    return 0
  fi

  # exact mountpoint match → dataset → pool
  ds="$(zfs list -H -o name,mountpoint 2>/dev/null | awk -v mp="$rootpath" '$2==mp{print $1; exit}')"
  if [ -n "$ds" ];


vp_to_filename() {
  # "hobby/car" -> "hobby__car"
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9/_\.-' | sed 's#/#__#g'
}

load_virtualpaths() {
  d="$ZCONF_DIR/virtualpath.d"
  [ -d "$d" ] || return 0
  for f in "$d"/*.conf; do
    [ -f "$f" ] || continue
    awk -F= '
      $1=="path"{gsub(/^[ \t]+|[ \t]+$/,"",$2); path=$2}
      $1=="scalefs"{gsub(/^[ \t]+|[ \t]+$/,"",$2); sid=$2}
      $1=="subpath"{gsub(/^[ \t]+|[ \t]+$/,"",$2); sub=$2}
      END{
        if(path!=""){
          if(sub=="") sub="/";
          print path "|" sid "|" sub
        }
      }' "$f"
  done
}


find_scalefs_main() {
  # args: scalefs_id (name.shortid)
  sid="$1"
  load_roots | while IFS='|' read alias path; do
    [ -n "$path" ] || continue
    cand="$path/$sid/main"
    if [ -d "$cand" ]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}


read_scalefs_id() {
  # args: scalefs_dir
  d="$1"
  f="$d/scalefs.ini"
  [ -f "$f" ] || return 1
  # accept both "id=xxx" and "[scalefs]\nid=xxx" formats
  awk -F= '/^[[:space:]]*id[[:space:]]*=/ {gsub(/[[:space:]]*/,"",$2); print $2; exit}' "$f"
}

zfs_dataset_for_mountpoint() {
  # args: mountpoint path (e.g. /path/to/scalefs/main)
  mp="$1"
  detect_zfs || return 1
  zfs list -H -o name "$mp" 2>/dev/null | head -n 1
}

try_unmount_if_mounted() {
  # best effort
  mp="$1"
  if command -v mount >/dev/null 2>&1; then
    if mount | awk '{print $3}' | grep -qx "$mp"; then
      umount "$mp" 2>/dev/null || true
    fi
  fi
}






