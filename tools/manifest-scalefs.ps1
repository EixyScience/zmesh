# tools/manifest-scalefs.ps1
# Emit a "body manifest" (metadata + paths + config + zfs stanza) for a scalefs body.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib.ps1"

param(
  [string]$Id,
  [string]$Root,
  [string]$Path,
  [ValidateSet("json","ini")] [string]$Format = "json",
  [switch]$Help
)

function Show-Help {
@"
manifest - emit scalefs body manifest (metadata/config summary)

USAGE
  scalefs manifest [options]

COMMAND + OPTIONS
  scalefs manifest -Path, -p PATH
      Body directory (contains scalefs.ini). Use '.' for current directory.

  scalefs manifest -Id,   -i ID
      Body id (name.shortid). Resolved via registered roots.

  scalefs manifest -Root, -r ALIAS
      Root alias to resolve Id (recommended if multiple roots)

  scalefs manifest -Format json|ini
      Output format (default: json)

EXAMPLES
  scalefs manifest -p .
  scalefs manifest -i democell.28e671 -r default
  scalefs manifest -p C:\scalefsroot\democell.28e671 -Format ini
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }

function Load-Roots {
  $confDir = ZmeshConfDir
  $d = Join-Path $confDir "zmesh.d"
  if (-not (Test-Path $d)) { return @() }

  $roots = @()
  Get-ChildItem $d -Filter "root.*.conf" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $txt = Get-Content $_.FullName -ErrorAction SilentlyContinue
    $alias = (($txt | Where-Object { $_ -match '^\s*alias\s*=' } | Select-Object -First 1) -replace '^\s*alias\s*=\s*','').Trim()
    $path  = (($txt | Where-Object { $_ -match '^\s*path\s*=' }  | Select-Object -First 1) -replace '^\s*path\s*=\s*','').Trim()
    if ($path) { $roots += [pscustomobject]@{ Alias=$alias; Path=$path } }
  }
  return $roots
}

function Resolve-BodyPath([string]$id,[string]$rootAlias,[string]$p) {
  if ($p) {
    if ($p -eq ".") { return (Get-Location).Path }
    return (Resolve-Path $p).Path
  }
  if (-not $id) { throw "require -Path or -Id" }

  $roots = Load-Roots
  if (-not $roots -or $roots.Count -eq 0) { throw "no roots configured (run: zmesh root add)" }

  if ($rootAlias) {
    $r = $roots | Where-Object { $_.Alias -eq $rootAlias } | Select-Object -First 1
    if (-not $r) { throw "unknown root alias: $rootAlias" }
    return (Join-Path $r.Path $id)
  }

  $cands = @()
  foreach ($r in $roots) {
    $pp = Join-Path $r.Path $id
    if (Test-Path $pp) { $cands += $pp }
  }
  if ($cands.Count -eq 0) { throw "not found: $id" }
  if ($cands.Count -ne 1) { throw "could not resolve id=$id uniquely (specify -Root or -Path)" }
  return $cands[0]
}

function Ini-Get([string]$ini,[string]$section,[string]$key) {
  $sec = "[$section]"
  $in = $false
  foreach ($line in Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue) {
    $t = $line.Trim()
    if ($t -eq $sec) { $in = $true; continue }
    if ($in -and $t.StartsWith("[")) { break }
    if ($in -and $t -match ("^\s*"+[regex]::Escape($key)+"\s*=\s*(.*)$")) {
      return $matches[1].Trim()
    }
  }
  return ""
}

$dir = Resolve-BodyPath $Id $Root $Path
if (-not (Test-Path $dir)) { throw "not a directory: $dir" }

$ini = Join-Path $dir "scalefs.ini"
if (-not (Test-Path $ini)) { throw "missing scalefs.ini: $ini" }

$idv   = Ini-Get $ini "scalefs" "id"
$name  = Ini-Get $ini "scalefs" "name"
$sid   = Ini-Get $ini "scalefs" "shortid"

$stateDir  = Ini-Get $ini "paths" "state_dir"
$watchRoot = Ini-Get $ini "paths" "watch_root"

$zEnabled  = Ini-Get $ini "zfs" "enabled"
$zPool     = Ini-Get $ini "zfs" "pool"
$zDataset  = Ini-Get $ini "zfs" "dataset"

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$os  = "windows"

$mainPath    = Join-Path $dir "main"
$statePath   = Join-Path $dir "scalefs.state"
$globalPath  = Join-Path $dir "scalefs.global.d"
$localPath   = Join-Path $dir "scalefs.local.d"
$runtimePath = Join-Path $dir "scalefs.runtime.d"

if ($Format -eq "ini") {
@"
[manifest]
ok=true
generated_unix=$now
os=$os
path=$dir

[scalefs]
id=$idv
name=$name
shortid=$sid

[paths]
main=$mainPath
state=$statePath
global_d=$globalPath
local_d=$localPath
runtime_d=$runtimePath

[config]
state_dir=$stateDir
watch_root=$watchRoot

[zfs]
enabled=$zEnabled
pool=$zPool
dataset=$zDataset
"@ | Write-Output
  exit 0
}

$obj = [ordered]@{
  ok = $true
  generated_unix = $now
  os = $os
  path = $dir
  scalefs = [ordered]@{ id=$idv; name=$name; shortid=$sid }
  paths = [ordered]@{
    main = $mainPath
    state = $statePath
    global_d = $globalPath
    local_d = $localPath
    runtime_d = $runtimePath
  }
  config = [ordered]@{ state_dir=$stateDir; watch_root=$watchRoot }
  zfs = [ordered]@{ enabled=$zEnabled; pool=$zPool; dataset=$zDataset }
}

$obj | ConvertTo-Json -Depth 6