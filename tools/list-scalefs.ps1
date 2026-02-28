$root="$HOME\scalefs"

Get-ChildItem $root -Directory |
Where { Test-Path "$($_.FullName)\scalefs.ini" }