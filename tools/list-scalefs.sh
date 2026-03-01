#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TOOLS_DIR/common.sh"

resolve_root_path | while IFS='|' read alias path
do

for d in "$path"/*
do
[ -d "$d/main" ] || continue
echo "$alias : $(basename "$d")"
done

done
