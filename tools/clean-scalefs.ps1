# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0# tools/clean-scalefs.ps1
#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [string]$Id,
  [string]$Root,
  [string]$Path,
  [switch]$State,
  [switch]$DestroyZfs,
  [switch]$DestroyBody,
  [switch]$Yes
)

function Die($m) { throw $m }

function Confirm([string]$msg) {
  if ($Yes) { return $true }
  $ans = Read-Host "$msg [y/N]"
  return ($ans -match '^(y|yes)$')
}

function Get-ZconfDir {
  if ($env:ZCONF_DIR) { return $env:ZCONF_DIR }
  return "$HOME\.zmesh"
}

function Get-Roots {
  $zconf = Get-ZconfDir
  $dir = Join-Path $zconf "zmesh.d"
  if (-not (Test-Path $dir)) { return @() }

  $roots = @()
  Get-ChildItem $dir -Filter "*.conf" -File | ForEach-Object {
    $name = $null
    $path = $null
    foreach ($line in Get-Content $_.FullName) {
      if ($line -match '^\[root\s+"(.+)"\]') { $name = $matches[1] }
      elseif ($line -match '^path=(.+)$') { $path = $matches[1] }
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

$zfsEnabled = Get-IniValue $ini "zfs" "enabled"
$zfsDataset = Get-IniValue $ini "zfs" "dataset"

Write-Host "Target: $dir"
Write-Host "Plan:"
Write-Host "  - clear runtime: scalefs.runtime.d\*"
if ($State) { Write-Host "  - clear state:   scalefs.state\*" }
if ($DestroyZfs) { Write-Host "  - destroy zfs dataset (if any): $zfsDataset" }
if ($DestroyBody) { Write-Host "  - remove body directory: $dir" }

if (-not (Confirm "Proceed?")) { Die "aborted" }

# runtime cleanup
$runtime = Join-Path $dir "scalefs.runtime.d"
if (Test-Path $runtime) {
  Get-ChildItem $runtime -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# optional state cleanup
if ($State) {
  $st = Join-Path $dir "scalefs.state"
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
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "OK"