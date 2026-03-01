# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0. "$PSScriptRoot\lib.ps1"

param(
    [switch]$i
)

$node = Ask "Node ID" $env:COMPUTERNAME.ToLower()
$site = Ask "Site" "default"

$configDir="$HOME\.zmesh"
EnsureDir $configDir
EnsureDir "$configDir\virtualpath.d"

$config="$configDir\zmesh.conf"

@"
[node]
id=$node
site=$site

[paths]
state_dir=./scalefs.state
watch_root=./main

[scalefs]
roots=$HOME\scalefs
"@ | Set-Content $config

EnsureDir "$configDir\zmesh.d"

Write-Host "OK initialized: $config"