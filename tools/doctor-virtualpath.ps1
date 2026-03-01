# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [switch]$CheckTargets,
  [switch]$Strict,
  [Alias("f")]
  [string]$File
)

function Say($s){ Write-Host $s }
function Die($s){ throw $s }

$ZCONF_DIR = $env:ZCONF_DIR
if ([string]::IsNullOrWhiteSpace($ZCONF_DIR)) { $ZCONF_DIR = Join-Path $HOME ".zmesh" }
$confDir = Join-Path $ZCONF_DIR "virtualpath.d"

if (-not (Test-Path $confDir)) { Die "missing config dir: $confDir" }

$files = @()
if ($File) {
  $p = Join-Path $confDir $File
  if (-not (Test-Path $p)) { Die "missing file: $p" }
  $files = @($p)
} else {
  $files = Get-ChildItem -LiteralPath $confDir -Filter "*.conf" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
}

if (-not $files -or $files.Count -eq 0) {
  Say "(no virtualpath rules)"
  exit 0
}

$hdrRegex = '^\[vpath\s+"([^"]+)"\]\s*$'
$targetRegex = '^target\s*=\s*(.*)$'

$warn = 0
$err  = 0
$rules = 0

Say "[doctor] conf=$confDir check_targets=$CheckTargets strict=$Strict"

foreach ($f in $files) {
  Say "== $f =="

  $v = $null
  $t = $null
  $sections = 0

  foreach ($line in Get-Content -LiteralPath $f) {
    $s = $line.Trim()
    if ($s -eq "" -or $s.StartsWith("#") -or $s.StartsWith(";")) { continue }

    $m = [regex]::Match($s, $hdrRegex)
    if ($m.Success) {
      if ($v -and -not $t) { Say "E missing target for vpath=$v"; $err++ }
      $v = $m.Groups[1].Value
      $t = $null
      $sections++
      continue
    }

    if ($v) {
      $m2 = [regex]::Match($s, $targetRegex)
      if ($m2.Success) {
        $t = $m2.Groups[1].Value.Trim()
        $rules++
        if ($CheckTargets -and -not (Test-Path -LiteralPath $t)) {
          Say "W target missing: vpath=$v target=$t"
          $warn++
        }
        continue
      }
    }
  }

  if ($v -and -not $t) { Say "E missing target for vpath=$v"; $err++ }
  Say "I sections=$sections"
}

Say "[summary] rules=$rules warnings=$warn errors=$err"

if ($Strict -and ($warn -gt 0 -or $err -gt 0)) {
  Die "doctor failed (strict)"
}
exit 0