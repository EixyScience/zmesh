#!/bin/sh
set -eu
. ./common.sh

resolve_root_path | while IFS='|' read alias path
do

for d in "$path"/*
do
[ -d "$d/main" ] || continue
echo "$alias : $(basename "$d")"
done

done