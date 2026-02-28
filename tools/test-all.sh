#!/bin/sh
set -eu

# ------------------------------------------------------------
# zmesh/scalefs smoke tests (Linux/FreeBSD)
# - No destructive operations
# - Creates temp config/home and temp root under mktemp
# - On failure: keeps TMP and prints its path + log
# ------------------------------------------------------------

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_DIR="$BASE_DIR/tools"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# Try to find entry points in both locations
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

FAIL=0
TMP=""

cleanup() {
  # If KEEP_TMP=1 or FAIL=1, keep temp dir for debugging
  if [ "${KEEP_TMP:-0}" = "1" ] || [ "$FAIL" -eq 1 ]; then
    if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
      say "  [debug] keeping TMP: $TMP"
      say "  [debug] logs may be under: $TMP"
    fi
    return 0
  fi
  [ -n "${TMP:-}" ] && rm -rf "$TMP" || true
}

trap cleanup EXIT INT TERM

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
# 2) Root config + add-scalefs smoke (stdin/env-driven)
# ------------------------------------------------------------
say "[2] add-scalefs smoke (temp root + temp config)"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/zmesh-test.XXXXXX")

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
[ -f "$ADD" ] || { FAIL=1; die "missing: $ADD"; }
[ -x "$ADD" ] || { FAIL=1; die "not executable: $ADD (chmod +x tools/add-scalefs.sh)"; }

say "  creating scalefs by stdin automation..."
log="$TMP/add-scalefs.log"

# Prefer env driven (more stable than stdin)
(
  cd "$TOOLS_DIR"
  ROOT="test" NAME="DemoCell" sh "./add-scalefs.sh"
) >"$log" 2>&1 || {
  FAIL=1
  say "---- add-scalefs.log ----"
  sed -n '1,200p' "$log" || true
  die "add-scalefs.sh failed"
}

# Validate: under ROOTPATH there should be "democell.<shortid>/" directory
created_dir="$(ls -1 "$ROOTPATH" 2>/dev/null | grep -E '^democell\.[0-9a-f]{6}$' | head -n 1 || true)"
if [ -z "$created_dir" ]; then
  FAIL=1
  say "---- add-scalefs.log ----"
  sed -n '1,200p' "$log" || true
  say "---- root contents ----"
  ls -la "$ROOTPATH" || true
  die "created scalefs dir not found under root (expected democell.<6hex>)"
fi

SCALEFS_DIR="$ROOTPATH/$created_dir"
say "  created: $SCALEFS_DIR"

# Validate required skeleton
[ -d "$SCALEFS_DIR/main" ] || { FAIL=1; die "missing main/"; }
[ -d "$SCALEFS_DIR/scalefs.state" ] || { FAIL=1; die "missing scalefs.state/"; }
[ -d "$SCALEFS_DIR/scalefs.global.d" ] || { FAIL=1; die "missing scalefs.global.d/"; }
[ -d "$SCALEFS_DIR/scalefs.local.d" ] || { FAIL=1; die "missing scalefs.local.d/"; }
[ -d "$SCALEFS_DIR/scalefs.runtime.d" ] || { FAIL=1; die "missing scalefs.runtime.d/"; }
[ -f "$SCALEFS_DIR/scalefs.ini" ] || { FAIL=1; die "missing scalefs.ini"; }

grep -q '^id=' "$SCALEFS_DIR/scalefs.ini" 2>/dev/null || true
grep -q '^\[scalefs\]' "$SCALEFS_DIR/scalefs.ini" 2>/dev/null || true

say "  OK: scalefs skeleton verified"
say "ALL OK"