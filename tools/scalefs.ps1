param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"
$toolDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Help {
  @"
scalefs - ScaleFS local filesystem body helper

USAGE
  scalefs <command> [options]
  scalefs help

COMMANDS (one-line)
  init        Create skeleton for a scalefs body in the current directory
  add         Create a new scalefs body under a registered root (name + shortid)
  list        List scalefs bodies under registered roots
  remove      Remove a scalefs body (best-effort; may refuse if mounted)
  mount       Mount scalefs main (ZFS if available; otherwise no-op/placeholder)
  umount      Unmount scalefs main (ZFS if available; otherwise no-op/placeholder)
  manifest    Print a manifest for a scalefs body (json/ini)
  clean       Clean runtime/state; optionally destroy zfs/body
  snapshot    Create a snapshot (ZFS-only for now)
  sync        Sync snapshot to peer (ZFS-only placeholder for now)
  help        Show this help

GLOBAL OPTIONS
  -h, --help  Show help

COMMAND HELP / EXAMPLES
  scalefs manifest -h
  scalefs clean -h

NOTES
  - To see help via zmesh:
      zmesh scalefs help
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

if (-not $Args -or $Args[0] -in @("help", "-h", "--help")) {
  Show-Help
  exit 0
}

$cmd = $Args[0]
$rest = @()
if ($Args.Length -gt 1) { $rest = $Args[1..($Args.Length - 1)] }

switch ($cmd) {
  "init" { Run-Script "scalefs-init.ps1" $rest }
  "mount" { Run-Script "scalefs-mount.ps1" $rest }
  "umount" { Run-Script "scalefs-umount.ps1" $rest }
  "add" { Run-Script "add-scalefs.ps1" $rest }
  "list" { Run-Script "list-scalefs.ps1" $rest }
  "remove" { Run-Script "remove-scalefs.ps1" $rest }

  "manifest" { Run-Script "manifest-scalefs.ps1" $rest }
  "clean" { Run-Script "clean-scalefs.ps1" $rest }

  "snapshot" { Run-Script "snapshot-scalefs.ps1" $rest }
  "sync" { Run-Script "sync-scalefs.ps1" $rest }

  default { Show-Help; exit 2 }
}