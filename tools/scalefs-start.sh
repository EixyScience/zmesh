#!/bin/sh
# Copyright 2026 Satoshi Takashima
# Copyright 2026 EixyScience, Inc.
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0set -eu

CONF="${1:-/usr/local/etc/zmesh/zmesh.conf}"

zmesh agent -c "$CONF"