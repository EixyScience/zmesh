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

COMMANDS
  init         Create skeleton for a scalefs body in the current directory
  add          Create a new scalefs body under a registered root (name + shortid)
  list         List scalefs bodies under registered roots
  remove       Remove a scalefs body (best-effort; may refuse if mounted)
  manifest     Output scalefs body manifest (metadata/config summary)
  clean        Cleanup runtime/state artifacts (and optional ZFS destroy)
  mount        Mount scalefs main (ZFS if available; otherwise no-op/placeholder)
  umount       Unmount scalefs main (ZFS if available; otherwise no-op/placeholder)
  snapshot     Create a snapshot (ZFS-only for now)
  sync         Sync snapshot to peer (ZFS-only placeholder for now)
  help         Show this help

COMMON OPTIONS
  -h, --help   Show help for scalefs or for a subcommand

DETAILS
  For subcommand details:
    scalefs <command> --help

COMMAND HELP + EXAMPLES

  scalefs init
    Create skeleton in current directory.
    Examples:
      scalefs init

  scalefs add
    Create new body under a root.
    Options:
      -Root, -r PATH/ALIAS     (current implementation uses path; alias support may be added)
      -Name, -n NAME
      -Pool, --pool POOL
      -NoZfs, --no-zfs
    Examples:
      scalefs add -Name DemoCell
      scalefs add -Root "$HOME\scalefs" -Name DemoCell -NoZfs

  scalefs list
    List bodies.
    Options:
      -Root, -r ALIAS
      -Id,   -i SUBSTR
      -Full
    Examples:
      scalefs list
      scalefs list -r default -Full

  scalefs remove
    Remove a body.
    Options:
      -Id,   -i ID
      -Root, -r ALIAS
      -KeepZfs
      -Yes,  -y
    Examples:
      scalefs remove -i democell.28e671 -r default -y

  scalefs manifest
    Output body manifest.
    Options:
      -Path, -p PATH   ('.' allowed)
      -Id,   -i ID
      -Root, -r ALIAS
      -Format, -f json|ini
    Examples:
      scalefs manifest -p .
      scalefs manifest -i democell.28e671 -r default -f ini

  scalefs clean
    Cleanup artifacts (default: runtime only).
    Options:
      -Path, -p PATH   ('.' allowed)
      -Id,   -i ID
      -Root, -r ALIAS
      -DryRun
      -Force
      -Zfs            (requires -Force)
      -Yes, -y
    Examples:
      scalefs clean -i democell.28e671 -DryRun
      scalefs clean -i democell.28e671 -Force -Yes
      scalefs clean -i democell.28e671 -Force -Zfs -Yes
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

  "clone" { Run-Script "clone-scalefs.ps1" $rest }
  "move" { Run-Script "move-scalefs.ps1" $rest }
  "snapshot" { Run-Script "snapshot-scalefs.ps1" $rest }
  "sync" { Run-Script "sync-scalefs.ps1" $rest }

  default { Show-Help; exit 2 }
}