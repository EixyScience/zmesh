param(
    [string]$ConfigPath = "",
    [string]$NodeID = "",
    [string]$Site = "",
    [string]$Root = "",
    [switch]$Interactive
)

function Ask($prompt, $default)
{
    if ($Interactive -or $default -eq "")
    {
        $v = Read-Host "$prompt [$default]"
        if ($v -eq "") { return $default }
        return $v
    }
    return $default
}

# defaults
if ($NodeID -eq "")
{
    $NodeID = $env:COMPUTERNAME.ToLower()
}

if ($Site -eq "")
{
    $Site = "default"
}

$NodeID = Ask "Node ID" $NodeID
$Site   = Ask "Site" $Site

if ($ConfigPath -eq "")
{
    $ConfigPath = Ask "Config path" "$HOME\.zmesh\zmesh.conf"
}

$dir = Split-Path $ConfigPath
New-Item -ItemType Directory -Force $dir | Out-Null

$config = @"
[node]
id=$NodeID
site=$Site

[scalefs]
roots=$HOME\scalefs

[paths]
state_dir=./scalefs.state
watch_root=./main
watch_exclude=scalefs.state/**
"@

$config | Set-Content $ConfigPath -Encoding UTF8

Write-Host "zmesh initialized: $ConfigPath"