# tools/clean-scalefs.ps1
# Clean runtime/state artifacts of a scalefs body.
# Default: safe clean (runtime only).
# With -Force: also clears common state subdirs.
# With -Zfs + -Force: attempt zfs unmount/destroy based on scalefs.ini [zfs].

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib.ps1"

param(
  [string]$Id,
  [string]$Root,
  [string]$Path,
  [switch]$DryRun,
  [switch]$Force,
  [switch]$Zfs,
  [switch]$Yes,
  [switch]$Help
)

function Show-Help {
@"
clean - cleanup runtime/state artifacts of a scalefs body

USAGE
  scalefs clean [options]

COMMAND + OPTIONS
  scalefs clean -Path, -p PATH
      Body directory (contains scalefs.ini). Use '.' for current directory.

  scalefs clean -Id,   -i ID
      Body id (name.shortid). Resolved via registered roots.

  scalefs clean -Root, -r ALIAS
      Root alias to resolve Id (recommended if multiple roots)

  scalefs clean -DryRun
      Show what would be removed, do nothing

  scalefs clean -Force
      Allow removing state caches/logs (still avoids ZFS destroy unless -Zfs)

  scalefs clean -Zfs
      Also attempt ZFS unmount/destroy if scalefs.ini has enabled=true and dataset=...
      Requires -Force. Best-effort.

  scalefs clean -Yes
      Non-interactive (assume yes)

EXAMPLES
  scalefs clean -p .
  scalefs clean -i democell.28e671 -DryRun
  scalefs clean -i democell.28e671 -Force -Yes
  scalefs clean -i democell.28e671 -Force -Zfs -Yes
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }

function Confirm([string]$msg) {
  if ($Yes) { return $true }
  $ans = Read-Host "$msg [y/N]"
  return ($ans -match '^(y|yes)$')
}

function Load-Roots {
  $confDir = ZmeshConfDir
  $d = Join-Path $confDir "zmesh.d"
  if (-not (Test-Path $d)) { return @() }

  $roots = @()
  Get-ChildItem $d -Filter "root.*.conf" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $txt = Get-Content $_.FullName -ErrorAction SilentlyContinue
    $alias = (($txt | Where-Object { $_ -match '^\s*alias\s*=' } | Select-Object -First 1) -replace '^\s*alias\s*=\s*','').Trim()
    $path  = (($txt | Where-Object { $_ -match '^\s*path\s*=' }  | Select-Object -First 1) -replace '^\s*path\s*=\s*','').Trim()
    if ($path) { $roots += [pscustomobject]@{ Alias=$alias; Path=$path } }
  }
  return $roots
}

function Resolve-BodyPath([string]$id,[string]$rootAlias,[string]$p) {
  if ($p) {
    if ($p -eq ".") { return (Get-Location).Path }
    return (Resolve-Path $p).Path
  }
  if (-not $id) { throw "require -Path or -Id" }

  $roots = Load-Roots
  if (-not $roots -or $roots.Count -eq 0) { throw "no roots configured (run: zmesh root add)" }

  if ($rootAlias) {
    $r = $roots | Where-Object { $_.Alias -eq $rootAlias } | Select-Object -First 1
    if (-not $r) { throw "unknown root alias: $rootAlias" }
    return (Join-Path $r.Path $id)
  }

  $cands = @()
  foreach ($r in $roots) {
    $pp = Join-Path $r.Path $id
    if (Test-Path $pp) { $cands += $pp }
  }
  if ($cands.Count -eq 0) { throw "not found: $id" }
  if ($cands.Count -ne 1) { throw "could not resolve id=$id uniquely (specify -Root or -Path)" }
  return $cands[0]
}

function Ini-Get([string]$ini,[string]$section,[string]$key) {
  $sec = "[$section]"
  $in = $false
  foreach ($line in Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue) {
    $t = $line.Trim()
    if ($t -eq $sec) { $in = $true; continue }
    if ($in -and $t.StartsWith("[")) { break }
    if ($in -and $t -match ("^\s*"+[regex]::Escape($key)+"\s*=\s*(.*)$")) {
      return $matches[1].Trim()
    }
  }
  return ""
}

function Plan([string]$p) {
  if (Test-Path $p) { Write-Host "RM $p" }
}

function DoRemove([string]$p) {
  if (-not (Test-Path $p)) { return }
  Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
}

# resolve
$dir = Resolve-BodyPath $Id $Root $Path
if (-not (Test-Path $dir)) { throw "not a directory: $dir" }

$ini = Join-Path $dir "scalefs.ini"
if (-not (Test-Path $ini)) { throw "missing scalefs.ini: $ini" }

$runtime = Join-Path $dir "scalefs.runtime.d"
$state   = Join-Path $dir "scalefs.state"

$targets = New-Object System.Collections.Generic.List[string]
$targets.Add($runtime) | Out-Null

if ($Force) {
  # common state cleanup (best effort)
  $targets.Add((Join-Path $state "tmp"))   | Out-Null
  $targets.Add((Join-Path $state "cache")) | Out-Null
  $targets.Add((Join-Path $state "log"))   | Out-Null
  $targets.Add((Join-Path $state "logs"))  | Out-Null
}

$zEnabled = (Ini-Get $ini "zfs" "enabled")
$zDataset = (Ini-Get $ini "zfs" "dataset")

Write-Host "Target: $dir"
Write-Host "Plan:"
foreach ($t in $targets) { Write-Host "  - remove: $t" }

if ($Zfs) {
  if (-not $Force) { throw "-Zfs requires -Force" }
  if ($zEnabled -ieq "true" -and $zDataset) {
    Write-Host "  - zfs destroy: $zDataset"
  } else {
    Write-Host "  - zfs destroy: (none)"
  }
}

if (-not (Confirm "Proceed?")) { throw "aborted" }

if ($DryRun) {
  foreach ($t in $targets) { Plan $t }
  if ($Zfs -and $zEnabled -ieq "true" -and $zDataset) {
    Write-Host "ZFS would: zfs unmount -f $zDataset ; zfs destroy -r $zDataset"
  }
  Write-Host "OK: dry-run only"
  exit 0
}

# ZFS destroy first (best effort)
if ($Zfs) {
  $zfs = Get-Command zfs.exe -ErrorAction SilentlyContinue
  if ($zfs -and $zEnabled -ieq "true" -and $zDataset) {
    try { & zfs.exe unmount -f $zDataset 2>$null | Out-Null } catch {}
    try { & zfs.exe destroy -r $zDataset 2>$null | Out-Null } catch {}
  }
}

# Remove files/dirs
foreach ($t in $targets) { DoRemove $t }

Write-Host "OK: cleaned (best-effort)"