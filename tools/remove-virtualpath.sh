#!/bin/sh
set -eu

# Remove a [vpath "..."] rule from a conf file under $ZCONF_DIR/virtualpath.d/
# Default target file: virtualpath.local.conf

ZCONF_DIR="${ZCONF_DIR:-/usr/local/etc/zmesh}"
CONF_DIR="$ZCONF_DIR/virtualpath.d"
DEFAULT_FILE="virtualpath.local.conf"

say(){ printf "%s\n" "$*"; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
cat <<'EOF'
remove-virtualpath.sh - remove a virtual path rule

USAGE
  remove-virtualpath.sh --vpath <REL> [--file <NAME.conf>] [--yes] [--dry-run]

OPTIONS
  -v, --vpath REL     Virtual path to remove (required)
  -f, --file NAME     Conf filename under virtualpath.d/ (default: virtualpath.local.conf)
  -y, --yes           Do not prompt
  -n, --dry-run       Print actions only

ENV
  ZCONF_DIR           Config directory (default: /usr/local/etc/zmesh)

EXAMPLES
  ZCONF_DIR=/usr/local/etc/zmesh ./tools/remove-virtualpath.sh --vpath "hobby/car" --yes
EOF
}

VPATH=""
FILE="$DEFAULT_FILE"
YES=0
DRYRUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -v|--vpath) VPATH="${2:-}"; shift 2;;
    --vpath=*)  VPATH="${1#*=}"; shift 1;;
    -f|--file) FILE="${2:-}"; shift 2;;
    --file=*)  FILE="${1#*=}"; shift 1;;
    -y|--yes) YES=1; shift 1;;
    -n|--dry-run|--dryrun) DRYRUN=1; shift 1;;
    *) die "unknown arg: $1 (use --help)";;
  esac
done

[ -n "$VPATH" ] || { usage; die "--vpath is required"; }

VPATH=$(printf "%s" "$VPATH" | sed 's#^[ /]*##; s#//*#/#g; s#/*$##')
[ -n "$VPATH" ] || die "vpath becomes empty after normalization"

CONF_PATH="$CONF_DIR/$FILE"
[ -f "$CONF_PATH" ] || die "missing file: $CONF_PATH"

confirm() {
  [ "$YES" -eq 1 ] && return 0
  printf "%s [y/N]: " "$1"
  read ans || true
  case "$ans" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

confirm "Remove vpath '$VPATH' from $CONF_PATH ?" || die "aborted"

TMP="${TMPDIR:-/tmp}/zmesh-vpath-rm.$$"
trap 'rm -rf "$TMP" >/dev/null 2>&1 || true' EXIT INT TERM
mkdir -p "$TMP"
OUT="$TMP/out.conf"

removed=0
awk -v vp="$VPATH" '
function is_hdr(line,   m){ return match(line, /^\[vpath[ \t]+"([^"]+)"\][ \t]*$/, m) && m[1]==vp }
BEGIN{ skip=0; removed=0 }
{
  line=$0
  if (is_hdr(line)) { skip=1; removed=1; next }
  if (skip && match(line, /^\[vpath[ \t]+"([^"]+)"\][ \t]*$/)) { skip=0 }
  if (!skip) print $0
}
END{ if (removed==0) exit 3 }
' "$CONF_PATH" > "$OUT" || rc=$? || true

# awk exit 3 means "not found"
if [ "${rc:-0}" -eq 3 ]; then
  say "(not found) vpath=$VPATH in $CONF_PATH"
  exit 0
fi

if [ "$DRYRUN" -eq 1 ]; then
  say "DRYRUN write: $CONF_PATH"
  say "-----"
  cat "$OUT"
  say "-----"
  exit 0
fi

tmpf="$CONF_PATH.tmp"
cp "$OUT" "$tmpf"
mv "$tmpf" "$CONF_PATH"

say "OK removed: vpath=$VPATH (file=$CONF_PATH)"
exit 0