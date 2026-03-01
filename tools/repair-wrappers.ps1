# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0# tools/repair-wrappers.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# param を使わない “入口” zmesh.ps1
$zmeshWrapper = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolBase = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Help {
@"
zmesh - orchestrator/agent helper for ScaleFS

USAGE
  zmesh <command> [options]

COMMANDS
  init        Initialize zmesh config skeleton (creates/updates zmesh.conf and zmesh.d/)
  start       Start zmesh agent (foreground)
  stop        Stop zmesh agent (best-effort)
  status      Show local status / quick diagnostics
  doctor      Run environment checks (paths, permissions, zfs availability)
  root        Manage ScaleFS roots (add/list/remove)
  scalefs     Proxy to scalefs tool (run ""zmesh scalefs help"" for details)
  help        Show this help

NOTES
  - To see scalefs help from zmesh:
      zmesh scalefs help
"@ | Write-Host
}

function Resolve-ToolPath([string]$name) {
  $p1 = Join-Path $toolBase ("tools\" + $name)
  if (Test-Path $p1) { return $p1 }
  $p2 = Join-Path $toolBase $name
  if (Test-Path $p2) { return $p2 }
  throw "missing script: $name (searched: $p1 and $p2)"
}

function Run-Script([string]$name, [string[]]$passArgs) {
  $path = Resolve-ToolPath $name
  & $path @passArgs
  exit $LASTEXITCODE
}

if (-not $args -or $args.Count -eq 0 -or $args[0] -in @("help","-h","--help")) {
  Show-Help
  exit 0
}

$cmd  = [string]$args[0]
$rest = @()
if ($args.Count -gt 1) { $rest = @($args[1..($args.Count-1)]) }

switch ($cmd) {
  "init"   { Run-Script "zmesh-init.ps1"   $rest }
  "start"  { Run-Script "zmesh-start.ps1"  $rest }
  "stop"   { Run-Script "zmesh-stop.ps1"   $rest }
  "status" { Run-Script "zmesh-status.ps1" $rest }
  "doctor" { Run-Script "doctor.ps1"       $rest }

  "root" {
    if (-not $rest -or $rest.Count -lt 1) { Show-Help; exit 2 }
    $sub = [string]$rest[0]
    $subArgs = @()
    if ($rest.Count -gt 1) { $subArgs = @($rest[1..($rest.Count-1)]) }

    switch ($sub) {
      "add"    { Run-Script "add-root.ps1"    $subArgs }
      "list"   { Run-Script "list-root.ps1"   $subArgs }
      "remove" { Run-Script "remove-root.ps1" $subArgs }
      default  { Show-Help; exit 2 }
    }
  }

  "scalefs" {
    Run-Script "scalefs.ps1" $rest
  }

  default { Show-Help; exit 2 }
}
'@

# 直下 zmesh.ps1 と tools/zmesh.ps1 を両方上書き
$targets = @(
  (Join-Path $repo "zmesh.ps1"),
  (Join-Path $repo "tools\zmesh.ps1")
)

foreach ($t in $targets) {
  $dir = Split-Path -Parent $t
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }

  # UTF-8 (BOMなし) で確実に書く
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($t, $zmeshWrapper, $utf8NoBom)

  Write-Host "WROTE: $t"
}

# 検証：先頭50行に "param(" が残っていないことを確認
foreach ($t in $targets) {
  $head = (Get-Content -LiteralPath $t -TotalCount 50) -join "`n"
  if ($head -match '^\s*param\s*\(') {
    throw "param() still present in: $t"
  }
  Write-Host "OK: no param() in head: $t"
}

Write-Host "DONE. Now run: .\tools\test-all.ps1"