. "$PSScriptRoot\lib.ps1"

$alias = Ask "Alias"

Remove-Item "$HOME\.zmesh\zmesh.d\root.$alias.conf"