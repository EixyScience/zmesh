function Ask($prompt, $default="")
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




