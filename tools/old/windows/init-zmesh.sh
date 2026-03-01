param(
  [Parameter(Mandatory=$true)][string]$Root,          # zmesh作業ディレクトリ
  [string]$NodeId = "node-01",
  [string]$Site = "site-a",
  [string]$WanListen = "0.0.0.0:48443",
  [string]$LanListen = "0.0.0.0:48080",
  [string]$Peers = "http://127.0.0.1:48443",
  [string]$ScaleFsId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

$root = (Resolve-Path $Root).Path
Ensure-Dir $root
Ensure-Dir (Join-Path $root "scalefs.d")
Ensure-Dir (Join-Path $root "access.d")

$conf = Join-Path $root "zmesh.conf"
if (-not (Test-Path -LiteralPath $conf)) {
@"
[node]
id = $NodeId
site = $Site

[lan]
udp_listen = $LanListen
udp_peers  =

[wan]
enabled = true
listen  = $WanListen
peers   = $Peers

[role]
prime = false
governor = true

[scalefs]
id = $ScaleFsId

# NOTE:
# zmesh.conf は “agent自身の設定”。
# scalefs の本体配置・複数列挙は scalefs.d/（将来の include）で扱う。
"@ | Set-Content -Encoding UTF8 -NoNewline $conf
}

Write-Host "ok: initialized zmesh root = $root"
Write-Host "config: $conf"