"""Build the castle's floor spears (sprite cells resident in VRAM) for the PC Engine.

usage: pce_traps.py spikes.snp outdir

The arcade draws the spears of its first castle room with sprites that belong to no
object slot (sim/scripts/spikes.txt, frame 1480): a slot cover ($234) on the floor and,
per spear, a head ($266) over a shaft ($267, repeated). Two spears 16 px apart make a
trap; markers $46 at x 8328 and 8488 place two traps.

The same room's hanging column (marker $47, hall.txt) is drawn the same way: a 32x32
block ($236-$239) hanging from the ceiling and a piston, shaft ($23A, repeated) and
foot ($23B), in the spears' palette.

Shaft 2's three spiked weights (marker $45, sim/scripts/weights.txt) are drawn the same
way too: a ceiling plate ($23F, in the arcade's palette 3: Rastan's), chain links ($23C,
repeated), a frame ($23D) and a 32 px spiked bar ($23E twice), in the spears' palette.

Outputs:
  traps.bin    3 cells (cover, head, shaft), 128 bytes each (PCE sprite format)
  trappal.bin  two sprite palettes (the cover's, the spear's)
  column.bin   6 cells: the block (4, in 32x32 sprite order), shaft, foot
  weights.bin  5 cells: chain, frame, bar, bar (a 32 x 16 sprite), plate; the plate's
               colours mapped to their indices in Rastan's palette (PCE sprite palette 0)
"""
import os
import sys
import numpy as np
from arcade_gfx import load_region, decode_packed
from snap import read_snaps, palette_rgb

ROMDIR = os.environ.get('RASTAN_ROMS', os.path.join(os.path.dirname(__file__), '..', 'roms', 'rastan'))
FRAME = 1480
CELLS = (0x234, 0x266, 0x267)
COLUMN = (0x236, 0x237, 0x238, 0x239, 0x23A, 0x23B)
WEIGHTS = (0x23C, 0x23D, 0x23E, 0x23E, 0x23F)
PLATE_PAL = 3                       # (the others: the spear's palette, 12)
PLAYER_PAL = os.path.join(os.path.dirname(__file__), '..', 'build', 'player', 'sprpal.bin')


def to9(c):
    return tuple(int(round(int(v) * 7 / 255)) for v in c)


def main():
    snapf, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    spr = decode_packed(load_region(ROMDIR, 'pc090oj'), 16, 16).astype(int)
    s = next(s for s in read_snaps(snapf) if s.frame == FRAME)
    pal, bank = palette_rgb(s.pal), (s.sprctrl & 0xe0) >> 1
    color = {}
    for e in range(256):
        d0, y, code, x = (int(v) for v in s.spr[e * 4:e * 4 + 4])
        if code & 0x1fff in CELLS:
            color[code & 0x1fff] = (d0 & 0xf) | bank
    assert set(color) == set(CELLS), color
    pals = [color[0x234], color[0x266]]
    assert color[0x267] == color[0x266]
    def cells(codes, remap={}):
        blob = bytearray()
        for code in codes:
            g = spr[code]
            if code in remap:
                g = np.vectorize(remap[code].get)(g)
            b = bytearray(128)
            for pl in range(4):
                for y in range(16):
                    v = 0
                    for x in range(16):
                        if (g[y, x] >> pl) & 1:
                            v |= 0x8000 >> x
                    b[pl * 32 + y * 2] = v & 0xff
                    b[pl * 32 + y * 2 + 1] = v >> 8
            blob += b
        return blob
    open(f'{out}/column.bin', 'wb').write(cells(COLUMN))
    # The plate's colours (arcade palette 3 of this bank, Rastan's) by index in Rastan's
    # PCE palette, which holds each of them exactly.
    pp = open(os.environ.get('PLAYER_PAL', PLAYER_PAL), 'rb').read()
    pce0 = [int.from_bytes(pp[2 * i:2 * i + 2], 'little') for i in range(16)]
    plate = {}
    for v in sorted(set(int(c) for c in spr[0x23F].flat)):
        if v == 0:
            plate[0] = 0
            continue
        r, g, b = to9(pal[(bank + PLATE_PAL) * 16 + v])
        want = (g << 6) | (r << 3) | b
        plate[v] = next(i for i in range(1, 16) if pce0[i] == want)
    open(f'{out}/weights.bin', 'wb').write(cells(WEIGHTS, {0x23F: plate}))
    blob = bytearray()
    for code in CELLS:
        g = spr[code]
        b = bytearray(128)
        for pl in range(4):
            for y in range(16):
                v = 0
                for x in range(16):
                    if (g[y, x] >> pl) & 1:
                        v |= 0x8000 >> x
                b[pl * 32 + y * 2] = v & 0xff
                b[pl * 32 + y * 2 + 1] = v >> 8
        blob += b
    open(f'{out}/traps.bin', 'wb').write(blob)
    vce = bytearray()
    for p in pals:
        for i in range(16):
            r, g, b = to9(pal[p * 16 + i])
            vce += ((g << 6) | (r << 3) | b).to_bytes(2, 'little')
    open(f'{out}/trappal.bin', 'wb').write(vce)
    print(f'traps: {len(CELLS)} cells, arcade palettes {pals}')


if __name__ == '__main__':
    main()
