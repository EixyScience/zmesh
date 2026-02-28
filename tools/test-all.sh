#!/bin/sh
set -eu

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_DIR="$BASE_DIR/tools"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

entry_path() {
  name="$1"
  if [ -x "$BASE_DIR/$name" ]; then echo "$BASE_DIR/$name"; return 0; fi
  if [ -x "$TOOLS_DIR/$name" ]; then echo "$TOOLS_DIR/$name"; return 0; fi
  die "missing executable entry: $name (searched $BASE_DIR and $TOOLS_DIR)"
}

run_help_contains() {
  exe="$1"
  pat="$2"
  out=$("$exe" help 2>/dev/null || true)
  echo "$out" | grep -qi "$pat" || die "help output from $exe does not contain: $pat"
}

# ------------------------------------------------------------
say "[1] basic checks"
need_cmd sh
need_cmd grep
need_cmd awk
need_cmd sed
need_cmd tr
need_cmd date
need_cmd mkdir
need_cmd rm
need_cmd mktemp

ZEXE=$(entry_path zmesh)
SEXE=$(entry_path scalefs)

say "  zmesh:   $ZEXE"
say "  scalefs: $SEXE"

run_help_contains "$ZEXE" "usage"
run_help_contains "$SEXE" "usage"

# Tools entry (optional)
if [ -x "$TOOLS_DIR/zmesh" ]; then run_help_contains "$TOOLS_DIR/zmesh" "usage"; fi
if [ -x "$TOOLS_DIR/scalefs" ]; then run_help_contains "$TOOLS_DIR/scalefs" "usage"; fi

say "  OK: help works"

# ------------------------------------------------------------
say "[2] add-scalefs smoke (temp root + temp config)"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/zmesh-test.XXXXXX")
cleanup() { rm -rf "$TMP" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

export ZCONF_DIR="$TMP/etc/zmesh"
mkdir -p "$ZCONF_DIR/zmesh.d"

ROOTPATH="$TMP/scalefsroot"
mkdir -p "$ROOTPATH"

cat > "$ZCONF_DIR/zmesh.d/root.test.conf" <<EOF
[root "test"]
path=$ROOTPATH
EOF

ADD="$TOOLS_DIR/add-scalefs.sh"
[ -f "$ADD" ] || die "missing: $ADD"
[ -x "$ADD" ] || die "not executable: $ADD (chmod +x tools/add-scalefs.sh)"

say "  creating scalefs by stdin automation..."
printf "test\nDemoCell\n" | (cd "$TOOLS_DIR" && sh "./add-scalefs.sh") >/dev/null 2>&1 || die "add-scalefs.sh failed"

# Validate: under ROOTPATH there should be "democell.<something>/" directory
# Be tolerant: shortid length/charset can vary by platform/tool availability.
created_dir="$(
  ls -1 "$ROOTPATH" 2>/dev/null \
    | grep -E '^democell\.[a-z0-9._-]+$' \
    | head -n 1 || true
)"
[ -n "$created_dir" ] || {
  say "  debug: ROOTPATH listing:"
  ls -la "$ROOTPATH" 2>/dev/null || true
  die "created scalefs dir not found under root (expected democell.<id>)"
}

SCALEFS_DIR="$ROOTPATH/$created_dir"
say "  created: $SCALEFS_DIR"

# Validate required skeleton
[ -d "$SCALEFS_DIR/main" ] || die "missing main/"
[ -d "$SCALEFS_DIR/scalefs.state" ] || die "missing scalefs.state/"
[ -d "$SCALEFS_DIR/scalefs.global.d" ] || die "missing scalefs.global.d/"
[ -d "$SCALEFS_DIR/scalefs.local.d" ] || die "missing scalefs.local.d/"
[ -d "$SCALEFS_DIR/scalefs.runtime.d" ] || die "missing scalefs.runtime.d/"
[ -f "$SCALEFS_DIR/scalefs.ini" ] || die "missing scalefs.ini"

# Validate scalefs.ini contains id=... and matches directory name best-effort
ini_id="$(awk -F= '/^id=/{print $2; exit}' "$SCALEFS_DIR/scalefs.ini" 2>/dev/null || true)"
[ -n "$ini_id" ] || die "scalefs.ini missing id="
dir_base="$(basename "$SCALEFS_DIR")"
[ "$ini_id" = "$dir_base" ] || {
  say "  warn: scalefs.ini id ($ini_id) != dir name ($dir_base) (continuing)"
}

say "  OK: scalefs skeleton verified"

# ------------------------------------------------------------
say "[3] virtualpath smoke (conf add/list/apply(dry-run)/remove)"

# Ensure tools exist
for t in add-virtualpath.sh list-virtualpath.sh remove-virtualpath.sh doctor-virtualpath.sh apply-virtualpath.sh; do
  [ -f "$TOOLS_DIR/$t" ] || die "missing: tools/$t"
  [ -x "$TOOLS_DIR/$t" ] || die "not executable: tools/$t (chmod +x)"
done

# prepare vroot and vpath rule
VROOT="$TMP/vroot"
mkdir -p "$VROOT"

# conf dir
mkdir -p "$ZCONF_DIR/virtualpath.d"

# add vpath rule (non-interactive)
VP="hobby/car"
TARGET="$SCALEFS_DIR/main"
( cd "$TOOLS_DIR" && \
  ZCONF_DIR="$ZCONF_DIR" sh ./add-virtualpath.sh --vpath "$VP" --target "$TARGET" --yes ) >/dev/null

# list should contain it
out="$( (cd "$TOOLS_DIR" && ZCONF_DIR="$ZCONF_DIR" sh ./list-virtualpath.sh ) )"
echo "$out" | grep -q "$VP" || die "virtualpath list missing vpath=$VP"
echo "$out" | grep -q "$TARGET" || die "virtualpath list missing target=$TARGET"

# doctor should pass
( cd "$TOOLS_DIR" && ZCONF_DIR="$ZCONF_DIR" sh ./doctor-virtualpath.sh --check-targets ) >/dev/null || die "doctor-virtualpath failed"

# apply dry-run should succeed
( cd "$TOOLS_DIR" && ZCONF_DIR="$ZCONF_DIR" sh ./apply-virtualpath.sh --root "$VROOT" --dry-run --yes ) >/dev/null || die "apply-virtualpath dry-run failed"

# remove rule
( cd "$TOOLS_DIR" && \
  ZCONF_DIR="$ZCONF_DIR" sh ./remove-virtualpath.sh --vpath "$VP" --yes ) >/dev/null

# list should not contain it
out2="$( (cd "$TOOLS_DIR" && ZCONF_DIR="$ZCONF_DIR" sh ./list-virtualpath.sh ) )"
echo "$out2" | grep -q "$VP" && die "virtualpath remove failed: still present"

say "  OK: virtualpath skeleton verified"

say "ALL OK"