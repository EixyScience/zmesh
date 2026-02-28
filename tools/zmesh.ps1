#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args
)

# この zmesh.ps1 があるディレクトリ（repo root を想定）
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsDir = Join-Path $baseDir "tools"

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
  scalefs     Proxy to scalefs tool (run "zmesh scalefs help" for details)

  virtualpath Manage virtual paths (add/list/remove/doctor/apply)
  help        Show this help

NOTES
  - To see scalefs help from zmesh:
      zmesh scalefs help

VIRTUALPATH SUBCOMMANDS
  zmesh virtualpath add     -VPath <REL> -Target <PATH> [-File <NAME.conf>] [-Yes]
  zmesh virtualpath list    [-File <NAME.conf>] [-Format table|raw]
  zmesh virtualpath remove  -VPath <REL> [-File <NAME.conf>] [-Yes]
  zmesh virtualpath doctor  [-CheckTargets] [-Strict] [-File <NAME.conf>]
  zmesh virtualpath apply   -Root <VROOT> [-DryRun] [-Yes]

EXAMPLES
  zmesh init
  zmesh start -c .\zmesh.conf
  zmesh root add -a default -p "$HOME\scalefs"

  zmesh virtualpath add -VPath "hobby/car" -Target "$HOME\scalefs\democell.abcdef\main" -Yes
  zmesh virtualpath apply -Root "$HOME\vroot" -Yes
"@ | Write-Host
}

function Resolve-ToolPath([string]$name) {
  $p1 = Join-Path $toolsDir $name
  if (Test-Path -LiteralPath $p1) { return $p1 }

  $p2 = Join-Path $baseDir $name
  if (Test-Path -LiteralPath $p2) { return $p2 }

  throw "missing script: $name (searched: $p1 and $p2)"
}

function Run-Script([string]$name, [string[]]$passArgs) {
  $path = Resolve-ToolPath $name
  & $path @passArgs
  exit $LASTEXITCODE
}

if (-not $Args -or $Args.Count -eq 0 -or $Args[0] -in @("help","-h","--help")) {
  Show-Help
  exit 0
}

$cmd = $Args[0]
$rest = @()
if ($Args.Count -gt 1) { $rest = $Args[1..($Args.Count-1)] }

switch ($cmd) {
  "init"   { Run-Script "zmesh-init.ps1" $rest }
  "start"  { Run-Script "zmesh-start.ps1" $rest }
  "stop"   { Run-Script "zmesh-stop.ps1" $rest }
  "status" { Run-Script "zmesh-status.ps1" $rest }
  "doctor" { Run-Script "doctor.ps1" $rest }

  "root" {
    if (-not $rest -or $rest.Count -eq 0) { Show-Help; exit 2 }
    $sub = $rest[0]
    $args2 = @()
    if ($rest.Count -gt 1) { $args2 = $rest[1..($rest.Count-1)] }
    switch ($sub) {
      "add"    { Run-Script "add-root.ps1"    $args2 }
      "list"   { Run-Script "list-root.ps1"   $args2 }
      "remove" { Run-Script "remove-root.ps1" $args2 }
      "rm"     { Run-Script "remove-root.ps1" $args2 }
      default  { Show-Help; exit 2 }
    }
  }

  "scalefs" {
    Run-Script "scalefs.ps1" $rest
  }

  "virtualpath" {
    $sub = "help"
    $args2 = @()
    if ($rest.Count -ge 1) { $sub = $rest[0] }
    if ($rest.Count -gt 1) { $args2 = $rest[1..($rest.Count-1)] }

    switch ($sub) {
      "add"    { Run-Script "add-virtualpath.ps1" $args2 }
      "list"   { Run-Script "list-virtualpath.ps1" $args2 }
      "remove" { Run-Script "remove-virtualpath.ps1" $args2 }
      "rm"     { Run-Script "remove-virtualpath.ps1" $args2 }
      "doctor" { Run-Script "doctor-virtualpath.ps1" $args2 }
      "apply"  { Run-Script "apply-virtualpath.ps1" $args2 }
      "help"   { Show-Help; exit 0 }
      "-h"     { Show-Help; exit 0 }
      "--help" { Show-Help; exit 0 }
      default  { Write-Host "Usage: zmesh virtualpath {add|list|remove|doctor|apply}"; exit 2 }
    }
  }

  default { Show-Help; exit 2 }
}