#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [string]$Path = "",
  [string]$Id   = "",
  [switch]$DryRun,
  [switch]$Force,
  [switch]$Zfs,
  [switch]$Help
)

function Show-Help {
@"
clean - cleanup runtime/state artifacts of a scalefs body

USAGE
  scalefs clean [options]

COMMAND + OPTIONS
  scalefs clean -Path, -p DIR
      Explicit scalefs body directory

  scalefs clean -Id,   -i ID
      Resolve scalefs body directory by ID (name.shortid) via registered roots

  scalefs clean -DryRun
      Show what would be removed, do nothing

  scalefs clean -Force
      Allow removing directories/files (still avoids ZFS destroy unless -Zfs)

  scalefs clean -Zfs
      Also attempt ZFS unmount/destroy if scalefs.ini has [zfs] enabled=true and dataset=...
      Requires -Force. Best-effort.

  scalefs clean -Help
      Show this help

WHAT IS CLEANED (default)
  - scalefs.runtime.d\*        (safe)
  - scalefs.state\tmp*         (safe if exists)
  - scalefs.state\cache*       (safe if exists)
  - scalefs.state\logs*        (optional if exists)

EXAMPLES
  scalefs clean -Path C:\scalefsroot\democell.17ded8 -DryRun
  scalefs clean -Id democell.17ded8 -Force
  scalefs clean -Id democell.17ded8 -Force -Zfs
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }

function Read-RootConfigs {
  $confDir = Join-Path $HOME ".zmesh\zmesh.d"
  if (-not (Test-Path $confDir)) { return @() }

  $files = Get-ChildItem -Path $confDir -Filter "root.*.conf" -File -ErrorAction SilentlyContinue
  $roots = @()

  foreach ($f in $files) {
    $txt = Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue
    $alias = ($txt | Where-Object { $_ -match '^\s*alias\s*=' } | Select-Object -First 1)
    $path  = ($txt | Where-Object { $_ -match '^\s*path\s*=' }  | Select-Object -First 1)
    if ($alias -and $path) {
      $a = ($alias -replace '^\s*alias\s*=\s*','').Trim()
      $p = ($path  -replace '^\s*path\s*=\s*','').Trim()
      if ($a -and $p) {
        $roots += [pscustomobject]@{ Alias=$a; Path=$p }
      }
    }
  }
  return $roots
}

function Resolve-ById([string]$id) {
  foreach ($r in (Read-RootConfigs)) {
    $d = Join-Path $r.Path $id
    if (Test-Path $d) { return (Resolve-Path $d).Path }
  }
  return ""
}

function Ini-Get([string]$file, [string]$section, [string]$key) {
  # tiny INI parser: only key=value, no includes
  $lines = Get-Content -LiteralPath $file -ErrorAction SilentlyContinue
  $in = $false
  foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ($t -match '^\[') {
      $in = ($t -ieq "[$section]")
      continue
    }
    if ($in -and $t -match ("^{0}\s*=" -f [regex]::Escape($key))) {
      return ($t -replace '^[^=]+=', '').Trim()
    }
  }
  return ""
}

# Resolve DIR
$dir = $Path
if (-not $dir) {
  if ($Id) {
    $dir = Resolve-ById $Id
    if (-not $dir) { throw "cannot resolve id: $Id (check $HOME\.zmesh\zmesh.d\root.*.conf)" }
  } else {
    $dir = (Get-Location).Path
  }
}

if (-not (Test-Path $dir)) { throw "no such dir: $dir" }
$ini = Join-Path $dir "scalefs.ini"
if (-not (Test-Path $ini))  { throw "not a scalefs body (missing scalefs.ini): $dir" }

Write-Host ("clean: dir={0} dry_run={1} force={2} zfs={3}" -f $dir, $DryRun.IsPresent, $Force.IsPresent, $Zfs.IsPresent)

# ZFS optional
if ($Zfs) {
  if (-not $Force) { throw "-Zfs requires -Force" }

  $enabled = (Ini-Get $ini "zfs" "enabled")
  $dataset = (Ini-Get $ini "zfs" "dataset")

  if ($enabled -ieq "true" -and $dataset) {
    Write-Host "ZFS: dataset=$dataset"
    if ($DryRun) {
      Write-Host "ZFS would: zfs umount '$dataset' ; zfs destroy -r '$dataset'"
    } else {
      try { & zfs.exe umount $dataset 2>$null | Out-Null } catch {}
      try { & zfs.exe destroy -r $dataset 2>$null | Out-Null } catch {}
    }
  } else {
    Write-Host "ZFS: not enabled or dataset not set in scalefs.ini; skipping"
  }
}

# Targets
$targets = @(
  Join-Path $dir "scalefs.runtime.d",
  Join-Path $dir "scalefs.state\tmp",
  Join-Path $dir "scalefs.state\cache",
  Join-Path $dir "scalefs.state\log",
  Join-Path $dir "scalefs.state\logs"
)

function Plan([string]$p) {
  if (Test-Path $p) { Write-Host "RM $p" }
}

function DoRemove([string]$p) {
  if (-not (Test-Path $p)) { return }

  if (-not $Force) {
    # safe default: only allow runtime.d
    if ($p -like (Join-Path $dir "scalefs.runtime.d*")) {
      Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
    } else {
      Write-Host "SKIP (need -Force) $p"
    }
    return
  }

  Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
}

if ($DryRun) {
  foreach ($p in $targets) { Plan $p }
  Write-Host "OK: dry-run only"
  exit 0
}

foreach ($p in $targets) { DoRemove $p }

Write-Host "OK: cleaned (best-effort)"