# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0. "$PSScriptRoot\lib.ps1"

$path = Ask "Path"

EnsureDir "$path\main"
EnsureDir "$path\scalefs.state"