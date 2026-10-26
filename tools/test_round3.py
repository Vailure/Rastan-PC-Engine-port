"""test_round3.py testdbg.pce bgcheck.pce god.pce stage3dir : round 3, headless.

Round 3 (map segments $2E-$44, src/debug.asm's checkpoints 17-23, its boss room's warp 24):
- each checkpoint warp starts round 3 with Rastan and the camera where the arcade restarts
  there (sim/scripts/round3.txt with the restart table byte $50768 patched);
- the tile map there, and as Rastan walks right from the round's start, is the converter's
  (build/stage3/preview.png; bgcheck build: the tile map alone);
- its walkers: lizardmen and chimeras, then (from $32) horned men, snakes, harpies (which throw
  blades) and skeletons;
- its first weapon item, an axe at (1088, 292), with its bat;
- its boss, the wizard (sim/scripts/boss3.txt): it appears at x 256 of the room, y 384, stands
  57 frames and drops to the floor (448); 309 frames after landing, then 137 later, it casts a fan
  of five fireballs; the sword hurts it, after which it is gone 133 frames; ten blows kill it,
  for 20000 (not measured), and the round is clear.
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
check('its first walkers are two lizardmen, a chimera, a lizardman', kinds[:4] == [0, 0, 5, 0], f'kinds {kinds[:6]}')

# From $32: horned men, snakes, harpies and skeletons in turn; the harpies throw blades.
EK_HORN, EK_SNAKE, EK_SKEL, EK_HARPY, EK_BLADE = 22, 18, 23, 24, 25
b = resume(god, 18)
r = peek(god, b + 900, warp(18), {'e_state': 17, 'e_kind': 17})
new = [r[i]['e_kind'][k] for i in range(b + 1, len(r)) for k in range(17)
       if r[i]['e_state'][k] and not r[i - 1]['e_state'][k]]
walk = [k for k in new if k != EK_BLADE]
check('from $32 horned men, snakes, harpies and skeletons come in turn',
      walk[:4] == [EK_HORN, EK_SNAKE, EK_HARPY, EK_SKEL], f'kinds {walk[:6]}')
check('the harpy throws blades', EK_BLADE in new, f'kinds {new[:10]}')

# The first item: an axe at (1088, 292) with its bat when Rastan reaches 924 (god build, walking
# and hopping right from the start).
ITEM, BAT = 4, 5
b = resume(god, CP0)
keys = warp(CP0) + [b + 10, b + 760, '04'] + sum([[t, t + 3, '40'] for t in range(b + 30, b + 760, 40)], [])
r = peek(god, b + 760, keys, {'e_state': 17, 'e_kind': 17, 'e_xl': 17, 'e_xh': 17, 'e_yl': 17, 'e_yh': 17,
                               'e_alt': 17, 'p_x': 2})
i = next((i for i in range(1, len(r)) if r[i]['e_state'][ITEM] and not r[i - 1]['e_state'][ITEM]), None)
pos = i and ((r[i]['e_xl'][ITEM] | r[i]['e_xh'][ITEM] << 8), (r[i]['e_yl'][ITEM] | r[i]['e_yh'][ITEM] << 8))
check('the first item, an axe, comes at (1088, 292) when Rastan reaches 924, with its bat',
      i and pos == (1088, 292) and r[i]['e_alt'][ITEM] == 2 and r[i]['e_kind'][BAT] == 4
      and 924 <= s16(r[i]['p_x']) < 932, f"{pos}, at x {i and s16(r[i]['p_x'])}")

# The wizard: Rastan passive in its room (the boss warp, 24).
EK_WIZ, EK_WFIRE, SPEC, ROOM = 26, 28, 6, 11264
b = resume(rom, 24)
r = peek(rom, b + 700, warp(24), {'e_state': 17, 'e_kind': 17, 'e_xl': 17, 'e_xh': 17, 'e_yl': 17, 'e_yh': 17})
come = next((i for i in range(b, len(r)) if r[i]['e_state'][SPEC] and r[i]['e_kind'][SPEC] == EK_WIZ), None)
pos = lambda f, k: ((f['e_xl'][k] | f['e_xh'][k] << 8) - ROOM, f['e_yl'][k] | f['e_yh'][k] << 8)
check('the wizard appears at x 256 of the room, y 384', come and pos(r[come], SPEC) == (256, 384),
      f'at {come and pos(r[come], SPEC)}')
land = next((i for i in range(come or b, len(r)) if pos(r[i], SPEC)[1] == 448), None) if come else None
check('it drops to the floor (448) after standing 57 frames', land and 56 <= land - come <= 100,
      f'landed {land and land - come} frames after it came')
fans = [i for i in range(1, len(r)) if sum(1 for k in range(9, 17) if r[i]['e_state'][k] and r[i]['e_kind'][k] == EK_WFIRE
                                          and not r[i - 1]['e_state'][k]) == 5]
check('309 frames after landing, then 137 later, a fan of five fireballs',
      land and [f - land for f in fans][:2] == [309 + 17, 309 + 137 + 17], f'fans at {[f - land for f in fans] if land else fans}')

# Ten blows kill it (god build): Rastan goes at it, swinging every 14 frames.
b = resume(god, 24)
keys, t, dead, V = warp(24), b + 100, None, {'wz_hits': 1, 'e_alt': 17, 'e_state': 17, 'p_x': 2, 'e_xl': 17, 'e_xh': 17,
                                            'score': 3, 'boss_clear': 1}
hits = []
while t < b + 6000 and dead is None:
    r = peek(god, t, keys, V)
    f = r[-1]
    hits.append(f['wz_hits'][0])
    if f['e_state'][SPEC] == 4:
        dead = t
        break
    px, wx = s16(f['p_x']), f['e_xl'][SPEC] | f['e_xh'][SPEC] << 8
    if abs(wx - px) >= 40 and f['e_alt'][SPEC] != 4:
        keys += [t, t + 59, '04' if wx > px else '08']
    keys += sum([[x, x + 3, '80'] for x in range(t, t + 60, 14)], [])
    t += 60
bcd = lambda v: sum(((x >> 4) * 10 + (x & 15)) * 100 ** n for n, x in enumerate(v))
r = peek(god, (dead or t) + 300, keys, V)
check('ten blows kill it, for 20000; then the round is clear', dead and bcd(r[dead + 2]['score']) - bcd(r[dead - 62]['score']) == 200
      and any(x['boss_clear'][0] == 1 for x in r[dead:]), f'dead {dead and dead - b}, hits {hits[-1:]}')

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
