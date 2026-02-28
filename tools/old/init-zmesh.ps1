param([string]$Root = ".")

$conf = Join-Path $Root "zmesh.conf"
$vpd  = Join-Path $Root "vpaths.d"

New-Item -ItemType Directory -Force -Path $Root | Out-Null
New-Item -ItemType Directory -Force -Path $vpd  | Out-Null

if (-not (Test-Path $conf)) {
@"
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
# scalefs 本体は add-scalefs で作成し、virtual path は vpaths.d で扱う。
"@ | Set-Content -Encoding UTF8 $conf
}

$sample = Join-Path $vpd "sample.ini"
if (-not (Test-Path $sample)) {
@"
# vpaths.d/*.ini
# 将来: controller/view が読む “virtual path” 定義。
"@ | Set-Content -Encoding UTF8 $sample
}

Write-Host "ok: created $conf and $vpd"