#requires -Version 5.1
param(
  [Alias("i")] [string]$Id,
  [Alias("r")] [string]$Root,
  [Alias("p")] [string]$Path,
  [ValidateSet("json","ini")] [string]$Format = "json",
  [Alias("h")] [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Usage {
@"
manifest-scalefs.ps1 - print scalefs body manifest (json or ini)

USAGE
  powershell -ExecutionPolicy Bypass -File tools\manifest-scalefs.ps1 [options]

OPTIONS
  -p, --Path PATH          Path inside a scalefs body (body dir OR any subdir)
  -i, --Id ID              name.shortid
  -r, --Root ALIAS          root alias (used with -Id)
  -Format json|ini          output format (default json)
  -h, --Help                show help

EXAMPLES
  powershell -ExecutionPolicy Bypass -File tools\manifest-scalefs.ps1 -Path .
  powershell -ExecutionPolicy Bypass -File tools\manifest-scalefs.ps1 -Path C:\scalefsroot\democell.28e671\main -Format ini
"@ | Write-Host
}

if ($Help) { Usage; exit 0 }

function Die([string]$m) { throw $m }

function Get-Roots {
  $zconf = $env:ZCONF_DIR
  if (-not $zconf) { $zconf = "$HOME\.zmesh" }
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
    $p = $Path
    if ($p -eq ".") { $p = (Get-Location).Path }
    return (Resolve-Path $p).Path
  }

  if (-not $Id) { Die "require -Path or -Id" }
  $roots = Get-Roots

  if ($Root) {
    $r = $roots | Where-Object { $_.Alias -eq $Root } | Select-Object -First 1
    if (-not $r) { Die "unknown root alias: $Root" }
    return (Join-Path $r.Path $Id)
  }

  $cands = @()
  foreach ($r in $roots) {
    $p = Join-Path $r.Path $Id
    if (Test-Path $p) { $cands += $p }
  }
  if ($cands.Count -ne 1) { Die "could not resolve id=$Id uniquely (specify -Root or -Path)" }
  return $cands[0]
}

function Find-BodyDir([string]$start) {
  $d = (Resolve-Path $start).Path
  while ($true) {
    if (Test-Path (Join-Path $d "scalefs.ini")) { return $d }
    $parent = Split-Path -Parent $d
    if (-not $parent -or $parent -eq $d) { break }
    $d = $parent
  }
  return $null
}

function Get-IniValue {
  param([string]$IniPath,[string]$Section,[string]$Key)
  $sec = "[$Section]"
  $in = $false
  foreach ($line in Get-Content $IniPath) {
    $t = $line.Trim()
    if ($t -eq $sec) { $in = $true; continue }
    if ($in -and $t.StartsWith("[")) { break }
    if ($in) {
      $x = ($line -split '[;#]',2)[0]
      if ($x -match ("^\s*"+[regex]::Escape($Key)+"\s*=\s*(.*)$")) {
        return $matches[1].Trim()
      }
    }
  }
  return ""
}

$start = Resolve-BodyPath -Id $Id -Root $Root -Path $Path
$body  = Find-BodyDir $start
if (-not $body) {
  Die "missing scalefs.ini near: $start`nHINT: run inside a scalefs body dir or pass -Path to any subdir inside it."
}

$ini = Join-Path $body "scalefs.ini"

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

$paths = [ordered]@{
  main     = (Join-Path $body "main")
  state    = (Join-Path $body "scalefs.state")
  global_d = (Join-Path $body "scalefs.global.d")
  local_d  = (Join-Path $body "scalefs.local.d")
  runtime_d= (Join-Path $body "scalefs.runtime.d")
}

if ($Format -eq "ini") {
@"
[manifest]
generated_unix=$now
os=$os
path=$body

[scalefs]
id=$idv
name=$name
shortid=$sid

[paths]
main=$($paths.main)
state=$($paths.state)
global_d=$($paths.global_d)
local_d=$($paths.local_d)
runtime_d=$($paths.runtime_d)

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

$obj = [ordered]@{
  ok = $true
  generated_unix = $now
  os = $os
  path = $body
  scalefs = [ordered]@{ id=$idv; name=$name; shortid=$sid }
  paths = $paths
  config = [ordered]@{ state_dir=$stateDir; watch_root=$watchRoot }
  zfs = [ordered]@{ enabled=$zfsEnabled; pool=$zfsPool; dataset=$zfsDataset }
}

$obj | ConvertTo-Json -Depth 6