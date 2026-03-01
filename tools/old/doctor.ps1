param()

Write-Host "zmesh doctor"

if (!(Get-Command zmesh -ErrorAction SilentlyContinue))
{
    Write-Host "zmesh not in PATH"
}

Write-Host "roots:"
Get-ChildItem "$HOME\.zmesh\zmesh.d" -ErrorAction SilentlyContinue