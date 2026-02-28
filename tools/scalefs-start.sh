#!/bin/sh
set -eu

CONF="${1:-/usr/local/etc/zmesh/zmesh.conf}"

zmesh agent -c "$CONF"