# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0. "$PSScriptRoot\lib.ps1"

$path = Ask "Root path" "$HOME\scalefs"
$alias = Ask "Alias" "default"

EnsureDir $path

$file="$HOME\.zmesh\zmesh.d\root.$alias.conf"

@"
alias=$alias
path=$path
"@ | Set-Content $file

Write-Host "OK root added"