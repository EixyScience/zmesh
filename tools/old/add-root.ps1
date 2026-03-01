param(
    [string]$Path="",
    [string]$Alias="",
    [switch]$Interactive
)

function Ask($prompt, $default)
{
    $v = Read-Host "$prompt [$default]"
    if ($v -eq "") { return $default }
    return $v
}

if ($Path -eq "")
{
    $Path = Ask "Scalefs root path" "$HOME\scalefs"
}

if ($Alias -eq "")
{
    $Alias = Ask "Alias" "default"
}

New-Item -ItemType Directory -Force $Path | Out-Null

$confdir="$HOME\.zmesh\zmesh.d"
New-Item -ItemType Directory -Force $confdir | Out-Null

$file="$confdir\root.$Alias.conf"

@"
alias=$Alias
path=$Path
"@ | Set-Content $file

Write-Host "root added: $Alias → $Path"