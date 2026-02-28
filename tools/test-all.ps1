#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Say($s) { Write-Host $s }

function Resolve-Entry([string]$name) {
  $base = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
  $tools = (Resolve-Path (Join-Path $base "tools")).Path

  $p1 = Join-Path $base $name
  if (Test-Path $p1) { return $p1 }

  $p2 = Join-Path $tools $name
  if (Test-Path $p2) { return $p2 }

  throw "missing entry: $name (searched: $p1 and $p2)"
}

function Assert-Help([string]$path, [string]$needle) {
  $out = & $path help 2>$null | Out-String
  if ($out -notmatch $needle) {
    throw "help output from $path does not contain '$needle'"
  }
}

Say "[1] basic checks"
$zmesh = Resolve-Entry "zmesh.ps1"
$scalefs = Resolve-Entry "scalefs.ps1"

Say "  zmesh.ps1:   $zmesh"
Say "  scalefs.ps1: $scalefs"

Assert-Help $zmesh "Usage|usage"
Assert-Help $scalefs "Usage|usage"

# Also test tools/ entry variants if present
$base = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$toolsZ = Join-Path $base "tools\zmesh.ps1"
$toolsS = Join-Path $base "tools\scalefs.ps1"
if (Test-Path $toolsZ) { Assert-Help $toolsZ "Usage|usage" }
if (Test-Path $toolsS) { Assert-Help $toolsS "Usage|usage" }

Say "  OK: help works"

Say "[2] script presence sanity"
$mustExist = @(
  "tools\lib.ps1",
  "tools\mk.ps1",
  "tools\add-root.ps1",
  "tools\add-scalefs.ps1",
  "tools\list-root.ps1",
  "tools\list-scalefs.ps1",
  "tools\remove-root.ps1",
  "tools\remove-scalefs.ps1"
)

foreach ($rel in $mustExist) {
  $p = Join-Path $base $rel
  if (-not (Test-Path $p)) { throw "missing: $p" }
}

Say "ALL OK"