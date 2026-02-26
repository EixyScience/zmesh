param(
    [Parameter(Position=0, Mandatory=$false)]
    [string[]]$Dirs,

    [Parameter(Position=1, Mandatory=$false)]
    [string[]]$Files
)

$ErrorActionPreference = "Stop"

function Ensure-Dir {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        Write-Host "MKDIR $Path"
    }
}

function Ensure-File {
    param([string]$Path)

    $parent = Split-Path -Parent $Path

    if ($parent -and -not (Test-Path $parent)) {
        Ensure-Dir $parent
    }

    if (-not (Test-Path $Path)) {
        # UTF8 without BOM empty file
        [System.IO.File]::WriteAllBytes($Path, [byte[]]@())
        Write-Host "TOUCH $Path"
    }
}

# ZMESH:SCAFFOLD: create directories first
foreach ($d in $Dirs) {
    Ensure-Dir $d
}

# ZMESH:SCAFFOLD: create files
foreach ($f in $Files) {
    Ensure-File $f
}

Write-Host "Done."