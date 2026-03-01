#requires -Version 5.1
param(
  [Alias("i")] [string]$Id,
  [Alias("r")] [string]$Root,
  [Alias("p")] [string]$Path = ".",
  [Alias("f")] [ValidateSet("json","ini")] [string]$Format = "json",
  [Alias("h")] [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Usage {
@"
manifest-scalefs.ps1 - show manifest for a scalefs body

USAGE
  powershell -ExecutionPolicy Bypass -File tools\manifest-scalefs.ps1 [-Path PATH] [-Format json|ini]
  powershell -ExecutionPolicy Bypass -File tools\manifest-scalefs.ps1 -Id ID [-Root ALIAS] [-Format json|ini]

OPTIONS
  -p, -Path PATH        Path inside scalefs body (dir or file). Default: .
  -i, -Id ID            body id (name.shortid)
  -r, -Root ALIAS       root alias (when resolving -Id)
  -f, -Format FMT       json (default) or ini
  -h, -Help             Show help

EXAMPLES
  powershell -ExecutionPolicy Bypass -File tools\manifest-scalefs.ps1 -Path .
  powershell -ExecutionPolicy Bypass -File tools\manifest-scalefs.ps1 -Path C:\scalefsroot\democell.28e671 -Format ini
  powershell -ExecutionPolicy Bypass -File tools\manifest-scalefs.ps1 -Id democell.28e671 -Root test
"@ | Write-Host
}

if ($PSBoundParameters.ContainsKey("Help")) { Usage; exit 0 }

function Die([string]$m) { throw $m }

# Walk up to find scalefs.ini
function Resolve-BodyDir([string]$p) {
  if (-not $p) { $p = "." }

  $d = $null
  if (Test-Path $p -PathType Leaf) {
    $d = (Resolve-Path (Split-Path -Parent $p)).Path
  } else {
    $d = (Resolve-Path $p).Path
  }

  $cur = $d
  while ($true) {
    if (Test-Path (Join-Path $cur "scalefs.ini")) { return $cur }
    $parent = Split-Path -Parent $cur
    if (-not $parent -or $parent -eq $cur) { break }
    $cur = $parent
  }
  return $null
}

# Load roots: compatible with [root "name"] + path=
function Get-Roots {
  $zconf = $env:ZCONF_DIR
  if (-not $zconf) { $zconf = "$HOME\.zmesh" }
  $dir = Join-Path $zconf "zmesh.d"
  if (-not (Test-Path $dir)) { return @() }

  $roots = @()
  Get-ChildItem $dir -Filter "*.conf" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $null
    $path = $null
    foreach ($line in (Get-Content $_.FullName)) {
      if ($line -match '^\[root\s+"(.+)"\]') { $name = $matches[1] }
      elseif ($line -match '^path=(.+)$') { $path = $matches[1] }
    }
    if ($name -and $path) { $roots += [pscustomobject]@{ Alias=$name; Path=$path } }
  }
  return $roots
}

function Resolve-BodyPathById([string]$id,[string]$rootAlias) {
  $roots = Get-Roots
  if (-not $id) { Die "require -Path or -Id" }

  if ($rootAlias) {
    $r = $roots | Where-Object { $_.Alias -eq $rootAlias } | Select-Object -First 1
    if (-not $r) { Die "unknown root alias: $rootAlias" }
    return (Join-Path $r.Path $id)
  }

  $cands = @()
  foreach ($r in $roots) {
    $p = Join-Path $r.Path $id
    if (Test-Path $p) { $cands += $p }
  }
  if ($cands.Count -ne 1) { Die "could not resolve id=$id uniquely (specify -Root or -Path)" }
  return $cands[0]
}

function Get-IniValue([string]$ini,[string]$section,[string]$key) {
  $sec = "[$section]"
  $in = $false
  foreach ($line in Get-Content $ini) {
    $t = $line.Trim()
    if ($t -eq $sec) { $in = $true; continue }
    if ($in -and $t.StartsWith("[")) { break }
    if ($in -and $line -match ("^\s*"+[regex]::Escape($key)+"\s*=\s*(.*)$")) {
      return $matches[1].Trim()
    }
  }
  return ""
}

# Resolve target directory
$target = $null
if ($Id) {
  $target = Resolve-BodyPathById -id $Id -rootAlias $Root
} else {
  $target = $Path
}

$bodyDir = Resolve-BodyDir $target
if (-not $bodyDir) {
  Die "missing scalefs.ini near: $target`nHINT: run inside a scalefs body dir or pass -Path to it."
}

$ini = Join-Path $bodyDir "scalefs.ini"

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
path=$bodyDir

[scalefs]
id=$idv
name=$name
shortid=$sid

[paths]
main=$(Join-Path $bodyDir "main")
state=$(Join-Path $bodyDir "scalefs.state")
global_d=$(Join-Path $bodyDir "scalefs.global.d")
local_d=$(Join-Path $bodyDir "scalefs.local.d")
runtime_d=$(Join-Path $bodyDir "scalefs.runtime.d")

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
  path = $bodyDir
  scalefs = [ordered]@{ id=$idv; name=$name; shortid=$sid }
  paths = [ordered]@{
    main = (Join-Path $bodyDir "main")
    state = (Join-Path $bodyDir "scalefs.state")
    global_d = (Join-Path $bodyDir "scalefs.global.d")
    local_d = (Join-Path $bodyDir "scalefs.local.d")
    runtime_d = (Join-Path $bodyDir "scalefs.runtime.d")
  }
  config = [ordered]@{ state_dir=$stateDir; watch_root=$watchRoot }
  zfs = [ordered]@{ enabled=$zfsEnabled; pool=$zfsPool; dataset=$zfsDataset }
}

$obj | ConvertTo-Json -Depth 6