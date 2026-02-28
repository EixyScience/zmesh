#!/usr/bin/env bash

#usage:
#chmod +x ./init-scalefs.sh
#./init-scalefs.sh /mnt/zmtest/zmesh

set -euo pipefail

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
echo "usage: $0 <scalefs_root_dir>" >&2
exit 2
fi

mkdir -p "$ROOT/main" \
"$ROOT/scalefs.runtime.d/scalefs.state" \
"$ROOT/scalefs.local.d" \
"$ROOT/scalefs.global.d"

INI="$ROOT/scalefs.ini"
if [[ ! -f "$INI" ]]; then
cat >"$INI" <<'EOF'
[paths]
main = ./main
state_dir = ./scalefs.runtime.d/scalefs.state
watch_root = ./main
watch_exclude = ./scalefs.runtime.d/**, ./scalefs.local.d/**, .shadow/**, .latest/**, .tmp/**, .snapshot/**, .git/**
EOF
fi

GI="$ROOT/.gitignore"
if [[ ! -f "$GI" ]]; then
cat >"$GI" <<'EOF'
# scalefs runtime/local state (per-node / ephemeral)
scalefs.runtime.d/
scalefs.local.d/
# generic internal working dirs
.shadow/
.latest/
.tmp/
.snapshot/
EOF
fi

echo "ok: initialized scalefs root = $ROOT"