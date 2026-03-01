# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

<#
Apply virtual path rules into a vroot.
- Builds a manifest: <vroot>\.zmesh\virtualpath.manifest
- Optional clean: remove stale links under vroot that are not in manifest

Config layout (recommended):
  $env:ZCONF_DIR\virtualpath.d\*.conf
Default ZCONF_DIR:
  $HOME\.zmesh   (Windows-friendly default)

Rule format (INI-ish):
  [vpath "hobby\car"]  or [vpath "hobby/car"]
  target=C:\path\to\scalefs\main
#>

param(
  [Parameter(Mandatory=$true)]
  [Alias("r")]
  [string]$Root,

  [switch]$Clean,
  [switch]$Yes,
  [switch]$Strict,
  [switch]$DryRun
)

function Say($s) { Write-Host $s }
function Die($s) { throw $s }

$ZCONF_DIR = $env:ZCONF_DIR
if ([string]::IsNullOrWhiteSpace($ZCONF_DIR)) {
  $ZCONF_DIR = Join-Path $HOME ".zmesh"
}

$confDir = Join-Path $ZCONF_DIR "virtualpath.d"
if (-not (Test-Path $confDir)) {
  Die "missing config dir: $confDir (set ZCONF_DIR or create virtualpath.d\)"
}

# Normalize Root
$Root = (Resolve-Path -LiteralPath $Root -ErrorAction SilentlyContinue)?.Path ?? $Root
if (-not $Root) { Die "Root is empty" }

$manifestDir = Join-Path $Root ".zmesh"
$manifestPath = Join-Path $manifestDir "virtualpath.manifest"

if (-not $DryRun) {
  New-Item -ItemType Directory -Force -Path $Root | Out-Null
  New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
}

# Parse rules: last-wins by vpath
# Supports multiple blocks per file.
$rules = @{}  # vpath -> target

Get-ChildItem -LiteralPath $confDir -Filter "*.conf" -File | ForEach-Object {
  $curV = $null
  $curT = $null

  Get-Content -LiteralPath $_.FullName | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#") -or $line.StartsWith(";")) { return }

    $m = [regex]::Match($line, '^\[vpath\s+"([^"]+)"\]\s*$')
    if ($m.Success) {
      if ($curV -and $curT) { $rules[$curV] = $curT }
      $curV = $m.Groups[1].Value
      $curT = $null
      return
    }

    $m2 = [regex]::Match($line, '^target\s*=\s*(.*)$')
    if ($m2.Success -and $curV) {
      $curT = $m2.Groups[1].Value.Trim()
      return
    }
  }

  if ($curV -and $curT) { $rules[$curV] = $curT }
}

Say "[apply] root=$Root conf=$confDir clean=$Clean strict=$Strict dryrun=$DryRun"

# Apply rules + build manifest lines
$manifestLines = New-Object System.Collections.Generic.List[string]
$manifestSet   = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)

foreach ($kv in $rules.GetEnumerator()) {
  $rel = $kv.Key
  $target = $kv.Value

  if ([string]::IsNullOrWhiteSpace($rel) -or [string]::IsNullOrWhiteSpace($target)) { continue }

  # normalize rel: strip leading slashes, convert / to \, collapse \\ lightly
  $rel = $rel.TrimStart('\','/')
  $rel = $rel -replace '/', '\'
  while ($rel.Contains("\\\")) { $rel = $rel -replace "\\\\+", "\" }

  $linkPath = Join-Path $Root $rel
  $parent = Split-Path -Parent $linkPath

  if ($Strict -and -not (Test-Path -LiteralPath $target)) {
    Die "target missing (strict): $target for vpath=$rel"
  }

  if ($DryRun) {
    Say "DRYRUN mkdir -Force $parent"
    Say "DRYRUN New-Item -ItemType SymbolicLink -Path $linkPath -Target $target -Force"
  } else {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    # If existing and is directory => fail (avoid clobber)
    if (Test-Path -LiteralPath $linkPath) {
      $it = Get-Item -LiteralPath $linkPath -Force
      if ($it.PSIsContainer -and -not $it.LinkType) {
        Die "link path exists and is a directory: $linkPath"
      }
      Remove-Item -LiteralPath $linkPath -Force -Recurse -ErrorAction SilentlyContinue
    }

    New-Item -ItemType SymbolicLink -Path $linkPath -Target $target -Force | Out-Null
  }

  $manifestSet.Add($rel) | Out-Null
  $manifestLines.Add("$rel|$target")
}

# Write manifest (atomic)
if ($DryRun) {
  Say "DRYRUN write manifest: $manifestPath"
} else {
  $tmp = "$manifestPath.tmp"
  $header = @(
    "# zmesh virtualpath manifest"
    "# generated_unix=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    "# format: vpath|target"
  )
  ($header + $manifestLines) | Set-Content -LiteralPath $tmp -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $manifestPath -Force
}

# Clean stale links
if ($Clean) {
  if (-not $Yes) {
    $ans = Read-Host "Clean is enabled. Remove stale links under '$Root'? [y/N]"
    if ($ans -notin @("y","Y","yes","YES")) { Die "aborted by user" }
  }

  # Find all symlinks under root excluding .zmesh
  $live = Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.LinkType } |
          ForEach-Object {
            $p = $_.FullName.Substring($Root.Length).TrimStart('\')
            if ($p -and -not $p.StartsWith(".zmesh\")) { $p }
          } | Sort-Object -Unique

  $stale = @()
  foreach ($p in $live) {
    if (-not $manifestSet.Contains($p)) { $stale += $p }
  }

  if ($stale.Count -gt 0) {
    Say "[clean] removing stale links:"
    foreach ($rel in $stale) {
      $p = Join-Path $Root $rel
      if ($DryRun) {
        Say "DRYRUN Remove-Item -LiteralPath $p -Force"
      } else {
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
      }
    }
  } else {
    Say "[clean] no stale links"
  }

  # Prune empty directories (excluding .zmesh) best-effort
  if ($DryRun) {
    Say "DRYRUN prune empty dirs under '$Root' (excluding .zmesh)"
  } else {
    # depth-first
    $dirs = Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $manifestDir } |
            Sort-Object FullName -Descending

    foreach ($d in $dirs) {
      try {
        $kids = Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue
        if (-not $kids -or $kids.Count -eq 0) {
          Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue
        }
      } catch { }
    }
  }
}

Say "[ok] manifest=$manifestPath"
exit 0