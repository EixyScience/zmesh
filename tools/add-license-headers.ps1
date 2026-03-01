#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [string]$Root = ".",
  [switch]$Apply,
  [int]$Year = 2026,
  [string]$Name1 = "Satoshi Takashima",
  [string]$Name2 = "EixyScience, Inc."
)

function Say($s) { Write-Host $s }

function Has-ApacheMarker([string]$path) {
  try {
    $txt = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    return ($txt -match "Licensed under the Apache License")
  } catch {
    return $false
  }
}

function Prepend-Text([string]$path, [string]$prefix) {
  $orig = Get-Content -LiteralPath $path -Raw
  Set-Content -LiteralPath $path -Value ($prefix + $orig) -Encoding UTF8
}

function Add-GoHeader([string]$path) {
  if (Has-ApacheMarker $path) { return }

  $hdr = @"
// Copyright $Year $Name1
// Copyright $Year $Name2
//
// Licensed under the Apache License, Version 2.0
// http://www.apache.org/licenses/LICENSE-2.0

"@

  if (-not $Apply) { Say ("DRY  go  {0}" -f $path); return }

  # Preserve Go build tags at the top (//go:build, // +build)
  $lines = Get-Content -LiteralPath $path
  $i = 0
  while ($i -lt $lines.Count) {
    if ($lines[$i] -match '^(//go:build |//\s*\+build |//\+build )') { $i++; continue }
    break
  }

  if ($i -gt 0) {
    $before = $lines[0..($i-1)]
    $after  = $lines[$i..($lines.Count-1)]
    $out = @()
    $out += $before
    $out += "" # blank line
    $out += ($hdr.TrimEnd("`r","`n") -split "`r?`n")
    $out += $after
    Set-Content -LiteralPath $path -Value $out -Encoding UTF8
  } else {
    Prepend-Text $path $hdr
  }

  Say ("APPL go  {0}" -f $path)
}

function Add-PsHeader([string]$path) {
  if (Has-ApacheMarker $path) { return }

  $hdr = @"
# Copyright $Year $Name1
# Copyright $Year $Name2
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0

"@

  if (-not $Apply) { Say ("DRY  ps1 {0}" -f $path); return }

  # Safe to prepend comment before param()/#requires
  Prepend-Text $path $hdr
  Say ("APPL ps1 {0}" -f $path)
}

function Add-ShHeader([string]$path) {
  if (Has-ApacheMarker $path) { return }

  $hdr = @"
# Copyright $Year $Name1
# Copyright $Year $Name2
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0

"@

  if (-not $Apply) { Say ("DRY  sh  {0}" -f $path); return }

  $lines = Get-Content -LiteralPath $path
  if ($lines.Count -gt 0 -and $lines[0].StartsWith("#!")) {
    $out = @()
    $out += $lines[0]
    $out += ($hdr.TrimEnd("`r","`n") -split "`r?`n")
    if ($lines.Count -gt 1) { $out += $lines[1..($lines.Count-1)] }
    Set-Content -LiteralPath $path -Value $out -Encoding UTF8
  } else {
    Prepend-Text $path $hdr
  }
  Say ("APPL sh  {0}" -f $path)
}

# Enumerate files; skip .git, tools/old, vendor
$rootFull = (Resolve-Path $Root).Path
$files = Get-ChildItem -LiteralPath $rootFull -Recurse -File -ErrorAction Stop |
  Where-Object {
    $_.FullName -notmatch '\\\.git\\' -and
    $_.FullName -notmatch '\\tools\\old\\' -and
    $_.FullName -notmatch '\\vendor\\' -and
    ($_.Name -match '\.go$' -or $_.Name -match '\.ps1$' -or $_.Name -match '\.sh$')
  }

foreach ($f in $files) {
  if ($f.Name -match '\.go$') { Add-GoHeader $f.FullName; continue }
  if ($f.Name -match '\.ps1$') { Add-PsHeader $f.FullName; continue }
  if ($f.Name -match '\.sh$') { Add-ShHeader $f.FullName; continue }
}

Say "DONE"
Say ("Mode: {0}" -f ($(if ($Apply) { "APPLY" } else { "DRY-RUN" })))