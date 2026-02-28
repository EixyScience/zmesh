#!/bin/sh
set -eu

load_roots() {

for f in \
/usr/local/etc/zmesh/zmesh.d/*.conf \
/etc/zmesh/zmesh.d/*.conf \
./zmesh.d/*.conf
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

ROOTS="$(load_roots)"

echo "Scalefs list:"
echo

echo "$ROOTS" | while IFS='|' read alias path
do

[ -d "$path" ] || continue

for d in "$path"/*
do
[ -d "$d/main" ] || continue
echo "$alias : $(basename "$d")"
done

done