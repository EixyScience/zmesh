# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0Write-Host "zmesh doctor"

if (!(Get-Command zmesh -ErrorAction SilentlyContinue))
{
    Write-Host "zmesh not found"
}

Write-Host "roots:"
Get-ChildItem "$HOME\.zmesh\zmesh.d"