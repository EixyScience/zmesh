param(
    [string]$Config="$HOME\.zmesh\zmesh.conf"
)

Start-Process zmesh -ArgumentList "agent -c `"$Config`""
Write-Host "zmesh started"