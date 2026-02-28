#!/bin/sh
set -eu

# clean-scalefs.sh
# - Cleans runtime/state artifacts for a scalefs body.
# - By default: safe clean only (runtime/temp), no destructive ZFS ops.
# - With --zfs --force: can unmount/destroy dataset listed in scalefs.ini [zfs] dataset=...

. ./common.sh

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
cat <<'EOF'
clean - cleanup runtime/state artifacts of a scalefs body

USAGE
  scalefs clean [options]

COMMAND + OPTIONS
  scalefs clean -p, --path DIR
      Use explicit scalefs body directory

  scalefs clean -i, --id ID
      Resolve scalefs body directory by ID (name.shortid) via registered roots

  scalefs clean --dry-run
      Show what would be removed, do nothing

  scalefs clean --force
      Allow removing directories/files (still avoids ZFS destroy unless --zfs)

  scalefs clean --zfs
      Also attempt ZFS unmount/destroy if scalefs.ini has [zfs] enabled=true and dataset=...
      Requires --force. Best-effort (won't fail the whole clean if ZFS fails).

  scalefs clean -h, --help
      Show this help

WHAT IS CLEANED (default)
  - scalefs.runtime.d/*        (safe, always removable)
  - scalefs.state/tmp*         (safe, if exists)
  - scalefs.state/cache*       (safe, if exists)
  - scalefs.state/logs*        (optional, if exists)

EXAMPLES
  scalefs clean -p /mnt/zmtest/scalefsroot/democell.17ded8 --dry-run
  scalefs clean -i democell.17ded8 --force
  scalefs clean -i democell.17ded8 --force --zfs
EOF
}

resolve_by_id() {
  id="$1"
  load_roots | while IFS='|' read alias path; do
    [ -n "$path" ] || continue
    if [ -d "$path/$id" ]; then
      printf "%s\n" "$path/$id"
      return 0
    fi
  done
  return 1
}

ini_get() {
  # ini_get <file> <section> <key>
  f="$1"; sec="$2"; key="$3"
  awk -v s="[$sec]" -v k="$key" '
    BEGIN{in=0}
    $0==s{in=1; next}
    in==1 && /^\[/{in=0}
    in==1{
      if ($0 ~ "^[ \t]*"k"[ \t]*=") {
        sub(/^[ \t]*[^=]+=/,"")
        gsub(/^[ \t]+|[ \t]+$/,"")
        print
        exit
      }
    }
  ' "$f" 2>/dev/null || true
}

# args
DIR=""
ID=""
DRY=0
FORCE=0
DOZFS=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -p|--path) DIR="${2:-}"; shift 2 ;;
    -i|--id)   ID="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift 1 ;;
    --force)   FORCE=1; shift 1 ;;
    --zfs)     DOZFS=1; shift 1 ;;
    *) die "unknown arg: $1 (use --help)" ;;
  esac
done

if [ -z "$DIR" ]; then
  if [ -n "$ID" ]; then
    DIR="$(resolve_by_id "$ID" || true)"
    [ -n "$DIR" ] || die "cannot resolve id: $ID"
  else
    DIR="."
  fi
fi

[ -d "$DIR" ] || die "no such dir: $DIR"
[ -f "$DIR/scalefs.ini" ] || die "not a scalefs body (missing scalefs.ini): $DIR"

# Default-clean targets (safe)
targets="
$DIR/scalefs.runtime.d
$DIR/scalefs.state/tmp
$DIR/scalefs.state/tmp.*
$DIR/scalefs.state/cache
$DIR/scalefs.state/cache.*
$DIR/scalefs.state/log
$DIR/scalefs.state/logs
"

plan_rm() {
  p="$1"
  if [ -e "$p" ]; then
    say "RM $p"
  fi
}

do_rm() {
  p="$1"
  [ -e "$p" ] || return 0
  if [ "$FORCE" -ne 1 ]; then
    # safe default: only remove inside scalefs.runtime.d, not entire directories elsewhere
    case "$p" in
      "$DIR/scalefs.runtime.d"*)
        rm -rf "$p"
        ;;
      *)
        # refuse
        say "SKIP (need --force) $p"
        ;;
    esac
    return 0
  fi
  rm -rf "$p"
}

say "clean: dir=$DIR dry_run=$DRY force=$FORCE zfs=$DOZFS"

# ZFS handling (optional)
if [ "$DOZFS" -eq 1 ]; then
  if [ "$FORCE" -ne 1 ]; then
    die "--zfs requires --force"
  fi
  if detect_zfs; then
    z_enabled="$(ini_get "$DIR/scalefs.ini" zfs enabled)"
    z_ds="$(ini_get "$DIR/scalefs.ini" zfs dataset)"

    if [ "$z_enabled" = "true" ] && [ -n "$z_ds" ]; then
      say "ZFS: dataset=$z_ds"
      if [ "$DRY" -eq 1 ]; then
        say "ZFS would: zfs umount '$z_ds' ; zfs destroy -r '$z_ds'"
      else
        # best effort
        zfs umount "$z_ds" >/dev/null 2>&1 || true
        zfs destroy -r "$z_ds" >/dev/null 2>&1 || true
      fi
    else
      say "ZFS: not enabled or dataset not set in scalefs.ini; skipping"
    fi
  else
    say "ZFS: zfs command not found; skipping"
  fi
fi

# file removals
if [ "$DRY" -eq 1 ]; then
  for p in $targets; do plan_rm "$p"; done
  say "OK: dry-run only"
  exit 0
fi

for p in $targets; do
  do_rm "$p"
done

say "OK: cleaned (best-effort)"