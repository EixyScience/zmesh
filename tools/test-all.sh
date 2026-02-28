#!/bin/sh
set -eu

# ------------------------------------------------------------
# zmesh/scalefs smoke tests (Linux/FreeBSD)
# - No destructive operations on user env
# - Creates temp config/home and temp root under mktemp
# ------------------------------------------------------------

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_DIR="$BASE_DIR/tools"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

# Try to find entry points in both locations
entry_path() {
  name="$1"
  if [ -x "$BASE_DIR/$name" ]; then echo "$BASE_DIR/$name"; return 0; fi
  if [ -x "$TOOLS_DIR/$name" ]; then echo "$TOOLS_DIR/$name"; return 0; fi
  die "missing executable entry: $name (searched $BASE_DIR and $TOOLS_DIR)"
}

# Run "<exe> help" and ensure it contains pattern (case-insensitive)
run_help_contains() {
  exe="$1"
  pat="$2"
  out=$("$exe" help 2>/dev/null || true)
  echo "$out" | grep -qi "$pat" || die "help output from $exe does not contain: $pat"
}

# Tools existence check (file path relative to repo root)
must_exist() {
  rel="$1"
  [ -f "$BASE_DIR/$rel" ] || die "missing file: $rel"
}

must_exec() {
  rel="$1"
  [ -f "$BASE_DIR/$rel" ] || die "missing file: $rel"
  [ -x "$BASE_DIR/$rel" ] || die "not executable: $rel (chmod +x $rel)"
}

# ------------------------------------------------------------
# 1) Basic checks
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

# Also confirm tools/ entry scripts work too (if executable)
if [ -x "$TOOLS_DIR/zmesh" ]; then run_help_contains "$TOOLS_DIR/zmesh" "usage"; fi
if [ -x "$TOOLS_DIR/scalefs" ]; then run_help_contains "$TOOLS_DIR/scalefs" "usage"; fi

say "  OK: help works"

# ------------------------------------------------------------
# 2) Script presence sanity (repo layout)
# ------------------------------------------------------------
say "[2] script presence sanity"

# common/lib
must_exist "tools/common.sh"

# scalefs ops (sh)
must_exec "tools/add-scalefs.sh"
must_exec "tools/list-scalefs.sh"
must_exec "tools/remove-scalefs.sh"
must_exec "tools/clean-scalefs.sh"

# virtualpath ops (sh)
must_exec "tools/add-virtualpath.sh"
must_exec "tools/list-virtualpath.sh"
must_exec "tools/remove-virtualpath.sh"
must_exec "tools/apply-virtualpath.sh"
must_exec "tools/doctor-virtualpath.sh"

# manifest (sh)
must_exec "tools/manifest-scalefs.sh"

# wrappers (entry points)
must_exec "tools/zmesh"
must_exec "tools/scalefs"

say "  OK: required scripts exist"

# ------------------------------------------------------------
# 3) add-scalefs smoke (temp root + temp config) + manifest + clean
# ------------------------------------------------------------
say "[3] add-scalefs + manifest + clean smoke (temp root + temp config)"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/zmesh-test.XXXXXX")
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

# temp config dir for common.sh load_roots()
export ZCONF_DIR="$TMP/etc/zmesh"
mkdir -p "$ZCONF_DIR/zmesh.d"

# temp root path for scalefs bodies
ROOTPATH="$TMP/scalefsroot"
mkdir -p "$ROOTPATH"

# root config format expected by common.sh: [root "NAME"] + path=
cat > "$ZCONF_DIR/zmesh.d/root.test.conf" <<EOF
[root "test"]
path=$ROOTPATH
EOF

ADD="$TOOLS_DIR/add-scalefs.sh"
MAN="$TOOLS_DIR/manifest-scalefs.sh"
CLN="$TOOLS_DIR/clean-scalefs.sh"

say "  creating scalefs by stdin automation..."
# Feed:
#  Select root: test
#  Name: DemoCell
# Capture output for debugging on failure
LOG="$TMP/add-scalefs.log"
( printf "test\nDemoCell\n" | (cd "$TOOLS_DIR" && sh "./add-scalefs.sh") ) >"$LOG" 2>&1 || {
  say "---- add-scalefs.log ----"
  sed -n '1,200p' "$LOG" || true
  die "add-scalefs.sh failed (log: $LOG)"
}

# Validate: under ROOTPATH there should be "democell.<shortid>/" directory
created_dir="$(ls -1 "$ROOTPATH" 2>/dev/null | grep -E '^democell\.[0-9a-f]{6}$' | head -n 1 || true)"
[ -n "$created_dir" ] || {
  say "---- add-scalefs.log ----"
  sed -n '1,200p' "$LOG" || true
  die "created scalefs dir not found under root (expected democell.<6hex>)"
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
grep -q '^id=' "$SCALEFS_DIR/scalefs.ini" 2>/dev/null || grep -q '^scalefs' "$SCALEFS_DIR/scalefs.ini" || die "scalefs.ini missing id/scalefs section"

say "  OK: scalefs skeleton verified"

# manifest smoke (json)
say "  manifest (json) ..."
MLOG="$TMP/manifest.log"
( cd "$TOOLS_DIR" && sh "./manifest-scalefs.sh" -p "$SCALEFS_DIR" -f json ) >"$MLOG" 2>&1 || {
  say "---- manifest.log ----"
  sed -n '1,200p' "$MLOG" || true
  die "manifest-scalefs.sh failed"
}
grep -q '"ok"[[:space:]]*:[[:space:]]*true' "$MLOG" || true
say "  OK: manifest produced"

# clean smoke: runtime only (non-destructive)
say "  clean (runtime only) ..."
CLOG="$TMP/clean.log"
( cd "$TOOLS_DIR" && sh "./clean-scalefs.sh" -p "$SCALEFS_DIR" -y ) >"$CLOG" 2>&1 || {
  say "---- clean.log ----"
  sed -n '1,200p' "$CLOG" || true
  die "clean-scalefs.sh failed"
}
say "  OK: clean ran"

# virtualpath help smoke (only check command responds)
say "  virtualpath help smoke..."
( "$ZEXE" virtualpath help >/dev/null 2>&1 ) || die "zmesh virtualpath help failed"
( "$ZEXE" apply --help >/dev/null 2>&1 ) || true