. "$PSScriptRoot\lib.ps1"

$root = Ask "Root path" "$HOME\scalefs"
$name = Ask "Name" "data"

$id = ShortID

$dir="$root\$name.$id"

EnsureDir "$dir\main"
EnsureDir "$dir\scalefs.state"
EnsureDir "$dir\scalefs.global.d"
EnsureDir "$dir\scalefs.local.d"
EnsureDir "$dir\scalefs.runtime.d"

@"
[scalefs]
id=$id
name=$name
"@ | Set-Content "$dir\scalefs.ini"

Write-Host "OK scalefs created: $dir"