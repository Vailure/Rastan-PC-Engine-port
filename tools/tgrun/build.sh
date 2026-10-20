#!/bin/sh
# Build the headless PCE runner against HuC's tgemu objects (run `make` in huc first).
T=/home/claude/tools/huc/tgemu
cd "$(dirname "$0")"
gcc -O2 -w -fno-strict-aliasing -D_GNU_SOURCE -DLSB_FIRST -DFAST_MEM -I$T/src -I$T/src/cpu -I$T/src/unix \
  -o tgrun tgrun.c $T/src/fileio.o $T/src/pce.o $T/src/psg.o $T/src/render.o $T/src/system.o \
  $T/src/vce.o $T/src/vdc.o $T/src/cpu/h6280.o -lz
