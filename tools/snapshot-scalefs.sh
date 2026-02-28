#!/bin/sh
set -eu

if detect_zfs; then

zfs snapshot "$1@$(date +%s)"

else

tar czf "$1.snapshot.$(date +%s).tgz" "$1"

fi