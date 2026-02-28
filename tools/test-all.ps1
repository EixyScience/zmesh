# tools/test-all.ps1
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

function Get-HelpText([string]$path) {
  # PowerShell script: call with & and capture all output as a single string
  $out = & $path help 2>&1 | Out-String
  return $out
}

function Assert-HelpContainsAny([string]$path, [string[]]$needles) {
  $out = Get-HelpText $path

  # debug print (useful when failing)
  # Say "---- help from $path ----"
  # Say $out
  # Say "--------------------------"

  foreach ($n in $needles) {
    if ($out -match $n) { return }
  }
  throw "help output from $path does not contain any of: $($needles -join ', ')"
}

Say "[1] basic checks"
$zmesh = Resolve-Entry "zmesh.ps1"
$scalefs = Resolve-Entry "scalefs.ps1"

Say "  zmesh.ps1:   $zmesh"
Say "  scalefs.ps1: $scalefs"

# Accept either "USAGE" or "Usage" to be flexible
Assert-HelpContainsAny $zmesh   @("(?im)^\s*usage\b", "(?im)^\s*USAGE\b")
Assert-HelpContainsAny $scalefs @("(?im)^\s*usage\b", "(?im)^\s*USAGE\b")

# Also test tools/ entry variants if present
$base = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$toolsZ = Join-Path $base "tools\zmesh.ps1"
$toolsS = Join-Path $base "tools\scalefs.ps1"
if (Test-Path $toolsZ) { Assert-HelpContainsAny $toolsZ @("(?im)^\s*usage\b", "(?im)^\s*USAGE\b") }
if (Test-Path $toolsS) { Assert-HelpContainsAny $toolsS @("(?im)^\s*usage\b", "(?im)^\s*USAGE\b") }

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