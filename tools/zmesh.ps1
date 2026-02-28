param(
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

# この zmesh.ps1 があるディレクトリを「ツール置き場」とみなす
$toolDir = Split-Path -Parent $MyInvocation.MyCommand.Path

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

function Show-Help {
@"
zmesh - orchestrator/agent helper for ScaleFS

USAGE
  zmesh <command> [options]

COMMANDS
  init         Initialize zmesh config skeleton (creates/updates zmesh.conf and zmesh.d/)
  start        Start zmesh agent (foreground)
  stop         Stop zmesh agent (best-effort)
  status       Show local status / quick diagnostics
  doctor       Run environment checks (paths, permissions, zfs availability)
  root         Manage ScaleFS roots (add/list/remove)
  scalefs      Proxy to scalefs tool (run ""zmesh scalefs help"" for details)
  virtualpath  Manage virtual path mapping (add/list/remove/doctor)
  apply        Apply virtualpath rules (apply-virtualpath)
  help         Show this help

COMMON OPTIONS
  -h, --help   Show help for zmesh or for a subcommand

DETAILS
  For subcommand details:
    zmesh <command> --help

  To see scalefs help from zmesh:
    zmesh scalefs help

COMMAND HELP + EXAMPLES

  zmesh init
    Initialize config skeleton.
    Options (typical):
      -c, --config PATH      Config path (default: .\zmesh.conf or platform default)
      -n, --node ID          Node id (default: hostname)
      -s, --site NAME        Site name (default: default)
    Examples:
      zmesh init
      zmesh init -c .\zmesh.conf -n node-01 -s site-a

  zmesh start
    Start agent (foreground).
    Options:
      -c, --config PATH      Config file path
    Examples:
      zmesh start -c .\zmesh.conf

  zmesh stop
    Stop agent (best-effort).
    Examples:
      zmesh stop

  zmesh status
    Show local status.
    Examples:
      zmesh status

  zmesh doctor
    Run environment checks.
    Examples:
      zmesh doctor

  zmesh root add
    Register a ScaleFS root (alias -> path).
    Options:
      -a, --alias NAME       Root alias
      -p, --path PATH        Root path
    Examples:
      zmesh root add -a default -p ""$HOME\scalefs""

  zmesh root list
    List registered roots.
    Examples:
      zmesh root list

  zmesh root remove
    Remove a registered root.
    Options:
      -a, --alias NAME       Root alias
      -y, --yes              Non-interactive
    Examples:
      zmesh root remove -a default -y

  zmesh scalefs
    Proxy to scalefs entry.
    Examples:
      zmesh scalefs help
      zmesh scalefs add -n DemoCell

  zmesh virtualpath
    Manage virtualpath rules (virtualpath.d).
    Subcommands:
      add | list | remove | doctor
    Examples:
      zmesh virtualpath help
      zmesh virtualpath list

  zmesh apply
    Apply virtualpath rules (apply-virtualpath).
    Options depend on apply-virtualpath tool.
    Examples:
      zmesh apply
      zmesh apply --help
"@ | Write-Host
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
    if (-not $rest -or $rest.Count -lt 1) { Show-Help; exit 2 }
    $sub = $rest[0]
    $subArgs = @()
    if ($rest.Count -gt 1) { $subArgs = $rest[1..($rest.Count-1)] }

    switch ($sub) {
      "add"    { Run-Script "add-root.ps1"    $subArgs }
      "list"   { Run-Script "list-root.ps1"   $subArgs }
      "remove" { Run-Script "remove-root.ps1" $subArgs }
      "rm"     { Run-Script "remove-root.ps1" $subArgs }
      "help"   { Show-Help; exit 0 }
      default  { Show-Help; exit 2 }
    }
  }

  "scalefs" {
    # zmesh から scalefs を呼べるようにする
    Run-Script "scalefs.ps1" $rest
  }

  "virtualpath" {
    if (-not $rest -or $rest.Count -lt 1) {
      Write-Host "Usage: zmesh virtualpath {add|list|remove|doctor}"
      exit 2
    }
    $sub = $rest[0]
    $subArgs = @()
    if ($rest.Count -gt 1) { $subArgs = $rest[1..($rest.Count-1)] }

    switch ($sub) {
      "add"    { Run-Script "add-virtualpath.ps1"    $subArgs }
      "list"   { Run-Script "list-virtualpath.ps1"   $subArgs }
      "remove" { Run-Script "remove-virtualpath.ps1" $subArgs }
      "rm"     { Run-Script "remove-virtualpath.ps1" $subArgs }
      "doctor" { Run-Script "doctor-virtualpath.ps1" $subArgs }
      "help"   { Write-Host "Usage: zmesh virtualpath {add|list|remove|doctor}"; exit 0 }
      default  { Write-Host "Usage: zmesh virtualpath {add|list|remove|doctor}"; exit 2 }
    }
  }

  "apply" {
    # apply-virtualpath に統一
    Run-Script "apply-virtualpath.ps1" $rest
  }

  default { Show-Help; exit 2 }
}