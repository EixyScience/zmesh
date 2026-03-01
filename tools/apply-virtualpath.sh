#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

# Apply virtual path rules into a vroot.
# - Builds a manifest: <vroot>/.zmesh/virtualpath.manifest
# - Optional clean: remove stale links under vroot that are not in manifest
#
# Config layout (recommended):
#   $ZCONF_DIR/virtualpath.d/*.conf
#
# Rule format (INI-ish, multiple [vpath "..."] blocks per file):
#   [vpath "hobby/car"]
#   target=/path/to/scalefs/main
#   type=symlink        # (optional) default=symlink
#
# Notes:
# - This script intentionally only creates directories and symlinks (no mounts).
# - Targets may be missing; we still create the link (dangling) unless --strict.

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_DIR="$BASE_DIR/tools"

# common.sh is optional; we only use ZCONF_DIR defaulting convention.
if [ -f "$TOOLS_DIR/common.sh" ]; then
  # shellcheck disable=SC1090
  . "$TOOLS_DIR/common.sh"
fi

ZCONF_DIR="${ZCONF_DIR:-/usr/local/etc/zmesh}"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# -------- args --------
VROOT=""
CLEAN=0
YES=0
STRICT=0
DRYRUN=0
MANIFEST_NAME="virtualpath.manifest"

usage() {
cat <<'EOF'
apply-virtualpath.sh - apply virtual path rules into a vroot

USAGE
  apply-virtualpath.sh --root <vroot> [--clean] [--yes] [--strict] [--dry-run]

OPTIONS
  -r, --root DIR     Virtual root directory to materialize virtual paths into (required)
  --clean            Remove stale links/dirs under vroot that are not present in manifest
  -y, --yes          Do not prompt (needed for --clean in non-interactive runs)
  --strict           Fail if a target does not exist
  -n, --dry-run      Print actions without modifying filesystem

ENV
  ZCONF_DIR           Config directory (default: /usr/local/etc/zmesh)
                      Reads: $ZCONF_DIR/virtualpath.d/*.conf

RULE FILE FORMAT
  [vpath "hobby/car"]
  target=/path/to/scalefs/main

EXAMPLES
  ZCONF_DIR=/usr/local/etc/zmesh ./tools/apply-virtualpath.sh --root /vroot
  ZCONF_DIR=/usr/local/etc/zmesh ./tools/apply-virtualpath.sh --root /vroot --clean --yes
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -r|--root) VROOT="${2:-}"; shift 2;;
    --root=*)  VROOT="${1#*=}"; shift 1;;
    --clean)   CLEAN=1; shift 1;;
    -y|--yes)  YES=1; shift 1;;
    --strict)  STRICT=1; shift 1;;
    -n|--dry-run|--dryrun) DRYRUN=1; shift 1;;
    *) die "unknown arg: $1 (use --help)";;
  esac
done

[ -n "$VROOT" ] || { usage; die "--root is required"; }

need_cmd awk
need_cmd sed
need_cmd tr
need_cmd mkdir
need_cmd rm
need_cmd find
need_cmd sort
need_cmd uniq

# FreeBSD: readlink may not have -f; we avoid it.
need_cmd ln

# -------- helpers --------
mkd() {
  [ "$DRYRUN" -eq 1 ] && { say "DRYRUN mkdir -p $1"; return 0; }
  mkdir -p "$1"
}

mklink() {
  tgt="$1"
  lnk="$2"
  # Replace existing file/link (but not a directory)
  if [ -e "$lnk" ] && [ ! -L "$lnk" ] && [ -d "$lnk" ]; then
    die "link path exists and is a directory: $lnk"
  fi
  if [ "$DRYRUN" -eq 1 ]; then
    say "DRYRUN ln -sfn '$tgt' '$lnk'"
    return 0
  fi
  ln -sfn "$tgt" "$lnk"
}

write_manifest_line() {
  rel="$1"
  tgt="$2"
  # Format: vpath|target
  printf "%s|%s\n" "$rel" "$tgt" >> "$MANIFEST_TMP"
}

confirm_clean() {
  [ "$CLEAN" -eq 1 ] || return 0
  if [ "$YES" -eq 1 ]; then
    return 0
  fi
  printf "Clean is enabled. Remove stale links under '%s'? [y/N]: " "$VROOT"
  read ans || true
  case "$ans" in
    y|Y|yes|YES) return 0;;
    *) die "aborted by user";;
  esac
}

# -------- parse rules --------
CONF_DIR="$ZCONF_DIR/virtualpath.d"
[ -d "$CONF_DIR" ] || die "missing config dir: $CONF_DIR (set ZCONF_DIR or create virtualpath.d/)"

# Build temp working directory
TMP="${TMPDIR:-/tmp}/zmesh-vpath.$$"
cleanup_tmp() { rm -rf "$TMP" >/dev/null 2>&1 || true; }
trap cleanup_tmp EXIT INT TERM
mkd "$TMP"

MANIFEST_DIR="$VROOT/.zmesh"
MANIFEST_PATH="$MANIFEST_DIR/$MANIFEST_NAME"
MANIFEST_TMP="$TMP/$MANIFEST_NAME.tmp"
MANIFEST_SET="$TMP/manifest.set"
LIVE_SET="$TMP/live.set"

mkd "$VROOT"
mkd "$MANIFEST_DIR"

# Generate manifest tmp by parsing *.conf
: > "$MANIFEST_TMP"

# AWK parser:
# - supports multiple [vpath "xxx"] blocks
# - reads target=... and emits when block completes or file ends
awk '
function trim(s){ gsub(/^[ \t\r\n]+/,"",s); gsub(/[ \t\r\n]+$/,"",s); return s }
BEGIN{ sec=""; vpath=""; target=""; }
{
  line=$0
  sub(/[ \r\t]+$/,"",line)
  if (line ~ /^[ \t]*([#;]|$)/) next

  if (match(line, /^\[vpath[ \t]+"([^"]+)"\][ \t]*$/, m)) {
    # flush previous
    if (vpath != "" && target != "") {
      print vpath "|" target
    }
    vpath=m[1]
    target=""
    next
  }

  if (vpath != "" && match(line, /^target[ \t]*=[ \t]*(.*)$/, m2)) {
    target=trim(m2[1])
    next
  }
}
END{
  if (vpath != "" && target != "") {
    print vpath "|" target
  }
}
' "$CONF_DIR"/*.conf 2>/dev/null >> "$MANIFEST_TMP" || true

# If no rules, still write empty manifest
# Normalize manifest: unique by vpath (last wins). We implement last-wins by reversing order.
if [ -s "$MANIFEST_TMP" ]; then
  # last wins: reverse lines then uniq by key, then reverse back
  # POSIX has no tac everywhere; emulate with awk.
  awk ' { a[NR]=$0 } END { for (i=NR;i>=1;i--) print a[i] }' "$MANIFEST_TMP" \
    | awk -F'|' '!seen[$1]++ {print}' \
    | awk ' { a[NR]=$0 } END { for (i=NR;i>=1;i--) print a[i] }' \
    > "$TMP/manifest.norm"
else
  : > "$TMP/manifest.norm"
fi

# Recreate MANIFEST_TMP from normalized output
cp "$TMP/manifest.norm" "$MANIFEST_TMP"

# -------- apply rules --------
say "[apply] root=$VROOT conf=$CONF_DIR clean=$CLEAN strict=$STRICT dryrun=$DRYRUN"

# Write manifest file atomically after apply.
# But we need a set of intended rel paths first.
: > "$MANIFEST_SET"

# Apply each line vpath|target
# vpath is relative path under vroot.
while IFS='|' read -r rel target
do
  [ -n "$rel" ] || continue
  [ -n "$target" ] || continue

  # Normalize rel: strip leading slashes and collapse // (lightweight)
  rel=$(printf "%s" "$rel" | sed 's#^/*##; s#//*#/#g')

  # Determine filesystem paths
  link_path="$VROOT/$rel"
  parent_dir=$(dirname "$link_path")

  # Ensure parent exists
  mkd "$parent_dir"

  # Strict mode: require target exists
  if [ "$STRICT" -eq 1 ] && [ ! -e "$target" ]; then
    die "target missing (strict): $target for vpath=$rel"
  fi

  mklink "$target" "$link_path"

  # record intended link relative path for cleaning
  printf "%s\n" "$rel" >> "$MANIFEST_SET"
done < "$MANIFEST_TMP"

# De-dup set
sort -u "$MANIFEST_SET" > "$TMP/manifest.set.u"
mv "$TMP/manifest.set.u" "$MANIFEST_SET"

# Write manifest file: include header for humans + machine lines
if [ "$DRYRUN" -eq 1 ]; then
  say "DRYRUN write manifest: $MANIFEST_PATH"
else
  tmpm="$MANIFEST_PATH.tmp"
  {
    printf "# zmesh virtualpath manifest\n"
    printf "# generated_unix=%s\n" "$(date +%s)"
    printf "# format: vpath|target\n"
    cat "$MANIFEST_TMP"
  } > "$tmpm"
  mv "$tmpm" "$MANIFEST_PATH"
fi

# -------- clean stale --------
if [ "$CLEAN" -eq 1 ]; then
  confirm_clean

  # Build LIVE_SET: all symlinks under vroot excluding .zmesh
  # We store relative paths from vroot
  (cd "$VROOT" && find . -type l 2>/dev/null | sed 's#^\./##' | grep -v '^\.zmesh/' || true) \
    | sort -u > "$LIVE_SET"

  # Determine stale links: in LIVE but not in manifest set
  # comm requires sorted lists
  STALE="$TMP/stale.set"
  comm -23 "$LIVE_SET" "$MANIFEST_SET" > "$STALE" || true

  if [ -s "$STALE" ]; then
    say "[clean] removing stale links:"
    while IFS= read -r rel
    do
      [ -n "$rel" ] || continue
      p="$VROOT/$rel"
      if [ "$DRYRUN" -eq 1 ]; then
        say "DRYRUN rm -f '$p'"
      else
        rm -f "$p" || true
      fi
    done < "$STALE"
  else
    say "[clean] no stale links"
  fi

  # Optionally prune empty directories (excluding .zmesh)
  # This is best-effort; do not remove vroot itself.
  if [ "$DRYRUN" -eq 1 ]; then
    say "DRYRUN prune empty dirs under '$VROOT' (excluding .zmesh)"
  else
    (cd "$VROOT" && find . -type d 2>/dev/null | grep -v '^\./\.zmesh$' | sort -r) \
      | while IFS= read -r d
        do
          [ "$d" = "." ] && continue
          [ "$d" = "./.zmesh" ] && continue
          rmdir "$d" 2>/dev/null || true
        done
  fi
fi

say "[ok] manifest=$MANIFEST_PATH"
exit 0