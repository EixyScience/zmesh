param(
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

# この zmesh.ps1 があるディレクトリを「ツール置き場」とみなす
$toolDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Help {
@"
Usage:
  zmesh <command> [args...]

Commands:
  init                -> zmesh-init.ps1
  start               -> zmesh-start.ps1
  stop                -> zmesh-stop.ps1
  status              -> zmesh-status.ps1
  doctor              -> doctor.ps1

  root add            -> add-root.ps1
  root list           -> list-root.ps1
  root remove         -> remove-root.ps1

  scalefs <...>       -> forward to scalefs.ps1 (zmesh scalefs ...)

Examples:
  .\zmesh.ps1 init
  .\zmesh.ps1 start
  .\zmesh.ps1 root add
  .\zmesh.ps1 scalefs add
  .\zmesh.ps1 scalefs list
"@
}

function Run-Script([string]$name, [string[]]$passArgs) {
  $path = Join-Path $toolDir $name
  if (-not (Test-Path $path)) {
    throw "missing script: $name (expected at $path)"
  }
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