Write-Host "zmesh doctor"

if (!(Get-Command zmesh -ErrorAction SilentlyContinue))
{
    Write-Host "zmesh not found"
}

Write-Host "roots:"
Get-ChildItem "$HOME\.zmesh\zmesh.d"