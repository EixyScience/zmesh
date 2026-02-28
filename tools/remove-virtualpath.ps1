#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [Alias("v")]
  [Parameter(Mandatory=$true)]
  [string]$VPath,

  [Alias("f")]
  [string]$File = "virtualpath.local.conf",

  [switch]$Yes,
  [switch]$DryRun
)

function Die($s){ throw $s }
function Say($s){ Write-Host $s }

$ZCONF_DIR = $env:ZCONF_DIR
if ([string]::IsNullOrWhiteSpace($ZCONF_DIR)) { $ZCONF_DIR = Join-Path $HOME ".zmesh" }
$confDir = Join-Path $ZCONF_DIR "virtualpath.d"
$confPath = Join-Path $confDir $File

if (-not (Test-Path -LiteralPath $confPath)) { Die "missing file: $confPath" }

# normalize vpath
$VPath = $VPath.Trim().TrimStart('\','/')
$VPath = $VPath -replace '\\','/'
$VPath = ($VPath -replace '/+','/').TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($VPath)) { Die "VPath becomes empty after normalization" }

if (-not $Yes) {
  $ans = Read-Host "Remove vpath '$VPath' from $confPath ? [y/N]"
  if ($ans -notin @("y","Y","yes","YES")) { Die "aborted by user" }
}

$content = Get-Content -LiteralPath $confPath -ErrorAction Stop

$out = New-Object System.Collections.Generic.List[string]
$skip = $false
$found = $false

$hdrRegex = '^\[vpath\s+"([^"]+)"\]\s*$'

foreach ($line in $content) {
  $m = [regex]::Match($line.TrimEnd(), $hdrRegex)
  if ($m.Success) {
    $name = $m.Groups[1].Value
    if ($name -eq $VPath) { $skip = $true; $found = $true; continue }
    if ($skip) { $skip = $false }
  }
  if (-not $skip) { $out.Add($line) }
}

if (-not $found) {
  Say "(not found) vpath=$VPath in $confPath"
  exit 0
}

if ($DryRun) {
  Say "DRYRUN write: $confPath"
  $out | ForEach-Object { Say $_ }
  exit 0
}

$tmp = "$confPath.tmp"
$out | Set-Content -LiteralPath $tmp -Encoding UTF8
Move-Item -LiteralPath $tmp -Destination $confPath -Force

Say "OK removed: vpath=$VPath (file=$confPath)"
exit 0