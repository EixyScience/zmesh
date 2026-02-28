param(
  [Parameter(ValueFromRemainingArguments=$true)]
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
  init        Create skeleton for a scalefs body in the current directory
  add         Create a new scalefs body under a registered root (name + shortid)
  list        List scalefs bodies under registered roots
  remove      Remove a scalefs body (best-effort; may refuse if mounted)
  mount       Mount scalefs main (ZFS if available; otherwise no-op/placeholder)
  umount      Unmount scalefs main (ZFS if available; otherwise no-op/placeholder)
  snapshot    Create a snapshot (ZFS-only for now)
  sync        Sync snapshot to peer (ZFS-only placeholder for now)
  help        Show this help

OPTIONS (typical)
  -h, --help              Show help
  -r, --root NAME         Root alias/name (for add/list/remove)
  -n, --name NAME         Human name (normalized); used with add
  -i, --id ID             Full scalefs id (name.shortid); used with remove/mount/umount
  -p, --path PATH         Explicit path (override root resolution) when applicable

EXAMPLES
  scalefs add -r test -n DemoCell
  scalefs list
  scalefs remove -i democell.17ded8
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