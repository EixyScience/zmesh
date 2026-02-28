# tools/add-scalefs.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib.ps1"

param(
  [string]$Root,
  [string]$Name,
  [string]$Pool,
  [switch]$NoZfs
)

function Normalize-Name([string]$s) {
  if ($null -eq $s) { return "" }
  $t = $s.ToLowerInvariant()
  # allow: a-z 0-9 . _ -
  $t = ($t -replace '[^a-z0-9._-]', '')
  $t = ($t -replace '^[^a-z0-9]+', '')
  return $t
}

function ShortID6() {
  return ([guid]::NewGuid().ToString("N")).Substring(0,6)
}

function Have-Zfs() {
  return $null -ne (Get-Command zfs.exe -ErrorAction SilentlyContinue) -and
         $null -ne (Get-Command zpool.exe -ErrorAction SilentlyContinue)
}

function Default-Pool() {
  try {
    $out = & zpool.exe list -H -o name 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) {
      $first = ($out | Select-Object -First 1).Trim()
      if ($first) { return $first }
    }
  } catch {}
  return ""
}

function Ensure-ZfsDataset([string]$ds) {
  # create parents too
  & zfs.exe create -p $ds 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "zfs create failed: $ds"
  }
}

function Set-ZfsMountpoint([string]$ds, [string]$mp) {
  & zfs.exe set "mountpoint=$mp" $ds 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "zfs set mountpoint failed: $ds -> $mp"
  }
  # mount is best-effort; on Windows mountpoint may trigger drive letter mapping
  & zfs.exe mount $ds 2>$null | Out-Null
}

# ---------------------------
# Inputs (interactive fallback)
# ---------------------------
if (-not $Root) { $Root = Ask "Root path" "$HOME\scalefs" }
if (-not $Name) { $Name = Ask "Name" "data" }

$NameN = Normalize-Name $Name
if (-not $NameN) { throw "invalid name after normalization: '$Name'" }

$sid = ShortID6()
$id  = "$NameN.$sid"
$dir = Join-Path $Root $id

# Skeleton
EnsureDir (Join-Path $dir "main")
EnsureDir (Join-Path $dir "scalefs.state")
EnsureDir (Join-Path $dir "scalefs.global.d")
EnsureDir (Join-Path $dir "scalefs.local.d")
EnsureDir (Join-Path $dir "scalefs.runtime.d")

# ZFS (flat): POOL/scalefs/<name>-<sid>
$usedZfs = $false
$ds = ""

if (-not $NoZfs -and (Have-Zfs)) {
  if (-not $Pool) { $Pool = Default-Pool }
  if ($Pool) {
    try {
      $base = "$Pool/scalefs"
      $ds = "$base/$NameN-$sid"

      Ensure-ZfsDataset $base
      Ensure-ZfsDataset $ds

      $mp = (Join-Path $dir "main")
      Set-ZfsMountpoint $ds $mp

      $usedZfs = $true
    } catch {
      # fallback to generic skeleton only
      $usedZfs = $false
      $ds = ""
    }
  }
}

# scalefs.ini (keep simple + portable)
$iniPath = Join-Path $dir "scalefs.ini"
@"
[scalefs]
id=$id
name=$NameN
shortid=$sid

[paths]
state_dir=./scalefs.state
watch_root=./main

[zfs]
enabled=$($usedZfs.ToString().ToLower())
pool=$Pool
dataset=$ds
"@ | Set-Content -Encoding UTF8 $iniPath

Write-Host "OK scalefs created: $dir"
if ($usedZfs) {
  Write-Host "  zfs dataset: $ds"
  Write-Host "  mountpoint : $(Join-Path $dir "main")"
} else {
  Write-Host "  zfs: disabled or unavailable (generic skeleton only)"
}