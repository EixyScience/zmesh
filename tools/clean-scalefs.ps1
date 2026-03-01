#requires -Version 5.1
param(
  [Alias("i")] [string]$Id,
  [Alias("r")] [string]$Root,
  [Alias("p")] [string]$Path,
  [switch]$State,
  [switch]$DestroyZfs,
  [switch]$DestroyBody,
  [switch]$Yes,
  [Alias("h")] [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Usage {
@"
clean-scalefs.ps1 - cleanup runtime/state and optionally destroy zfs/body

USAGE
  powershell -ExecutionPolicy Bypass -File tools\clean-scalefs.ps1 [options]

OPTIONS
  -p, --Path PATH       Path inside a scalefs body (body dir OR any subdir)
  -State                Also clear scalefs.state\*
  -DestroyZfs            Destroy zfs dataset (if enabled in scalefs.ini)
  -DestroyBody           Remove the body directory itself
  -Yes                  No prompt
  -h, --Help             Show help

EXAMPLES
  powershell -ExecutionPolicy Bypass -File tools\clean-scalefs.ps1 -Path . -Yes
  powershell -ExecutionPolicy Bypass -File tools\clean-scalefs.ps1 -Path C:\scalefsroot\democell.28e671 -State -Yes
"@ | Write-Host
}

if ($Help) { Usage; exit 0 }
function Die([string]$m) { throw $m }

function Confirm([string]$msg) {
  if ($Yes) { return $true }
  $ans = Read-Host "$msg [y/N]"
  return ($ans -match '^(y|yes)$')
}

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
$zfsEnabled = Get-IniValue $ini "zfs" "enabled"
$zfsDataset = Get-IniValue $ini "zfs" "dataset"

Write-Host "Target: $body"
Write-Host "Plan:"
Write-Host "  - clear runtime: scalefs.runtime.d\*"
if ($State) { Write-Host "  - clear state:   scalefs.state\*" }
if ($DestroyZfs) { Write-Host "  - destroy zfs dataset (if any): $zfsDataset" }
if ($DestroyBody) { Write-Host "  - remove body directory: $body" }

if (-not (Confirm "Proceed?")) { Die "aborted" }

# runtime cleanup
$runtime = Join-Path $body "scalefs.runtime.d"
if (Test-Path $runtime) {
  Get-ChildItem $runtime -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# optional state cleanup
if ($State) {
  $st = Join-Path $body "scalefs.state"
  if (Test-Path $st) {
    Get-ChildItem $st -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# optional zfs destroy
if ($DestroyZfs) {
  $zfs = Get-Command zfs.exe -ErrorAction SilentlyContinue
  if ($zfs -and $zfsEnabled -eq "true" -and $zfsDataset) {
    & $zfs.Source unmount $zfsDataset 2>$null | Out-Null
    & $zfs.Source destroy -r $zfsDataset 2>$null | Out-Null
  }
}

# optional body removal
if ($DestroyBody) {
  Remove-Item $body -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "OK"