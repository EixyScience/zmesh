param(
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

# この zmesh.ps1 があるディレクトリを「ツール置き場」とみなす
$toolDir = Split-Path -Parent $MyInvocation.MyCommand.Path

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
  virtualpath Manage virtual path rules (add/list/remove/doctor/apply)
  help        Show this help

NOTES
  - To see scalefs help from zmesh:
      zmesh scalefs help

  - To see virtualpath help:
      zmesh virtualpath help

EXAMPLES
  zmesh init
  zmesh start -c .\zmesh.conf
  zmesh root add
  zmesh virtualpath apply -Root "$HOME\vroot" -Clean -Yes
"@ | Write-Host
}

function Resolve-ToolPath([string]$name) {
  $p1 = Join-Path $toolDir ("tools\" + $name)
  if (Test-Path $p1) { return $p1 }
  $p2 = Join-Path $toolDir $name
  if (Test-Path $p2) { return $p2 }
  throw "missing script: $name (searched: $p1 and $p2)"
}

function Run-Script([string]$name, [string[]]$passArgs) {
  $path = Resolve-ToolPath $name
  & $path @passArgs
  exit $LASTEXITCODE
}

if (-not $Args -or $Args[0] -in @("help","-h","--help")) {
  Show-Help
  exit 0
}

$cmd = $Args[0]
$rest = @()
if ($Args.Length -gt 1) { $rest = $Args[1..($Args.Length-1)] }

switch ($cmd) {
  "init"   { Run-Script "zmesh-init.ps1" $rest }
  "start"  { Run-Script "zmesh-start.ps1" $rest }
  "stop"   { Run-Script "zmesh-stop.ps1" $rest }
  "status" { Run-Script "zmesh-status.ps1" $rest }
  "doctor" { Run-Script "doctor.ps1" $rest }

  "root" {
    if (-not $rest) { Show-Help; exit 2 }
    switch ($rest[0]) {
      "add"    { Run-Script "add-root.ps1"    ($rest | Select-Object -Skip 1) }
      "list"   { Run-Script "list-root.ps1"   ($rest | Select-Object -Skip 1) }
      "remove" { Run-Script "remove-root.ps1" ($rest | Select-Object -Skip 1) }
      "rm"     { Run-Script "remove-root.ps1" ($rest | Select-Object -Skip 1) }
      default  { Show-Help; exit 2 }
    }
  }

  "scalefs" {
    Run-Script "scalefs.ps1" $rest
  }

  "virtualpath" {
    $sub = "help"
    if ($rest.Length -ge 1) { $sub = $rest[0] }

    $subArgs = @()
    if ($rest.Length -gt 1) { $subArgs = $rest[1..($rest.Length-1)] }

    switch ($sub) {
      "add"    { Run-Script "add-virtualpath.ps1" $subArgs }
      "list"   { Run-Script "list-virtualpath.ps1" $subArgs }
      "remove" { Run-Script "remove-virtualpath.ps1" $subArgs }
      "rm"     { Run-Script "remove-virtualpath.ps1" $subArgs }
      "doctor" { Run-Script "doctor-virtualpath.ps1" $subArgs }

      "apply" {
        # Preferred name: tools\virtualpath-apply.ps1
        # Back-compat: tools\apply-virtualpath.ps1
        try {
          Run-Script "virtualpath-apply.ps1" $subArgs
        } catch {
          Run-Script "apply-virtualpath.ps1" $subArgs
        }
      }

      "help" { 
@"
zmesh virtualpath - manage virtual path rules

USAGE
  zmesh virtualpath <subcommand> [options]

SUBCOMMANDS
  add         Add a rule file under virtualpath.d\
  list        List rules
  remove      Remove a rule
  doctor      Diagnostics for virtualpath config
  apply       Apply rules into a vroot (and write manifest; optional -Clean)

APPLY EXAMPLES
  zmesh virtualpath apply -Root "$HOME\vroot"
  zmesh virtualpath apply -Root "$HOME\vroot" -Clean -Yes
"@ | Write-Host
        exit 0
      }

      default {
        Write-Host "Usage: zmesh virtualpath {add|list|remove|doctor|apply|help}"
        exit 2
      }
    }
  }

  default { Show-Help; exit 2 }
}