#!/bin/sh
set -eu

NAME=""
AUTO_YES=0

while [ $# -gt 0 ]; do
case "$1" in

-n|--name)
NAME="$2"
shift 2
;;

-y|--yes)
AUTO_YES=1
shift
;;

*)
echo "Usage: remove-scalefs.sh -n name"
exit 1
;;
esac
done

[ -n "$NAME" ] || {
echo "Name required"
exit 1
}

FOUND=""

for root in $(list-scalefs.sh | awk '{print $3}')
do

if [ "$root" = "$NAME" ]; then
FOUND="$root"
fi

done

[ -n "$FOUND" ] || {
echo "Not found"
exit 1
}

if [ "$AUTO_YES" -eq 0 ]; then
printf "Delete $FOUND? [y/N]: "
read ans
case "$ans" in y|Y) ;; *) exit 0 ;; esac
fi

rm -rf "$FOUND"

echo "Removed $FOUND"