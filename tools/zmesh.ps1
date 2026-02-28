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
  help        Show this help

NOTES
  - To see scalefs help from zmesh:
      zmesh scalefs help

OPTIONS (common)
  -h, --help        Show help
  -v, --verbose     Verbose output (if supported)
  -C, --chdir DIR   Run as if started in DIR (if supported)

EXAMPLES
  zmesh init
  zmesh start -c .\zmesh.conf
  zmesh root add -a default -p "$HOME\scalefs"
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
      "add"    { Run-Script "add-root.ps1"    $rest[1..($rest.Length-1)] }
      "list"   { Run-Script "list-root.ps1"   $rest[1..($rest.Length-1)] }
      "remove" { Run-Script "remove-root.ps1" $rest[1..($rest.Length-1)] }
      default  { Show-Help; exit 2 }
    }
  }

  "scalefs" {
    # zmesh から scalefs を呼べるようにする
    Run-Script "scalefs.ps1" $rest
  }

  default { Show-Help; exit 2 }
}