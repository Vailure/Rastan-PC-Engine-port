"""extract_roms.py <rastan rom dir> <outdir>: build interleaved region images used by sim/."""
import sys
from arcade_gfx import load_region
romdir, out = sys.argv[1], sys.argv[2]
for name in ("maincpu", "pc080sn", "pc090oj"):
    open(f"{out}/{name}.bin", "wb").write(load_region(romdir, name))
    print("wrote", f"{out}/{name}.bin")
