# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Say($s) { Write-Host $s }

function Resolve-Entry([string]$name) {
  $base = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
  $tools = Join-Path $base "tools"

  $p1 = Join-Path $base $name
  if (Test-Path $p1) { return $p1 }

  $p2 = Join-Path $tools $name
  if (Test-Path $p2) { return $p2 }

  throw "missing entry: $name"
}

function Assert-Help([string]$path, [string]$needle) {
  $out = & $path help 2>$null | Out-String
  if ($out -notmatch $needle) {
    throw "help output from $path does not contain '$needle'"
  }
}

function Optional-Help([string]$path) {
  try {
    $out = & $path help 2>$null | Out-String
    if ($out) {
      Say "  optional help ok: $path"
    }
  }
  catch {
    Say "  optional tool missing or not ready: $path"
  }
}

# ------------------------------------------------------------
# Base paths
# ------------------------------------------------------------

$base = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$tools = Join-Path $base "tools"

# ------------------------------------------------------------
# 1) basic checks
# ------------------------------------------------------------

Say "[1] basic checks"

$zmesh   = Resolve-Entry "zmesh.ps1"
$scalefs = Resolve-Entry "scalefs.ps1"

Say "  zmesh.ps1:   $zmesh"
Say "  scalefs.ps1: $scalefs"

Assert-Help $zmesh "USAGE|Usage|usage"
Assert-Help $scalefs "USAGE|Usage|usage"

# tools/ variants (optional)
$toolsZ = Join-Path $tools "zmesh.ps1"
$toolsS = Join-Path $tools "scalefs.ps1"

if (Test-Path $toolsZ) { Assert-Help $toolsZ "USAGE|Usage|usage" }
if (Test-Path $toolsS) { Assert-Help $toolsS "USAGE|Usage|usage" }

Say "  OK: help works"

# ------------------------------------------------------------
# 2) required script presence sanity
# ------------------------------------------------------------

Say "[2] required script presence"

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

  if (-not (Test-Path $p)) {
    throw "missing: $p"
  }
}

Say "  OK: required scripts present"

# ------------------------------------------------------------
# 3) optional tools presence (virtualpath/apply/manifest/clean)
# ------------------------------------------------------------

Say "[3] optional tools (non-fatal)"

$optional = @(
  "tools\add-virtualpath.ps1",
  "tools\list-virtualpath.ps1",
  "tools\remove-virtualpath.ps1",
  "tools\doctor-virtualpath.ps1",
  "tools\apply-virtualpath.ps1",
  "tools\manifest-scalefs.ps1",
  "tools\clean-scalefs.ps1"
)

foreach ($rel in $optional) {

  $p = Join-Path $base $rel

  if (Test-Path $p) {
    Say "  found optional: $rel"
  }
  else {
    Say "  optional missing (ok): $rel"
  }
}

# ------------------------------------------------------------
# 4) command dispatch sanity (zmesh virtualpath / apply)
# ------------------------------------------------------------

Say "[4] command dispatch sanity"

try {

  & $zmesh help | Out-Null
  Say "  zmesh help ok"

}
catch {

  throw "zmesh help failed"

}

try {

  & $zmesh scalefs help | Out-Null
  Say "  zmesh scalefs help ok"

}
catch {

  throw "zmesh scalefs help failed"

}

# optional commands (non-fatal)

try {

  & $zmesh virtualpath help 2>$null | Out-Null
  Say "  virtualpath entry ok"

}
catch {

  Say "  virtualpath not implemented yet (ok)"

}

try {

  & $zmesh apply --help 2>$null | Out-Null
  Say "  apply entry ok"

}
catch {

  Say "  apply not implemented yet (ok)"

}

Say ""
Say "ALL OK"