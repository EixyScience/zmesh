#!/bin/sh
set -eu
. ./common.sh

load_roots | while IFS='|' read alias path
do

for d in "$path"/*
do
[ -d "$d/main" ] || continue
echo "$alias : $(basename "$d")"
done

done