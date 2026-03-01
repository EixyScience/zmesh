# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0param(
    [string]$Dataset,
    [string]$Mount
)

zfs set mountpoint=$Mount $Dataset
zfs mount $Dataset