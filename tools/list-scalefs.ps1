# tools/list-scalefs.ps1
# List scalefs bodies under registered roots (root.*.conf: alias=, path=)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib.ps1"

param(
  [string]$Root,    # alias filter (optional)
  [string]$Id,      # substring filter (optional)
  [switch]$Full,    # show full paths
  [switch]$Help
)

function Show-Help {
@"
list - list scalefs bodies under registered roots

USAGE
  scalefs list [options]

COMMAND + OPTIONS
  scalefs list -Root, -r ALIAS
      Filter by root alias

  scalefs list -Id,   -i SUBSTR
      Filter by id substring (e.g., democell.)

  scalefs list -Full
      Show full body path

EXAMPLES
  scalefs list
  scalefs list -r default
  scalefs list -i democell. -Full
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }

function Load-Roots {
  $confDir = ZmeshConfDir
  $d = Join-Path $confDir "zmesh.d"
  if (-not (Test-Path $d)) { return @() }

  $roots = @()
  Get-ChildItem $d -Filter "root.*.conf" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $txt = Get-Content $_.FullName -ErrorAction SilentlyContinue
    $alias = (($txt | Where-Object { $_ -match '^\s*alias\s*=' } | Select-Object -First 1) -replace '^\s*alias\s*=\s*','').Trim()
    $path  = (($txt | Where-Object { $_ -match '^\s*path\s*=' }  | Select-Object -First 1) -replace '^\s*path\s*=\s*','').Trim()
    if ($path) {
      $roots += [pscustomobject]@{ Alias=$alias; Path=$path }
    }
  }
  return $roots
}

$roots = Load-Roots
if ($Root) { $roots = $roots | Where-Object { $_.Alias -eq $Root } }

if (-not $roots -or $roots.Count -eq 0) {
  Write-Host "No roots found. Add one by: zmesh root add"
  exit 0
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($r in $roots) {
  if (-not (Test-Path $r.Path)) { continue }
  Get-ChildItem -LiteralPath $r.Path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $dir = $_.FullName
    $ini = Join-Path $dir "scalefs.ini"
    if (Test-Path $ini) {
      $idName = $_.Name
      if ($Id -and ($idName -notlike "*$Id*")) { return }
      $results.Add([pscustomobject]@{
        RootAlias = $r.Alias
        Id        = $idName
        Path      = $dir
      })
    }
  }
}

if ($results.Count -eq 0) { exit 0 }

if ($Full) {
  $results | Sort-Object RootAlias,Id | Format-Table RootAlias,Id,Path -AutoSize
} else {
  $results | Sort-Object RootAlias,Id | Format-Table RootAlias,Id -AutoSize
}