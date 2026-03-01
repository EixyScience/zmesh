# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0param(
  [string]$Dirs = "",
  [string]$Files = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-Rel([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $null }
  # If rooted, keep. If relative, resolve from current directory (NOT HOME).
  if ([System.IO.Path]::IsPathRooted($p)) {
    return [System.IO.Path]::GetFullPath($p)
  }
  $cwd = (Get-Location).Path
  return [System.IO.Path]::GetFullPath((Join-Path $cwd $p))
}

function Touch-Empty([string]$path) {
  $dir = Split-Path -Parent $path
  if (-not [string]::IsNullOrWhiteSpace($dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  if (-not (Test-Path -LiteralPath $path)) {
    # create empty file as bytes
    [System.IO.File]::WriteAllBytes($path, [byte[]]@())
  }
}

if (-not [string]::IsNullOrWhiteSpace($Dirs)) {
  $Dirs.Split(",") | ForEach-Object {
    $p = $_.Trim()
    if ($p -ne "") {
      $abs = Resolve-Rel $p
      New-Item -ItemType Directory -Force -Path $abs | Out-Null
    }
  }
}

if (-not [string]::IsNullOrWhiteSpace($Files)) {
  $Files.Split(",") | ForEach-Object {
    $p = $_.Trim()
    if ($p -ne "") {
      $abs = Resolve-Rel $p
      Touch-Empty $abs
    }
  }
}

Write-Host "ok"