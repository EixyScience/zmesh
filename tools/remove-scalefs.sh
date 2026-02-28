#!/bin/sh
set -eu
. ./common.sh

printf "Name: "
read NAME

load_roots | while IFS='|' read alias path
do

DIR="$path/$NAME"

if [ -d "$DIR" ]; then
rm -rf "$DIR"
echo removed
fi

done