# usage:
# .\init-scalefs.ps1 -Root C:\data\scalefs\car

param(
    [Parameter(Mandatory = $true)][string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = (Resolve-Path $Root).Path

function Ensure-Dir([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

Ensure-Dir (Join-Path $root "main")
Ensure-Dir (Join-Path $root "scalefs.runtime.d\scalefs.state")
Ensure-Dir (Join-Path $root "scalefs.local.d")
Ensure-Dir (Join-Path $root "scalefs.global.d")

$iniPath = Join-Path $root "scalefs.ini"
if (-not (Test-Path -LiteralPath $iniPath)) {
    @"
[paths]
main = ./main
state_dir = ./scalefs.runtime.d/scalefs.state
watch_root = ./main
watch_exclude = ./scalefs.runtime.d/**, ./scalefs.local.d/**, .shadow/**, .latest/**, .tmp/**, .snapshot/**, .git/**
"@ | Set-Content -Encoding UTF8 -NoNewline $iniPath
}

$gitignore = Join-Path $root ".gitignore"
if (-not (Test-Path -LiteralPath $gitignore)) {
    @"
# scalefs runtime/local state (per-node / ephemeral)
scalefs.runtime.d/
scalefs.local.d/
# generic internal working dirs
.shadow/
.latest/
.tmp/
.snapshot/
"@ | Set-Content -Encoding UTF8 -NoNewline $gitignore
}

Write-Host "ok: initialized scalefs root = $root"