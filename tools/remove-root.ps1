# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0. "$PSScriptRoot\lib.ps1"

$alias = Ask "Alias"

Remove-Item "$HOME\.zmesh\zmesh.d\root.$alias.conf"