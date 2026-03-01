#!/bin/sh
set -eu

# ===============================
# zmesh add-scalefs unified tool
# POSIX sh compliant
# ===============================

ROOT_ALIAS=""
NAME=""
SHORTID=""
AUTO_YES=0
QUIET=0

usage() {
cat <<EOF
Usage:

  add-scalefs.sh [options]

Options:

  -r, --root NAME       scalefs root alias
  -n, --name NAME       scalefs name
  -i, --id ID           short id override
  -y, --yes             automatic yes
  -q, --quiet           non-interactive
  -h, --help            show help

Examples:

  add-scalefs.sh
  add-scalefs.sh -r fast -n photos
  add-scalefs.sh --root archive --name backup -y

EOF
exit 0
}

# ---------- parse args ----------

while [ $# -gt 0 ]; do

case "$1" in

-r|--root)
ROOT_ALIAS="$2"
shift 2
;;

-n|--name)
NAME="$2"
shift 2
;;

-i|--id)
SHORTID="$2"
shift 2
;;

-y|--yes)
AUTO_YES=1
shift
;;

-q|--quiet)
QUIET=1
shift
;;

-h|--help)
usage
;;

*)
echo "Unknown option: $1"
usage
;;

esac

done

# ---------- utils ----------

normalize() {

echo "$1" \
| tr '[:upper:]' '[:lower:]' \
| sed -E '
s/[\/\\]+/./g
s/[[:space:]]+/-/g
s/[^a-z0-9._-]+/-/g
s/[._-]{2,}/-/g
s/^[._-]+//
s/[._-]+$//
'
}

gen_shortid() {

dd if=/dev/urandom bs=1 count=32 2>/dev/null \
| tr -dc '23456789abcdefghjkmnpqrstuvwxyz' \
| head -c 6
}

detect_node() {

hostname | cut -d. -f1
}

detect_site() {

h="$(hostname)"

case "$h" in
*.*) echo "$h" | cut -d. -f2- ;;
*) echo default ;;
esac

}

# ---------- load roots ----------

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

[ -n "$ROOTS" ] || {
echo "No scalefs roots configured"
exit 1
}

# ---------- select root ----------

if [ -z "$ROOT_ALIAS" ]; then

if [ "$QUIET" -eq 1 ]; then
echo "Root required in quiet mode"
exit 1
fi

echo "Available roots:"

echo "$ROOTS" | awk -F'|' '{print NR ") " $1 " -> " $2}'

printf "Select root number: "
read sel

ROOT_ALIAS="$(echo "$ROOTS" | sed -n "${sel}p" | cut -d'|' -f1)"
ROOT_PATH="$(echo "$ROOTS" | sed -n "${sel}p" | cut -d'|' -f2)"

else

ROOT_PATH="$(echo "$ROOTS" | grep "^$ROOT_ALIAS|" | cut -d'|' -f2)"

fi

[ -n "$ROOT_PATH" ] || {
echo "Invalid root"
exit 1
}

# ---------- name ----------

if [ -z "$NAME" ]; then

if [ "$QUIET" -eq 1 ]; then
echo "Name required in quiet mode"
exit 1
fi

printf "Enter scalefs name: "
read NAME

fi

NAME_NORM="$(normalize "$NAME")"

# ---------- id ----------

if [ -z "$SHORTID" ]; then
SHORTID="$(gen_shortid)"
fi

FINAL_NAME="${NAME_NORM}.${SHORTID}"

SC_PATH="${ROOT_PATH}/${FINAL_NAME}"

# ---------- confirm ----------

if [ "$AUTO_YES" -eq 0 ] && [ "$QUIET" -eq 0 ]; then

echo
echo "Create scalefs:"
echo " root : $ROOT_ALIAS"
echo " name : $FINAL_NAME"
echo " path : $SC_PATH"
echo

printf "Confirm? [Y/n]: "
read ans

case "$ans" in
n|N)
exit 0
;;
esac

fi

# ---------- create ----------

mkdir -p "$SC_PATH"

mkdir -p \
"$SC_PATH/main" \
"$SC_PATH/scalefs.state" \
"$SC_PATH/scalefs.global.d" \
"$SC_PATH/scalefs.local.d" \
"$SC_PATH/scalefs.runtime.d"

# ---------- write config ----------

cat > "$SC_PATH/scalefs.ini" <<EOF
[node]
node=$(detect_node)
site=$(detect_site)

[paths]
watch_root=./main
state_dir=./scalefs.state

[include]
global=./scalefs.global.d/*.ini
local=./scalefs.local.d/*.ini
runtime=./scalefs.runtime.d/*.ini
EOF

# ---------- optional zfs ----------

if command -v zfs >/dev/null 2>&1; then

DATASET="${ROOT_ALIAS}/${FINAL_NAME}"

if ! zfs list "$DATASET" >/dev/null 2>&1; then

echo "Creating ZFS dataset $DATASET"

zfs create \
-o mountpoint="$SC_PATH/main" \
"$DATASET"

fi

fi

echo
echo "Scalefs created:"
echo " $SC_PATH"
echo