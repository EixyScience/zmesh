. "$PSScriptRoot\lib.ps1"

$path = Ask "Root path" "$HOME\scalefs"
$alias = Ask "Alias" "default"

EnsureDir $path

$file="$HOME\.zmesh\zmesh.d\root.$alias.conf"

@"
alias=$alias
path=$path
"@ | Set-Content $file

Write-Host "OK root added"