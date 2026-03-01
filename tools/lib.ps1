# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0function Ask($prompt, $default="")
{
    $msg = $prompt
    if ($default -ne "") { $msg += " [$default]" }

    $v = Read-Host $msg
    if ($v -eq "") { return $default }
    return $v
}

function EnsureDir($path)
{
    if (!(Test-Path $path))
    {
        New-Item -ItemType Directory -Force $path | Out-Null
    }
}

function ShortID()
{
    return ([guid]::NewGuid().ToString("N")).Substring(0,8)
}



function Normalize-Name([string]$s) {
    if ($null -eq $s) { return "" }
    $x = $s.ToLower()
    # allow a-z 0-9 . _ -
    $x = ($x -replace '[^a-z0-9\.\_\-]', '')
    $x = ($x -replace '^[^a-z0-9]+', '')
    return $x
}

function Get-ZmeshConfDir() {
    if ($env:ZCONF_DIR -and $env:ZCONF_DIR.Trim() -ne "") { return $env:ZCONF_DIR }
    return (Join-Path $HOME ".zmesh")
}

function Load-Roots() {
    $dir = Get-ZmeshConfDir
    $d = Join-Path $dir "zmesh.d"
    if (!(Test-Path $d)) { return @() }

    $roots = @()
    Get-ChildItem -Path $d -Filter "root.*.conf" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $alias = ""
        $path  = ""
        Get-Content $_.FullName | ForEach-Object {
            $line = $_.Trim()
            if ($line -match '^\s*alias\s*=\s*(.+)\s*$') { $alias = $Matches[1].Trim(); return }
            if ($line -match '^\s*path\s*=\s*(.+)\s*$')  { $path  = $Matches[1].Trim(); return }
        }
        if ($alias -ne "" -and $path -ne "") {
            $roots += [pscustomobject]@{ Alias=$alias; Path=$path; File=$_.FullName }
        }
    }
    return $roots
}

function Normalize-Name([string]$s) {
    $s = $s.ToLowerInvariant()
    # keep a-z0-9 . _ -
    $s = ($s -replace '[^a-z0-9\.\_\-]', '')
    $s = ($s -replace '^[^a-z0-9]+', '')
    return $s
}


function ZmeshConfDir() {
    $d = Join-Path $HOME ".zmesh"
    EnsureDir $d
    return $d
}

function VirtualPathDir() {
    $d = Join-Path (ZmeshConfDir) "virtualpath.d"
    EnsureDir $d
    return $d
}

function NormalizeVPath([string]$vp) {
    $vp = $vp.Trim()
    $vp = $vp -replace '^[\\/]+',''
    $vp = $vp -replace '[\\/]+','/'
    $vp = $vp.TrimEnd('/')
    return $vp.ToLower()
}

function VpFileName([string]$vp) {
    # hobby/car -> hobby__car
    $safe = ($vp -replace '/', '__')
    $safe = ($safe -replace '[^a-z0-9._-]','')
    return $safe
}

# ----------------------------
# Roots / Paths helpers
# ----------------------------

function Get-ZmeshConfDir {
    # 1) env: ZCONF_DIR (tests or overrides)
    if ($env:ZCONF_DIR -and $env:ZCONF_DIR.Trim() -ne "") {
        return $env:ZCONF_DIR.Trim()
    }
    # 2) default (Windows)
    return (Join-Path $HOME ".zmesh")
}

function Get-RootConfDir {
    $z = Get-ZmeshConfDir
    return (Join-Path $z "zmesh.d")
}

function Get-Roots {
    # root.*.conf の形式に対応:
    #   alias=default
    #   path=C:\scalefsroot
    $dir = Get-RootConfDir
    if (-not (Test-Path $dir)) { return @() }

    $roots = @()
    Get-ChildItem -Path $dir -Filter "root.*.conf" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $alias = $null
        $path  = $null
        Get-Content $_.FullName | ForEach-Object {
            $line = $_.Trim()
            if ($line -match '^\s*alias\s*=\s*(.+)\s*$') { $alias = $Matches[1].Trim() }
            elseif ($line -match '^\s*path\s*=\s*(.+)\s*$') { $path = $Matches[1].Trim() }
        }
        if ($alias -and $path) {
            $roots += [pscustomobject]@{
                Alias = $alias
                Path  = $path
                File  = $_.FullName
            }
        }
    }
    return $roots
}

function Resolve-RootPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RootSpec
    )

    $r = $RootSpec.Trim()
    if ($r -eq "") { throw "root spec is empty" }

    # 1) existing directory => treat as path
    if (Test-Path $r -PathType Container) {
        return (Resolve-Path $r).Path
    }

    # 2) alias => lookup
    $roots = Get-Roots
    $hit = $roots | Where-Object { $_.Alias -eq $r } | Select-Object -First 1
    if (-not $hit) { throw "unknown root alias or path: $RootSpec" }

    # path may be relative (rare), normalize
    if (Test-Path $hit.Path -PathType Container) {
        return (Resolve-Path $hit.Path).Path
    }
    return $hit.Path
}

function Resolve-ScalefsBodyPath {
    param(
        [string]$Id,
        [string]$RootSpec,
        [string]$Path
    )
    if ($Path -and $Path.Trim() -ne "") {
        return (Resolve-Path $Path).Path
    }
    if (-not $Id -or $Id.Trim() -eq "") {
        throw "id is required (e.g. democell.17ded8)"
    }

    if ($RootSpec -and $RootSpec.Trim() -ne "") {
        $rootPath = Resolve-RootPath $RootSpec
        return (Join-Path $rootPath $Id)
    }

    # RootSpec省略時: 全rootsから一意に見つかるならそれを使う
    $roots = Get-Roots
    $hits = @()
    foreach ($rt in $roots) {
        $p = Join-Path $rt.Path $Id
        if (Test-Path $p -PathType Container) { $hits += $p }
    }
    if ($hits.Count -eq 1) { return $hits[0] }
    if ($hits.Count -eq 0) { throw "not found in any root: $Id (use -r or -p)" }
    throw "ambiguous id across roots: $Id (use -r or -p)"
}




