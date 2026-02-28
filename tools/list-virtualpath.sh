#!/bin/sh
set -eu
. ./common.sh

load_virtualpaths | awk -F'|' '
BEGIN{
  printf("%-24s  %-20s  %s\n","VPATH","SCALEFS","SUBPATH");
  printf("%-24s  %-20s  %s\n","------------------------","--------------------","-------");
}
{ printf("%-24s  %-20s  %s\n",$1,$2,$3); }'