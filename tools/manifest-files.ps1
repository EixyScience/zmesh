# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [string]$Id,
  [string]$Root,
  [string]$Path,
  [ValidateSet("json","ini")] [string]$Format = "json"
)

function Die($m) { throw $m }

function Usage {
  @"
Usage: manifest-scalefs.ps1 [-Id ID] [-Root ALIAS] [-Path PATH] [-Format json|ini]

Examples:
  .\manifest-scalefs.ps1 -Path .
  .\manifest-scalefs.ps1 -Id democell.28e671 -Root test
  .\manifest-scalefs.ps1 -Path C:\scalefsroot\democell.28e671 -Format ini
"@ | Write-Host
}

if ($PSBoundParameters.ContainsKey("Help")) { Usage; exit 0 }

# Load roots (compatible with your current zmesh.d style: [root "name"] + path=)
function Get-Roots {
  $zconf = $env:ZCONF_DIR
  if (-not $zconf) { $zconf = "$HOME\.zmesh" } # windows fallback
  $dir = Join-Path $zconf "zmesh.d"
  if (-not (Test-Path $dir)) { return @() }

  $roots = @()
  Get-ChildItem $dir -Filter "*.conf" -File | ForEach-Object {
    $name = $null
    $path = $null
    Get-Content $_.FullName | ForEach-Object {
      if ($_ -match '^\[root\s+"(.+)"\]') { $name = $matches[1] }
      elseif ($_ -match '^path=(.+)$') { $path = $matches[1] }
    }
    if ($name -and $path) {
      $roots += [pscustomobject]@{ Alias=$name; Path=$path }
    }
  }
  return $roots
}

function Resolve-BodyPath {
  param([string]$Id,[string]$Root,[string]$Path)

  if ($Path) {
    if ($Path -eq ".") { return (Get-Location).Path }
    return (Resolve-Path $Path).Path
  }

  if (-not $Id) { Die "require -Path or -Id" }
  $roots = Get-Roots

  if ($Root) {
    $r = $roots | Where-Object { $_.Alias -eq $Root } | Select-Object -First 1
    if (-not $r) { Die "unknown root alias: $Root" }
    return (Join-Path $r.Path $Id)
  }

  # unique match across all roots
  $cands = @()
  foreach ($r in $roots) {
    $p = Join-Path $r.Path $Id
    if (Test-Path $p) { $cands += $p }
  }
  if ($cands.Count -ne 1) { Die "could not resolve id=$Id uniquely (specify -Root or -Path)" }
  return $cands[0]
}

function Get-IniValue {
  param([string]$IniPath,[string]$Section,[string]$Key)
  $sec = "[$Section]"
  $in = $false
  foreach ($line in Get-Content $IniPath) {
    if ($line.Trim() -eq $sec) { $in = $true; continue }
    if ($in -and $line.Trim().StartsWith("[")) { break }
    if ($in -and $line -match ("^\s*"+[regex]::Escape($Key)+"\s*=\s*(.*)$")) {
      return $matches[1].Trim()
    }
  }
  return ""
}

$dir = Resolve-BodyPath -Id $Id -Root $Root -Path $Path
if (-not (Test-Path $dir)) { Die "not a directory: $dir" }
$ini = Join-Path $dir "scalefs.ini"
if (-not (Test-Path $ini)) { Die "missing scalefs.ini: $ini" }

$idv  = Get-IniValue $ini "scalefs" "id"
$name = Get-IniValue $ini "scalefs" "name"
$sid  = Get-IniValue $ini "scalefs" "shortid"

$stateDir = Get-IniValue $ini "paths" "state_dir"
$watchRoot = Get-IniValue $ini "paths" "watch_root"

$zfsEnabled = Get-IniValue $ini "zfs" "enabled"
$zfsPool = Get-IniValue $ini "zfs" "pool"
$zfsDataset = Get-IniValue $ini "zfs" "dataset"

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$os  = "windows"

if ($Format -eq "ini") {
@"
[manifest]
generated_unix=$now
os=$os
path=$dir

[scalefs]
id=$idv
name=$name
shortid=$sid

[paths]
main=$(Join-Path $dir "main")
state=$(Join-Path $dir "scalefs.state")
global_d=$(Join-Path $dir "scalefs.global.d")
local_d=$(Join-Path $dir "scalefs.local.d")
runtime_d=$(Join-Path $dir "scalefs.runtime.d")

[config]
state_dir=$stateDir
watch_root=$watchRoot

[zfs]
enabled=$zfsEnabled
pool=$zfsPool
dataset=$zfsDataset
"@ | Write-Output
  exit 0
}

# json
$obj = [ordered]@{
  ok = $true
  generated_unix = $now
  os = $os
  path = $dir
  scalefs = [ordered]@{ id=$idv; name=$name; shortid=$sid }
  paths = [ordered]@{
    main = (Join-Path $dir "main")
    state = (Join-Path $dir "scalefs.state")
    global_d = (Join-Path $dir "scalefs.global.d")
    local_d = (Join-Path $dir "scalefs.local.d")
    runtime_d = (Join-Path $dir "scalefs.runtime.d")
  }
  config = [ordered]@{ state_dir=$stateDir; watch_root=$watchRoot }
  zfs = [ordered]@{ enabled=$zfsEnabled; pool=$zfsPool; dataset=$zfsDataset }
}

$obj | ConvertTo-Json -Depth 6