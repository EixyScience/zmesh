# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [Alias("v")]
  [Parameter(Mandatory=$true)]
  [string]$VPath,

  [Alias("t")]
  [Parameter(Mandatory=$true)]
  [string]$Target,

  [Alias("f")]
  [string]$File = "virtualpath.local.conf",

  [string]$Type = "symlink",

  [switch]$Yes,
  [switch]$DryRun
)

function Die($s){ throw $s }
function Say($s){ Write-Host $s }

$ZCONF_DIR = $env:ZCONF_DIR
if ([string]::IsNullOrWhiteSpace($ZCONF_DIR)) { $ZCONF_DIR = Join-Path $HOME ".zmesh" }
$confDir = Join-Path $ZCONF_DIR "virtualpath.d"
$confPath = Join-Path $confDir $File

if ($Type -ne "symlink") { Die "unsupported -Type '$Type' (only symlink)" }

# normalize vpath: trim leading slashes, unify to backslash for config readability? keep "/" in header is fine.
$VPath = $VPath.Trim()
$VPath = $VPath.TrimStart('\','/')
$VPath = $VPath -replace '\\','/'  # store as forward slashes in conf
$VPath = ($VPath -replace '/+','/').TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($VPath)) { Die "VPath becomes empty after normalization" }

if (-not $DryRun) {
  New-Item -ItemType Directory -Force -Path $confDir | Out-Null
}

# Load existing (or empty)
$content = @()
if (Test-Path -LiteralPath $confPath) {
  $content = Get-Content -LiteralPath $confPath -ErrorAction Stop
}

# Remove existing block for this vpath, then append new block (last-wins)
$out = New-Object System.Collections.Generic.List[string]
$skip = $false

$hdrRegex = '^\[vpath\s+"([^"]+)"\]\s*$'

foreach ($line in $content) {
  $m = [regex]::Match($line.TrimEnd(), $hdrRegex)
  if ($m.Success) {
    $name = $m.Groups[1].Value
    if ($name -eq $VPath) { $skip = $true; continue }
    if ($skip) { $skip = $false }
  }
  if (-not $skip) { $out.Add($line) }
}

# Append block
$out.Add("")
$out.Add("[vpath `"$VPath`"]")
$out.Add("target=$Target")
$out.Add("type=$Type")

if ($DryRun) {
  Say "DRYRUN write: $confPath"
  $out | ForEach-Object { Say $_ }
  exit 0
}

if (-not (Test-Path -LiteralPath $confPath) -and -not $Yes) {
  $ans = Read-Host "Create new config file: $confPath ? [y/N]"
  if ($ans -notin @("y","Y","yes","YES")) { Die "aborted by user" }
}

$tmp = "$confPath.tmp"
$out | Set-Content -LiteralPath $tmp -Encoding UTF8
Move-Item -LiteralPath $tmp -Destination $confPath -Force

Say "OK added: vpath=$VPath -> target=$Target (file=$confPath)"
exit 0