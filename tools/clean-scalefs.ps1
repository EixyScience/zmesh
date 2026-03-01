#requires -Version 5.1
param(
  [Alias("i")] [string]$Id,
  [Alias("r")] [string]$Root,
  [Alias("p")] [string]$Path = ".",
  [switch]$State,
  [switch]$DestroyZfs,
  [switch]$DestroyBody,
  [Alias("y")] [switch]$Yes,
  [Alias("h")] [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Usage {
@"
clean-scalefs.ps1 - cleanup a scalefs body

USAGE
  powershell -ExecutionPolicy Bypass -File tools\clean-scalefs.ps1 [-Path PATH] [-Yes] [-State] [-DestroyZfs] [-DestroyBody]
  powershell -ExecutionPolicy Bypass -File tools\clean-scalefs.ps1 -Id ID [-Root ALIAS] [-Yes] [-State] [-DestroyZfs] [-DestroyBody]

DEFAULT BEHAVIOR
  - Removes scalefs.runtime.d\* only (safe).

OPTIONS
  -p, -Path PATH        Path inside scalefs body (dir or file). Default: .
  -i, -Id ID            body id (name.shortid)
  -r, -Root ALIAS       root alias (when resolving -Id)
  -State                Also clear scalefs.state\*
  -DestroyZfs            Destroy ZFS dataset recorded in scalefs.ini (DANGEROUS)
  -DestroyBody           Remove the whole body directory (DANGEROUS)
  -y, -Yes              No confirmation
  -h, -Help             Show help

EXAMPLES
  powershell -ExecutionPolicy Bypass -File tools\clean-scalefs.ps1 -Path . -Yes
  powershell -ExecutionPolicy Bypass -File tools\clean-scalefs.ps1 -Path C:\scalefsroot\democell.28e671 -State -Yes
  powershell -ExecutionPolicy Bypass -File tools\clean-scalefs.ps1 -Id democell.28e671 -Root test -DestroyZfs -DestroyBody -Yes
"@ | Write-Host
}

if ($PSBoundParameters.ContainsKey("Help")) { Usage; exit 0 }

function Die([string]$m) { throw $m }

function Confirm([string]$msg) {
  if ($Yes) { return $true }
  $ans = Read-Host "$msg [y/N]"
  return ($ans -match '^(y|yes)$')
}

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

# Resolve target
$target = $null
if ($Id) { $target = Resolve-BodyPathById -id $Id -rootAlias $Root } else { $target = $Path }

$bodyDir = Resolve-BodyDir $target
if (-not $bodyDir) {
  Die "missing scalefs.ini near: $target`nHINT: run inside a scalefs body dir or pass -Path to it."
}

$ini = Join-Path $bodyDir "scalefs.ini"
$zfsEnabled = Get-IniValue $ini "zfs" "enabled"
$zfsDataset = Get-IniValue $ini "zfs" "dataset"

Write-Host "Target: $bodyDir"
Write-Host "Plan:"
Write-Host "  - clear runtime: scalefs.runtime.d\*"
if ($State) { Write-Host "  - clear state:   scalefs.state\*" }
if ($DestroyZfs) { Write-Host "  - destroy zfs dataset: $zfsDataset" }
if ($DestroyBody) { Write-Host "  - remove body dir: $bodyDir" }

if (-not (Confirm "Proceed?")) { Die "aborted" }

# runtime cleanup
$runtime = Join-Path $bodyDir "scalefs.runtime.d"
if (Test-Path $runtime) {
  Get-ChildItem $runtime -Force -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# optional state cleanup
if ($State) {
  $st = Join-Path $bodyDir "scalefs.state"
  if (Test-Path $st) {
    Get-ChildItem $st -Force -ErrorAction SilentlyContinue |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# optional zfs destroy
if ($DestroyZfs) {
  $zfs = Get-Command zfs.exe -ErrorAction SilentlyContinue
  if ($zfs -and $zfsEnabled -eq "true" -and $zfsDataset) {
    & $zfs.Source unmount -f $zfsDataset 2>$null | Out-Null
    & $zfs.Source destroy -r $zfsDataset 2>$null | Out-Null
  } else {
    Write-Host "WARN: zfs destroy skipped (zfs missing or zfs.enabled!=true or dataset empty)"
  }
}

# optional body removal
if ($DestroyBody) {
  Remove-Item $bodyDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "OK"