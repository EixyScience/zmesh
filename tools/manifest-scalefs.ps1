#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [string]$Path = "",
  [string]$Id   = "",
  [string]$Out  = "",
  [switch]$Stdout,
  [ValidateSet("auto","none","sha1","sha256")]
  [string]$Hash = "auto",
  [switch]$NoHash,
  [switch]$Help
)

function Show-Help {
@"
manifest - emit a manifest of main/ (file list + metadata)

USAGE
  scalefs manifest [options]

COMMAND + OPTIONS
  scalefs manifest -Path,  -p DIR
      Explicit scalefs body directory (contains scalefs.ini and main/)

  scalefs manifest -Id,    -i ID
      Resolve scalefs body directory by ID (name.shortid) via registered roots

  scalefs manifest -Out,   -o FILE
      Write to FILE (default: DIR\scalefs.manifest)

  scalefs manifest -Stdout
      Write to stdout

  scalefs manifest -Hash auto|none|sha1|sha256
      Hash algorithm (default: auto)

  scalefs manifest -NoHash
      Same as -Hash none

  scalefs manifest -Help
      Show this help

EXAMPLES
  scalefs manifest -Path C:\scalefsroot\democell.17ded8
  scalefs manifest -Id democell.17ded8 -Stdout
  scalefs manifest -Id democell.17ded8 -Out .\out.manifest -Hash sha1
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }
if ($NoHash) { $Hash = "none" }

function Read-RootConfigs {
  $confDir = Join-Path $HOME ".zmesh\zmesh.d"
  if (-not (Test-Path $confDir)) { return @() }

  $files = Get-ChildItem -Path $confDir -Filter "root.*.conf" -File -ErrorAction SilentlyContinue
  $roots = @()

  foreach ($f in $files) {
    $txt = Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue
    # supports:
    #   alias=default
    #   path=C:\scalefsroot
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
$main = Join-Path $dir "main"
if (-not (Test-Path $ini))  { throw "not a scalefs body (missing scalefs.ini): $dir" }
if (-not (Test-Path $main)) { throw "missing main/: $main" }

# Determine hash algorithm
$algo = $Hash
if ($algo -eq "auto") { $algo = "sha256" }
if ($algo -eq "sha256" -and -not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) { $algo = "none" }
if ($algo -eq "sha1"   -and -not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) { $algo = "none" }

function Hash-Of([string]$file) {
  if ($algo -eq "none") { return "-" }
  try {
    $h = Get-FileHash -LiteralPath $file -Algorithm $algo.ToUpperInvariant()
    return $h.Hash.ToLowerInvariant()
  } catch {
    return "-"
  }
}

# Output file selection
$outFile = $Out
if ($Stdout) {
  $outFile = ""
} elseif (-not $outFile) {
  $outFile = Join-Path $dir "scalefs.manifest"
}

# Collect
$generated = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# scalefs manifest")
$lines.Add("# body_dir=$dir")
$lines.Add("# main_dir=$main")
$lines.Add("# hash=$algo")
$lines.Add("# generated_unix=$generated")
$lines.Add("# format: path<TAB>size<TAB>mtime_unix<TAB>hash")

$files = Get-ChildItem -Path $main -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName
foreach ($f in $files) {
  $rel = $f.FullName.Substring($main.Length).TrimStart('\','/')
  $size = $f.Length
  $mtime = [DateTimeOffset]$f.LastWriteTimeUtc
  $mt = $mtime.ToUnixTimeSeconds()
  $hs = Hash-Of $f.FullName
  $lines.Add(("{0}`t{1}`t{2}`t{3}" -f $rel, $size, $mt, $hs))
}

if ($Stdout) {
  $lines | ForEach-Object { $_ }
} else {
  $lines | Set-Content -LiteralPath $outFile -Encoding UTF8
  Write-Host "OK: wrote $outFile"
}