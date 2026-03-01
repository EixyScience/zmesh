param(
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"
$toolDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Help {
@"
Usage:
  scalefs <command> [args...]

Commands:
  init     -> scalefs-init.ps1
  mount    -> scalefs-mount.ps1
  umount   -> scalefs-umount.ps1
  add      -> add-scalefs.ps1
  list     -> list-scalefs.ps1
  remove   -> remove-scalefs.ps1

(advanced)
  clone    -> clone-scalefs.ps1
  move     -> move-scalefs.ps1
  snapshot -> snapshot-scalefs.ps1
  sync     -> sync-scalefs.ps1
"@
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
  "init"     { Run-Script "scalefs-init.ps1" $rest }
  "mount"    { Run-Script "scalefs-mount.ps1" $rest }
  "umount"   { Run-Script "scalefs-umount.ps1" $rest }
  "add"      { Run-Script "add-scalefs.ps1" $rest }
  "list"     { Run-Script "list-scalefs.ps1" $rest }
  "remove"   { Run-Script "remove-scalefs.ps1" $rest }

  "clone"    { Run-Script "clone-scalefs.ps1" $rest }
  "move"     { Run-Script "move-scalefs.ps1" $rest }
  "snapshot" { Run-Script "snapshot-scalefs.ps1" $rest }
  "sync"     { Run-Script "sync-scalefs.ps1" $rest }

  default { Show-Help; exit 2 }
}