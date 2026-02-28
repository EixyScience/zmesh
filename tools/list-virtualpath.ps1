#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [Alias("f")]
  [string]$File,

  [ValidateSet("table","raw")]
  [string]$Format = "table"
)

function Say($s){ Write-Host $s }
function Die($s){ throw $s }

$ZCONF_DIR = $env:ZCONF_DIR
if ([string]::IsNullOrWhiteSpace($ZCONF_DIR)) { $ZCONF_DIR = Join-Path $HOME ".zmesh" }
$confDir = Join-Path $ZCONF_DIR "virtualpath.d"

if (-not (Test-Path $confDir)) {
  Say "(no config dir) $confDir"
  exit 0
}

$files = @()
if ($File) {
  $p = Join-Path $confDir $File
  if (-not (Test-Path $p)) { Die "missing file: $p" }
  $files = @($p)
} else {
  $files = Get-ChildItem -LiteralPath $confDir -Filter "*.conf" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
}

if (-not $files -or $files.Count -eq 0) {
  Say "(no rules)"
  exit 0
}

if ($Format -eq "raw") {
  foreach ($f in $files) {
    Say "== $f =="
    Get-Content -LiteralPath $f
    Say ""
  }
  exit 0
}

Say "vpath | target | file"
Say "----- | ------ | ----"

$hdrRegex = '^\[vpath\s+"([^"]+)"\]\s*$'
$targetRegex = '^target\s*=\s*(.*)$'

foreach ($f in $files) {
  $v = $null
  $t = $null

  foreach ($line in Get-Content -LiteralPath $f) {
    $s = $line.Trim()
    if ($s -eq "" -or $s.StartsWith("#") -or $s.StartsWith(";")) { continue }

    $m = [regex]::Match($s, $hdrRegex)
    if ($m.Success) {
      if ($v -and $t) { Say ("{0} | {1} | {2}" -f $v, $t, $f) }
      $v = $m.Groups[1].Value
      $t = $null
      continue
    }

    if ($v) {
      $m2 = [regex]::Match($s, $targetRegex)
      if ($m2.Success) { $t = $m2.Groups[1].Value.Trim(); continue }
    }
  }

  if ($v -and $t) { Say ("{0} | {1} | {2}" -f $v, $t, $f) }
}