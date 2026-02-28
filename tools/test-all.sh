#!/bin/sh
set -eu

# ------------------------------------------------------------
# zmesh/scalefs smoke tests (Linux/FreeBSD)
# - No destructive operations
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

run_help_contains() {
  exe="$1"
  pat="$2"
  out=$("$exe" help 2>/dev/null || true)
  echo "$out" | grep -qi "$pat" || die "help output from $exe does not contain: $pat"
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
# 2) Root config + add-scalefs smoke (stdin-driven)
# ------------------------------------------------------------
say "[2] add-scalefs smoke (temp root + temp config)"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/zmesh-test.XXXXXX")

created_dir=""
cleanup() {
  # If scalefs was created, remove via tool (handles zfs destroy via marker)
  if [ -n "$created_dir" ]; then
    # remove-scalefs.sh is interactive; feed name via stdin
    printf "%s\n" "$created_dir" | (cd "$TOOLS_DIR" && sh ./remove-scalefs.sh) >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP" >/dev/null 2>&1 || true
}
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

# run add-scalefs.sh from tools (it uses ". ./common.sh")
ADD="$TOOLS_DIR/add-scalefs.sh"
[ -f "$ADD" ] || die "missing: $ADD"
[ -x "$ADD" ] || die "not executable: $ADD (chmod +x tools/add-scalefs.sh)"

# Feed answers:
#  - Select root: test
#  - Name: DemoCell
say "  creating scalefs by stdin automation..."
printf "test\nDemoCell\n" | (cd "$TOOLS_DIR" && sh "./add-scalefs.sh") >/dev/null 2>&1 || die "add-scalefs.sh failed"

# Validate: under ROOTPATH there should be "democell.<shortid>/" directory
created_dir="$(ls -1 "$ROOTPATH" 2>/dev/null | grep -E '^democell\.[0-9a-f]{6}$' | head -n 1 || true)"
[ -n "$created_dir" ] || die "created scalefs dir not found under root (expected democell.<6hex>)"

SCALEFS_DIR="$ROOTPATH/$created_dir"
say "  created: $SCALEFS_DIR"

# Validate required skeleton
[ -d "$SCALEFS_DIR/main" ] || die "missing main/"
[ -d "$SCALEFS_DIR/scalefs.state" ] || die "missing scalefs.state/"
[ -d "$SCALEFS_DIR/scalefs.global.d" ] || die "missing scalefs.global.d/"
[ -d "$SCALEFS_DIR/scalefs.local.d" ] || die "missing scalefs.local.d/"
[ -d "$SCALEFS_DIR/scalefs.runtime.d" ] || die "missing scalefs.runtime.d/"
[ -f "$SCALEFS_DIR/scalefs.ini" ] || die "missing scalefs.ini"

# Validate scalefs.ini contains id=...
grep -q '^id=' "$SCALEFS_DIR/scalefs.ini" || die "scalefs.ini missing id="

say "  OK: scalefs skeleton verified"

say "ALL OK"