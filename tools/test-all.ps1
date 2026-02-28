#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Say($s) { Write-Host $s }
function Die($s) { throw $s }

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
  "tools\remove-scalefs.ps1",

  "tools\add-virtualpath.ps1",
  "tools\list-virtualpath.ps1",
  "tools\remove-virtualpath.ps1",
  "tools\doctor-virtualpath.ps1",
  "tools\apply-virtualpath.ps1"
)

foreach ($rel in $mustExist) {
  $p = Join-Path $base $rel
  if (-not (Test-Path $p)) { throw "missing: $p" }
}

Say "  OK: scripts exist"

Say "[3] virtualpath smoke (temp config + apply dry-run)"

# temp dirs
$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("zmesh-test." + ([guid]::NewGuid().ToString("N")).Substring(0,6))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

try {
  $env:ZCONF_DIR = Join-Path $tmpRoot "etc\zmesh"
  $vpDir = Join-Path $env:ZCONF_DIR "virtualpath.d"
  New-Item -ItemType Directory -Force -Path $vpDir | Out-Null

  $vroot = Join-Path $tmpRoot "vroot"
  New-Item -ItemType Directory -Force -Path $vroot | Out-Null

  # Create a fake target directory
  $target = Join-Path $tmpRoot "target\main"
  New-Item -ItemType Directory -Force -Path $target | Out-Null

  $addVp = Join-Path $base "tools\add-virtualpath.ps1"
  $listVp = Join-Path $base "tools\list-virtualpath.ps1"
  $docVp = Join-Path $base "tools\doctor-virtualpath.ps1"
  $applyVp = Join-Path $base "tools\apply-virtualpath.ps1"
  $rmVp = Join-Path $base "tools\remove-virtualpath.ps1"

  & $addVp -VPath "hobby/car" -Target $target -Yes | Out-Null

  $out = & $listVp | Out-String
  if ($out -notmatch "hobby/car") { Die "list-virtualpath missing vpath" }
  if ($out -notmatch [regex]::Escape($target)) { Die "list-virtualpath missing target" }

  & $docVp -CheckTargets | Out-Null

  # dry-run apply must succeed
  & $applyVp -Root $vroot -DryRun -Yes | Out-Null

  & $rmVp -VPath "hobby/car" -Yes | Out-Null
  $out2 = & $listVp | Out-String
  if ($out2 -match "hobby/car") { Die "remove-virtualpath failed: still present" }

  Say "  OK: virtualpath smoke passed"
}
finally {
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tmpRoot | Out-Null
  Remove-Item Env:ZCONF_DIR -ErrorAction SilentlyContinue
}

Say "ALL OK"