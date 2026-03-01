param(
  [Parameter(Mandatory=$true)][string]$ScalefsRoot,
  [Parameter(Mandatory=$true)][string]$Name,
  [switch]$NoShortId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Normalize-Name([string]$s) {
  $t = $s.Trim().ToLowerInvariant()
  if ($t -eq "") { return "scalefs" }

  # separators -> dot, spaces -> dash
  $t = $t -replace "[\\/:;,]+", "."
  $t = $t -replace "\s+", "-"

  # allow a-z 0-9 . _ -
  $t = $t -replace "[^a-z0-9\.\_\-]", ""

  # collapse dots
  while ($t.Contains("..")) { $t = $t.Replace("..", ".") }

  $t = $t.Trim(".","-","_")
  if ($t -eq "") { $t = "scalefs" }
  return $t
}

function New-ShortId([int]$len = 6) {
  $alphabet = "abcdefghijklmnopqrstuvwxyz234567"
  $bytes = New-Object byte[] ($len)
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $chars = for ($i=0; $i -lt $len; $i++) { $alphabet[ $bytes[$i] % $alphabet.Length ] }
  -join $chars
}

$root = (Resolve-Path $ScalefsRoot).Path
$norm = Normalize-Name $Name
$short = if ($NoShortId) { "" } else { New-ShortId 6 }
$finalName = if ($short -eq "") { $norm } else { "$norm.$short" }

$sf = Join-Path $root $finalName

if (Test-Path -LiteralPath $sf) {
  throw "already exists: $sf"
}

Ensure-Dir $sf
Ensure-Dir (Join-Path $sf "main")
Ensure-Dir (Join-Path $sf "scalefs.runtime.d\scalefs.state")
Ensure-Dir (Join-Path $sf "scalefs.local.d")
Ensure-Dir (Join-Path $sf "scalefs.global.d")

$iniPath = Join-Path $sf "scalefs.ini"
@"
[paths]
main = ./main
state_dir = ./scalefs.runtime.d/scalefs.state
watch_root = ./main
watch_exclude = ./scalefs.runtime.d/**, ./scalefs.local.d/**, .shadow/**, .latest/**, .tmp/**, .snapshot/**, .git/**
"@ | Set-Content -Encoding UTF8 -NoNewline $iniPath

$gitignore = Join-Path $sf ".gitignore"
@"
scalefs.runtime.d/
scalefs.local.d/
.shadow/
.latest/
.tmp/
.snapshot/
"@ | Set-Content -Encoding UTF8 -NoNewline $gitignore

Write-Host "ok: created scalefs=$finalName"
Write-Host "path: $sf"
Write-Host "watch_root: $(Join-Path $sf 'main')"