param(
  [Parameter(Mandatory=$true)][string]$ScalefsRoot,
  [Parameter(Mandatory=$true)][string]$Name,

  [string]$ZfsBase = "",         # Windowsでは基本空 (ZFS for Windowsが入っていれば将来)
  [string]$Mountpoint = "",

  [int]$ShortIdLen = 6,
  [switch]$NoShortId,
  [switch]$NoZfs,

  [ValidateSet("error","reuse","suffix")][string]$Exists = "error",
  [switch]$DryRun,
  [switch]$Json
)

function Normalize-Name([string]$s) {
  $s = $s.ToLowerInvariant()
  $s = $s -replace '[\\/]+','.'
  $s = $s -replace '\s+','-'
  $s = $s -replace '[^a-z0-9._-]+','-'
  $s = $s -replace '[._-]{2,}','-'
  $s = $s -replace '^[._-]+',''
  $s = $s -replace '[._-]+$',''
  if ([string]::IsNullOrWhiteSpace($s)) { $s = "scalefs" }
  return $s
}

function New-ShortId([int]$n) {
  $alphabet = "23456789abcdefghjkmnpqrstuvwxyz"
  $bytes = New-Object byte[] 64
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $chars = New-Object System.Collections.Generic.List[char]
  foreach ($b in $bytes) {
    $chars.Add($alphabet[ $b % $alphabet.Length ])
    if ($chars.Count -ge $n) { break }
  }
  return -join $chars
}

function Run([scriptblock]$sb) {
  if ($DryRun) { Write-Host "[dry-run] $sb"; return }
  & $sb
}

$norm = Normalize-Name $Name
$sid = ""
$final = $norm
if (-not $NoShortId) {
  $sid = New-ShortId $ShortIdLen
  $final = "$norm.$sid"
}

$scalefsPath = Join-Path $ScalefsRoot $final
$mainPath = Join-Path $scalefsPath "main"
$statePath = Join-Path $scalefsPath "scalefs.state"
if ($Mountpoint) { $mainPath = $Mountpoint }

$action = "created"
$provider = "generic"
$dataset = ""

if (Test-Path $scalefsPath) {
  switch ($Exists) {
    "reuse" { $action = "reused" }
    "error" {
      if ($Json) {
        @{ ok=$false; message="already exists"; scalefs_path=$scalefsPath } | ConvertTo-Json -Compress
        exit 0
      }
      throw "already exists: $scalefsPath"
    }
    "suffix" {
      $ok = $false
      for ($i=0; $i -lt 20; $i++) {
        $sid = New-ShortId $ShortIdLen
        $final = "$norm.$sid"
        $scalefsPath = Join-Path $ScalefsRoot $final
        $mainPath = Join-Path $scalefsPath "main"
        $statePath = Join-Path $scalefsPath "scalefs.state"
        if ($Mountpoint) { $mainPath = $Mountpoint }
        if (-not (Test-Path $scalefsPath)) { $ok = $true; break }
      }
      if (-not $ok) { throw "could not find non-colliding name" }
    }
  }
}

Run { New-Item -ItemType Directory -Force -Path $scalefsPath | Out-Null }
Run { New-Item -ItemType Directory -Force -Path (Join-Path $scalefsPath "scalefs.global.d") | Out-Null }
Run { New-Item -ItemType Directory -Force -Path (Join-Path $scalefsPath "scalefs.local.d")  | Out-Null }
Run { New-Item -ItemType Directory -Force -Path (Join-Path $scalefsPath "scalefs.runtime.d")| Out-Null }
Run { New-Item -ItemType Directory -Force -Path $statePath | Out-Null }

$iniPath = Join-Path $scalefsPath "scalefs.ini"
if (-not (Test-Path $iniPath)) {
  $ini = @"
[paths]
state_dir = ./scalefs.state
watch_root = ./main
watch_exclude = ./scalefs.state/**, ./scalefs.runtime.d/**

[include]
global = ./scalefs.global.d/*.ini
local  = ./scalefs.local.d/*.ini
runtime = ./scalefs.runtime.d/*.ini
"@
  if ($DryRun) { Write-Host "[dry-run] write $iniPath" }
  else { $ini | Set-Content -Encoding UTF8 -NoNewline $iniPath }
}

# Windowsは基本 ZFS無し。将来 ZFS for Windows が導入されたらここを拡張。
if (-not $NoZfs -and $ZfsBase) {
  $provider = "zfs"
  $dataset = "$ZfsBase/$final"
  # TODO: zfs.exe が提供される前提なら作る
  # Run { & zfs create -o mountpoint="$mainPath" $dataset }
} else {
  Run { New-Item -ItemType Directory -Force -Path $mainPath | Out-Null }
}

$out = [ordered]@{
  ok=$true; message="ok"; action=$action
  input_name=$Name; normalized=$norm; shortid=$sid; final=$final
  scalefs_path=$scalefsPath; main_path=$mainPath; state_path=$statePath
  provider=$provider; dataset=$dataset
}
if ($Json) { $out | ConvertTo-Json -Compress } else { $out }