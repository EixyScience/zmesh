#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
NODE_ID="${2:-node-01}"
SITE="${3:-site-a}"

[[ -z "$ROOT" ]] && { echo "usage: $0 <zmesh_root_dir> [node_id] [site]" >&2; exit 2; }

mkdir -p "$ROOT/scalefs.d" "$ROOT/access.d"

CONF="$ROOT/zmesh.conf"
if [[ ! -f "$CONF" ]]; then
cat >"$CONF" <<EOF
[node]
id = ${NODE_ID}
site = ${SITE}

[lan]
udp_listen = 0.0.0.0:48080
udp_peers  =

[wan]
enabled = true
listen  = 0.0.0.0:48443
peers   = http://127.0.0.1:48443

[role]
prime = false
governor = true

[scalefs]
id =

# NOTE:
# scalefs の列挙・配置は将来 scalefs.d/ に切り出す。
EOF
fi

echo "ok: initialized zmesh root = $ROOT"
echo "config: $CONF"