# tools/zmesh-status.ps1
#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ZconfDir {
  if ($env:ZCONF_DIR) { return $env:ZCONF_DIR }
  $p = Join-Path $HOME ".zmesh"
  return $p
}

function Get-Roots {
  $zconf = Get-ZconfDir
  $dir = Join-Path $zconf "zmesh.d"
  if (-not (Test-Path $dir)) { return @() }

  $roots = @()
  Get-ChildItem $dir -Filter "*.conf" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $null
    $path = $null
    foreach ($line in Get-Content $_.FullName) {
      if ($line -match '^\[root\s+"(.+)"\]') { $name = $matches[1] }
      elseif ($line -match '^path=(.+)$') { $path = $matches[1] }
    }
    if ($name -and $path) { $roots += [pscustomobject]@{ Alias=$name; Path=$path } }
  }
  return $roots
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$zconf = Get-ZconfDir

Write-Host "zmesh status"
Write-Host ("  repo:   {0}" -f $repo)
Write-Host ("  zconf:  {0}" -f $zconf)

# zfs availability
$zfs = Get-Command zfs.exe -ErrorAction SilentlyContinue
$zpool = Get-Command zpool.exe -ErrorAction SilentlyContinue
if ($zfs -and $zpool) {
  try {
    $v = & $zfs.Source version 2>$null | Select-Object -First 1
    if ($v) { Write-Host ("  zfs:    yes ({0})" -f $v.Trim()) } else { Write-Host "  zfs:    yes" }
  } catch { Write-Host "  zfs:    yes" }
} else {
  Write-Host "  zfs:    no"
}

$roots = Get-Roots
Write-Host ("  roots:  {0}" -f $roots.Count)
foreach ($r in $roots) {
  Write-Host ("    - {0} -> {1}" -f $r.Alias, $r.Path)
}

# count scalefs bodies (cheap)
$cnt = 0
foreach ($r in $roots) {
  if (Test-Path $r.Path) {
    Get-ChildItem $r.Path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      if (Test-Path (Join-Path $_.FullName "scalefs.ini")) { $cnt++ }
    }
  }
}
Write-Host ("  scalefs: {0} (dirs containing scalefs.ini)" -f $cnt)