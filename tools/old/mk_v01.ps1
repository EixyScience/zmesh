param(
    [Parameter(Position=0, Mandatory=$false)]
    [string[]]$Dirs,

    [Parameter(Position=1, Mandatory=$false)]
    [string[]]$Files,

    # Optional: override base directory (repo root)
    [Parameter(Mandatory=$false)]
    [string]$BaseDir
)

$ErrorActionPreference = "Stop"

# ZMESH:SCAFFOLD: resolve repo root from script location by default
if ([string]::IsNullOrWhiteSpace($BaseDir)) {
    # tools\mk.ps1 -> repo root is parent of tools
    $BaseDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $BaseDir = (Resolve-Path $BaseDir).Path
}

function To-AbsPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return (Join-Path $BaseDir $Path)
}

function Ensure-Dir {
    param([string]$Path)

    $abs = To-AbsPath $Path
    if (-not (Test-Path $abs)) {
        New-Item -ItemType Directory -Force -Path $abs | Out-Null
        Write-Host "MKDIR $Path"
    }
}

function Ensure-File {
    param([string]$Path)

    $abs = To-AbsPath $Path
    $parent = Split-Path -Parent $abs

    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        Write-Host ("MKDIR {0}" -f ($parent.Substring($BaseDir.Length).TrimStart('\','/')))
    }

    if (-not (Test-Path $abs)) {
        # empty file, no BOM
        [System.IO.File]::WriteAllBytes($abs, [byte[]]@())
        Write-Host "TOUCH $Path"
    }
}

foreach ($d in $Dirs) { Ensure-Dir $d }
foreach ($f in $Files) { Ensure-File $f }

Write-Host "Done. (base=$BaseDir)"