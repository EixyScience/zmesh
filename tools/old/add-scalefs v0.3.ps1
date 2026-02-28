param(
    [string]$Root="",
    [string]$Name="",
    [switch]$Interactive
)

function Ask($prompt, $default)
{
    $v = Read-Host "$prompt [$default]"
    if ($v -eq "") { return $default }
    return $v
}

if ($Root -eq "")
{
    $Root = Ask "Root path" "$HOME\scalefs"
}

if ($Name -eq "")
{
    $Name = Ask "Scalefs name" "data"
}

$shortid = [guid]::NewGuid().ToString().Substring(0,8)

$path="$Root\$Name.$shortid"

New-Item -ItemType Directory -Force "$path\main" | Out-Null
New-Item -ItemType Directory -Force "$path\scalefs.state" | Out-Null
New-Item -ItemType Directory -Force "$path\scalefs.global.d" | Out-Null
New-Item -ItemType Directory -Force "$path\scalefs.local.d" | Out-Null
New-Item -ItemType Directory -Force "$path\scalefs.runtime.d" | Out-Null

@"
[scalefs]
id=$shortid
name=$Name
"@ | Set-Content "$path\scalefs.ini"

Write-Host "scalefs created: $path"