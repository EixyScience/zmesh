#!/bin/sh
set -eu

ROOT="${1:-.}"
CONF="$ROOT/zmesh.conf"
VPD="$ROOT/vpaths.d"

mkdir -p "$ROOT" "$VPD"

if [ ! -f "$CONF" ]; then
cat > "$CONF" <<'EOF'
[node]
id = node-01
site = site-a

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

# NOTE:
# scalefs 本体（scalefs.ini など）は別途 add-scalefs で作成し、
# その scalefs をどう束ねて見せるかを vpaths.d で扱う（将来のcontroller/view）。
EOF
fi

# sample vpaths
SAMPLE="$VPD/sample.ini"
if [ ! -f "$SAMPLE" ]; then
cat > "$SAMPLE" <<'EOF'
# vpaths.d/*.ini
# 将来: controller/view が読む “virtual path” 定義。
# 例:
# [vpath "work"]
# target = /mnt/zmtest/zmesh/body.organ.tissue.cell.ab12cd/main
EOF
fi

echo "ok: created $CONF and $VPD"