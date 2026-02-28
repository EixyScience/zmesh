. "$PSScriptRoot\lib.ps1"

$path = Ask "Path"

EnsureDir "$path\main"
EnsureDir "$path\scalefs.state"