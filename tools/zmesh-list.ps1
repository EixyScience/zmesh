# tools/zmesh-list.ps1
#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scalefs1 = Join-Path $repo "scalefs.ps1"
$scalefs2 = Join-Path $repo "tools\scalefs.ps1"

if (Test-Path $scalefs1) { & $scalefs1 list @args; exit $LASTEXITCODE }
if (Test-Path $scalefs2) { & $scalefs2 list @args; exit $LASTEXITCODE }

throw "missing scalefs.ps1"