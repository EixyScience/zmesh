. "$PSScriptRoot\lib.ps1"

$path = Ask "Scalefs path"

Remove-Item $path -Recurse -Force