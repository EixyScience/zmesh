param(
    [string]$Root="$HOME\scalefs"
)

Get-ChildItem $Root -Directory | ForEach-Object {

    if (Test-Path "$($_.FullName)\scalefs.ini")
    {
        Write-Host $_.FullName
    }
}