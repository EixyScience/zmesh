#!/bin/sh
set -eu

# manifest-scalefs.sh
# - Emits a manifest of main/ contents for a scalefs body directory.
# - Supports non-interactive usage.
#
# Requires: sh, find, awk, sed, tr, date, stat (or fallback), and optional hash tools.

. ./common.sh

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

usage() {
cat <<'EOF'
manifest - emit a manifest of main/ (file list + metadata)

USAGE
  scalefs manifest [options]

COMMAND + OPTIONS
  scalefs manifest -p, --path DIR
      Use explicit scalefs body directory (contains scalefs.ini and main/)

  scalefs manifest -i, --id ID
      Resolve scalefs body directory by ID (name.shortid) via registered roots

  scalefs manifest -o, --out FILE
      Write to FILE (default: DIR/scalefs.manifest)

  scalefs manifest --stdout
      Write to stdout

  scalefs manifest --hash none|sha1|sha256
      Hash algorithm (default: sha256 if available, else sha1, else none)

  scalefs manifest --no-hash
      Same as --hash none

  scalefs manifest -h, --help
      Show this help

EXAMPLES
  scalefs manifest -p /mnt/zmtest/scalefsroot/democell.17ded8
  scalefs manifest -i democell.17ded8 --stdout
  scalefs manifest -i democell.17ded8 -o ./out.manifest --hash sha1
EOF
}

# -------------------------
# resolve scalefs body dir
# -------------------------
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

# -------------------------
# stat helpers (portable-ish)
# -------------------------
file_size() {
  # prints size in bytes
  f="$1"
  if command -v stat >/dev/null 2>&1; then
    # GNU stat
    if stat -c %s "$f" >/dev/null 2>&1; then
      stat -c %s "$f"
      return 0
    fi
    # BSD stat
    if stat -f %z "$f" >/dev/null 2>&1; then
      stat -f %z "$f"
      return 0
    fi
  fi
  # fallback: wc -c
  wc -c <"$f" | tr -d ' '
}

file_mtime() {
  # prints mtime as unix seconds
  f="$1"
  if command -v stat >/dev/null 2>&1; then
    # GNU stat
    if stat -c %Y "$f" >/dev/null 2>&1; then
      stat -c %Y "$f"
      return 0
    fi
    # BSD stat
    if stat -f %m "$f" >/dev/null 2>&1; then
      stat -f %m "$f"
      return 0
    fi
  fi
  # fallback: date -r (BSD) or perl
  if date -r "$f" +%s >/dev/null 2>&1; then
    date -r "$f" +%s
    return 0
  fi
  perl -e 'print((stat($ARGV[0]))[9],"\n")' "$f" 2>/dev/null || echo 0
}

# -------------------------
# hash helper
# -------------------------
pick_hash() {
  req="$1"
  if [ "$req" = "none" ]; then echo "none"; return 0; fi
  if [ "$req" = "sha256" ]; then
    if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1; then
      echo "sha256"; return 0
    fi
    echo "none"; return 0
  fi
  if [ "$req" = "sha1" ]; then
    if command -v sha1sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1; then
      echo "sha1"; return 0
    fi
    echo "none"; return 0
  fi

  # auto
  if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1; then
    echo "sha256"; return 0
  fi
  if command -v sha1sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1; then
    echo "sha1"; return 0
  fi
  echo "none"
}

do_hash() {
  algo="$1"
  f="$2"
  case "$algo" in
    none) echo "-" ;;
    sha256)
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk '{print $1}'
      elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" | awk '{print $1}'
      elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$f" | awk '{print $2}'
      else
        echo "-"
      fi
      ;;
    sha1)
      if command -v sha1sum >/dev/null 2>&1; then
        sha1sum "$f" | awk '{print $1}'
      elif command -v shasum >/dev/null 2>&1; then
        shasum -a 1 "$f" | awk '{print $1}'
      elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha1 "$f" | awk '{print $2}'
      else
        echo "-"
      fi
      ;;
    *) echo "-" ;;
  esac
}

# -------------------------
# args
# -------------------------
DIR=""
ID=""
OUT=""
STDOUT=0
HASHREQ="auto"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -p|--path) DIR="${2:-}"; shift 2 ;;
    -i|--id)   ID="${2:-}"; shift 2 ;;
    -o|--out)  OUT="${2:-}"; shift 2 ;;
    --stdout)  STDOUT=1; shift 1 ;;
    --hash)    HASHREQ="${2:-auto}"; shift 2 ;;
    --no-hash) HASHREQ="none"; shift 1 ;;
    *) die "unknown arg: $1 (use --help)" ;;
  esac
done

if [ -z "$DIR" ]; then
  if [ -n "$ID" ]; then
    DIR="$(resolve_by_id "$ID" || true)"
    [ -n "$DIR" ] || die "cannot resolve id: $ID (check roots in $ZCONF_DIR/zmesh.d)"
  else
    DIR="."
  fi
fi

[ -d "$DIR" ] || die "no such dir: $DIR"
[ -f "$DIR/scalefs.ini" ] || die "not a scalefs body (missing scalefs.ini): $DIR"
[ -d "$DIR/main" ] || die "missing main/: $DIR/main"

MAIN="$DIR/main"

ALGO="$(pick_hash "$HASHREQ")"

if [ "$STDOUT" -eq 1 ]; then
  OUTFILE="/dev/stdout"
else
  if [ -n "$OUT" ]; then
    OUTFILE="$OUT"
  else
    OUTFILE="$DIR/scalefs.manifest"
  fi
fi

# -------------------------
# emit
# -------------------------
# format: relpath<TAB>size<TAB>mtime_unix<TAB>hash_or_dash
# excludes: none (only main/ is scanned)
#
# Important: stable ordering (LC_ALL=C sort)
(
  say "# scalefs manifest"
  say "# body_dir=$DIR"
  say "# main_dir=$MAIN"
  say "# hash=$ALGO"
  say "# generated_unix=$(date +%s)"
  say "# format: path<TAB>size<TAB>mtime_unix<TAB>hash"

  # find files under main (ignore dirs)
  # -print0 is not POSIX; keep simple and assume "reasonable" filenames for now.
  find "$MAIN" -type f 2>/dev/null \
    | sed "s|^$MAIN/||" \
    | LC_ALL=C sort \
    | while IFS= read -r rel; do
        f="$MAIN/$rel"
        sz="$(file_size "$f")"
        mt="$(file_mtime "$f")"
        hs="$(do_hash "$ALGO" "$f")"
        printf "%s\t%s\t%s\t%s\n" "$rel" "$sz" "$mt" "$hs"
      done
) >"$OUTFILE"

if [ "$STDOUT" -ne 1 ]; then
  say "OK: wrote $OUTFILE"
fi