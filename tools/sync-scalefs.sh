#!/bin/sh
set -eu

rsync -av "$1/" "$2/"