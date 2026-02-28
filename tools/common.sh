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
    # 最終手段（衝突リスクは上がる）
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

command -v zfs >/dev/null 2>&1
}

load_roots() {

for f in "$ZCONF_DIR"/zmesh.d/*.conf
do

[ -f "$f" ] || continue

awk '
/^\[root "/ {
gsub(/^\[root "/,"")
gsub(/"\]/,"")
name=$0
}

/^path=/ {
path=substr($0,6)
print name "|" path
}
' "$f"

done

}