# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0# tools/remove-scalefs.ps1
# Remove a scalefs body directory (and optionally destroy its ZFS dataset)
# - Default: tries to destroy dataset ONLY if [zfs] enabled=true and dataset is set.
# - Best-effort; if ZFS destroy fails, still can remove directory (unless it's mounted/busy).

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib.ps1"

param(
  [string]$Id,          # name.shortid
  [string]$Root,        # optional root alias for disambiguation
  [switch]$KeepZfs,     # don't destroy dataset even if configured
  [switch]$Yes,
  [switch]$Help
)

function Show-Help {
@"
remove - remove a scalefs body (best-effort)

USAGE
  scalefs remove [options]

COMMAND + OPTIONS
  scalefs remove -Id,   -i ID
      Target id (name.shortid)

  scalefs remove -Root, -r ALIAS
      Root alias (recommended if multiple roots)

  scalefs remove -KeepZfs
      Do not destroy ZFS dataset even if scalefs.ini says enabled=true

  scalefs remove -Yes
      Non-interactive (assume yes)

EXAMPLES
  scalefs remove -i democell.28e671
  scalefs remove -i democell.28e671 -r default -Yes
  scalefs remove -i democell.28e671 -KeepZfs -Yes
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }

function Confirm([string]$msg) {
  if ($Yes) { return $true }
  $ans = Read-Host "$msg [y/N]"
  return ($ans -match '^(y|yes)$')
}

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

function Resolve-BodyPath([string]$id,[string]$rootAlias) {
  $roots = Load-Roots
  if (-not $roots -or $roots.Count -eq 0) { throw "no roots configured (run: zmesh root add)" }

  if ($rootAlias) {
    $r = $roots | Where-Object { $_.Alias -eq $rootAlias } | Select-Object -First 1
    if (-not $r) { throw "unknown root alias: $rootAlias" }
    return (Join-Path $r.Path $id)
  }

  $cands = @()
  foreach ($r in $roots) {
    $p = Join-Path $r.Path $id
    if (Test-Path $p) { $cands += $p }
  }
  if ($cands.Count -eq 0) { throw "not found: $id" }
  if ($cands.Count -ne 1) { throw "id is not unique across roots: $id (specify -Root)" }
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

function Try-ZfsDestroy([string]$ds) {
  if (-not $ds) { return }
  $zfs = Get-Command zfs.exe -ErrorAction SilentlyContinue
  if (-not $zfs) { return }

  Write-Host "zfs destroy -r $ds"
  try { & zfs.exe unmount -f $ds 2>$null | Out-Null } catch {}
  try { & zfs.exe destroy -r $ds 2>$null | Out-Null } catch {}
}

if (-not $Id) { $Id = Ask "ID (name.shortid)" }
$Id = NormalizeName $Id
if (-not $Id) { throw "empty id" }

$dir = Resolve-BodyPath $Id $Root
if (-not (Test-Path $dir)) { throw "not a directory: $dir" }

$ini = Join-Path $dir "scalefs.ini"
if (-not (Test-Path $ini)) { throw "missing scalefs.ini: $ini" }

$zEnabled = (Ini-Get $ini "zfs" "enabled")
$zDataset = (Ini-Get $ini "zfs" "dataset")

Write-Host "Target:"
Write-Host "  id   = $Id"
Write-Host "  dir  = $dir"
if ($zEnabled -ieq "true" -and $zDataset) {
  Write-Host "  zfs  = $zDataset"
} else {
  Write-Host "  zfs  = (none)"
}

if (-not (Confirm "Proceed?")) { Write-Host "cancelled"; exit 0 }

if (-not $KeepZfs) {
  if ($zEnabled -ieq "true" -and $zDataset) {
    Try-ZfsDestroy $zDataset
  }
}

# Remove directory (may fail if still mounted/busy)
Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
Write-Host "OK removed: $Id"