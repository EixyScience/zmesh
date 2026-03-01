#requires -Version 5.1
param(
  [string]$Root,
  [switch]$All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib.ps1"

function Load-Roots {
  $confDir = ZmeshConfDir
  $d = Join-Path $confDir "zmesh.d"
  if (-not (Test-Path $d)) { return @() }

  $roots = @()
  Get-ChildItem $d -Filter "root.*.conf" -ErrorAction SilentlyContinue | ForEach-Object {
    $txt = Get-Content $_.FullName
    $alias = (($txt | Where-Object { $_ -match '^alias=' } | Select-Object -First 1) -replace '^alias=','').Trim()
    $path  = (($txt | Where-Object { $_ -match '^path=' }  | Select-Object -First 1) -replace '^path=','').Trim()
    if ($path) { $roots += [pscustomobject]@{ Alias=$alias; Path=$path } }
  }
  return $roots
}

$roots = @(Load-Roots)

if (-not $Root -and -not $All) {
  # default: use first root if exists, else HOME\scalefs
  if ($roots.Count -gt 0) {
    $Root = $roots[0].Path
  } else {
    $Root = Join-Path $HOME "scalefs"
  }
}

$targets = @()

if ($All) {
  foreach ($r in $roots) { $targets += $r.Path }
  if ($targets.Count -eq 0) { $targets += (Join-Path $HOME "scalefs") }
} elseif ($Root) {
  # if Root matches alias, resolve
  $r = $roots | Where-Object { $_.Alias -eq $Root } | Select-Object -First 1
  if ($r) { $targets += $r.Path } else { $targets += $Root }
}

foreach ($t in $targets) {
  if (-not (Test-Path $t)) { continue }
  Get-ChildItem $t -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "scalefs.ini") } |
    Select-Object FullName
}