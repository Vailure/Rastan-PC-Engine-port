#!/bin/sh
# Build the headless PCE runner from the vendored tgemu (GPLv2, tools/tgemu/src,
# from HuC; patched for 2.5MB ROMs and the Street Fighter II mapper).
cd "$(dirname "$0")"
T=../tgemu/src
gcc -O2 -w -fno-strict-aliasing -D_GNU_SOURCE -DLSB_FIRST -DFAST_MEM -I$T -I$T/cpu -I$T/unix \
  -o tgrun tgrun.c $T/fileio.c $T/pce.c $T/psg.c $T/render.c $T/system.c $T/vce.c $T/vdc.c $T/cpu/h6280.c -lz -lm
