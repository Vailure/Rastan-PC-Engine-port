"""test_round3.py testdbg.pce bgcheck.pce god.pce stage3dir : round 3, headless.

Round 3 (map segments $2E-$44, src/debug.asm's checkpoints 17-23, its boss room's warp 24):
- each checkpoint warp starts round 3 with Rastan and the camera where the arcade restarts
  there (sim/scripts/round3.txt with the restart table byte $50768 patched);
- the tile map there, and as Rastan walks right from the round's start, is the converter's
  (build/stage3/preview.png; bgcheck build: the tile map alone);
- its walkers are lizardmen and chimeras.
"""
import os
import subprocess
import sys
import numpy as np
from PIL import Image
from peek import peek
from routes import warp, resume
from trace_player import TGRUN

rom, bgc, god, stage = sys.argv[1:5]
tmp = os.environ.get('TMPDIR', '/tmp')
fails = []


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


s16 = lambda v: (v[0] | v[1] << 8) - (65536 if v[1] & 0x80 else 0)
CP0 = 17
CPS = {17: (48, 295), 18: (2384, 295), 19: (3472, 295), 20: (5680, 295), 21: (8240, 295), 22: (9296, -89),
       23: (11328, 391), 24: (11328, 391)}

# Checkpoints: the round, Rastan where the arcade puts him, standing.
got = {}
for cp, (x, y) in CPS.items():
    b = resume(rom, cp)
    f = peek(rom, b + 30, warp(cp), {'p_x': 2, 'p_y': 2, 'p_state': 1, 'cur_round': 1, 'cur_cp': 1})[-1]
    got[cp] = (f['cur_round'][0], f['cur_cp'][0], s16(f['p_x']), s16(f['p_y']), f['p_state'][0])
check('every round 3 checkpoint warp starts round 3 there, Rastan where the arcade puts him',
      all(g[:4] == (3, cp, CPS[cp][0], CPS[cp][1]) for cp, g in got.items()), f'{got}')

# The tile map at each checkpoint, then walking right from the start (bgcheck: tile map only).
Y0 = next(int(ln.split('=')[1].split(';')[0]) for ln in open(os.path.join(stage, 'stage.inc'))
          if ln.split('=')[0].strip().endswith('PREVIEW_Y0'))
PREV = np.rint(np.array(Image.open(os.path.join(stage, 'preview.png'))).astype(int) * 7 / 255).astype(int)


def shot(romf, frame, keys):
    out = os.path.join(tmp, f'r3_{os.getpid()}.ppm')
    subprocess.run([TGRUN, romf, str(frame), out] + [str(k) for k in keys], check=True, capture_output=True)
    return np.array(Image.open(out))[:224, 32:288].astype(int) >> 5


def matches(sh, x0, y0, reach=4):
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            x, y = x0 + dx, y0 + dy
            ref = PREV[y - Y0:y - Y0 + 224, x:x + 256]
            if y >= Y0 and ref.shape == sh.shape and not (ref != sh).any():
                return True
    return False


bad = []
for cp in CPS:
    b = resume(bgc, cp)
    f = peek(bgc, b + 20, warp(cp), {'scroll_x': 2, 'scroll_y': 2})[-1]
    if not matches(shot(bgc, b + 20, warp(cp)), s16(f['scroll_x']), s16(f['scroll_y'])):
        bad.append(cp)
check("the tile map at each checkpoint is the converter's", not bad, f'wrong at {bad}')

b = resume(bgc, CP0)
keys = warp(CP0) + [b + 10, b + 760, '04'] + sum([[t, t + 3, '40'] for t in range(b + 30, b + 760, 40)], [])
r = peek(bgc, b + 760, keys, {'scroll_x': 2, 'scroll_y': 2, 'p_x': 2})
bad = [t for t in range(b + 100, b + 760, 110)
       if not matches(shot(bgc, t, keys), s16(r[t]['scroll_x']), s16(r[t]['scroll_y']))]
check("walking right from the start (up the steps to the slope), the tile map is the converter's",
      not bad and s16(r[-1]['p_x']) > 800, f"wrong at {bad}, reached x {s16(r[-1]['p_x'])}")

# Walkers: lizardmen and chimeras in turn (Rastan standing at the start; god build).
b = resume(god, CP0)
r = peek(god, b + 900, warp(CP0), {'e_state': 17, 'e_kind': 17})
kinds = [r[i]['e_kind'][k] for i in range(b + 1, len(r)) for k in range(4)
         if r[i]['e_state'][k] and not r[i - 1]['e_state'][k]]
check('its walkers are lizardmen and chimeras in turn', kinds[:4] == [0, 5, 0, 5], f'kinds {kinds[:6]}')

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
