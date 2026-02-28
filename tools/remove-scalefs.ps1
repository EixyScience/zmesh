Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib.ps1"

param(
  [string]$Name,      # name.shortid
  [switch]$Yes
)

function Load-Roots {
  $confDir = ZmeshConfDir
  $d = Join-Path $confDir "zmesh.d"
  if (-not (Test-Path $d)) { return @() }

  $roots = @()
  Get-ChildItem $d -Filter "root.*.conf" -ErrorAction SilentlyContinue | ForEach-Object {
    $txt = Get-Content $_.FullName
    $alias = (($txt | Where-Object { $_ -match '^alias=' } | Select-Object -First 1) -replace '^alias=','').Trim()
    $path  = (($txt | Where-Object { $_ -match '^path=' }  | Select-Object -First 1) -replace '^path=','').Trim()
    if ($path) { $roots += [pscustomobject]@{ Alias=$alias; Path=$path } }
  }
  return $roots
}

function Find-ScalefsDir([string]$sid) {
  foreach ($r in (Load-Roots)) {
    $d = Join-Path $r.Path $sid
    if (Test-Path $d) { return [pscustomobject]@{ Root=$r; Dir=$d } }
  }
  return $null
}

function Zfs-DatasetForMountpoint([string]$mp) {
  # zfs list -H -o name <mountpoint>
  try {
    $out = & zfs.exe list -H -o name $mp 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { return ($out | Select-Object -First 1).Trim() }
  } catch {}
  return $null
}

function Try-ZfsDestroy([string]$ds) {
  if (-not $ds) { return }
  Write-Host "zfs destroy -r $ds"
  & zfs.exe unmount -f $ds 2>$null | Out-Null
  & zfs.exe destroy -r $ds
}

if (-not $Name) { $Name = Ask "Name (name.shortid)" }
$Name = NormalizeName $Name
if (-not $Name) { throw "empty name" }

$hit = Find-ScalefsDir $Name
if (-not $hit) { throw "not found: $Name" }

$dir = $hit.Dir
$main = Join-Path $dir "main"

$ds = $null
if (Get-Command zfs.exe -ErrorAction SilentlyContinue) {
  $ds = Zfs-DatasetForMountpoint $main
}

Write-Host "Target:"
Write-Host ("  root={0} path={1}" -f $hit.Root.Alias, $hit.Root.Path)
Write-Host ("  dir ={0}" -f $dir)
if ($ds) { Write-Host ("  zfs ={0}" -f $ds) }

if (-not $Yes) {
  $ans = Ask "Proceed? (y/N)" "N"
  if ($ans.ToLower() -ne "y" -and $ans.ToLower() -ne "yes") { Write-Host "cancelled"; exit 0 }
}

if ($ds) { Try-ZfsDestroy $ds }

# Remove directory after ZFS destroy
Remove-Item $dir -Recurse -Force
Write-Host "OK removed: $Name"