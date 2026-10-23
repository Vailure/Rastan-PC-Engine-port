"""test_castle.py rastan.pce god.pce : the castle's shafts, the swinging vines, the door into
the boss room, headless.

The arcade streams some of round 1's map segments upwards (tools/world.py): the castle
climbs two shafts. Routes (god build, debug-menu warps to checkpoints 4 and 5):
  A  checkpoint 4 (the castle's first room): past the floor spears, the ropes up into shaft 1 (its rows stream,
     the camera follows up), out at its top into the lava hall, across on the three
     swinging vines, onto the far side;
  B  checkpoint 5 (past the lava hall): the jets' room, shaft 2, the door at its top into
     the boss room (dropped in at (11728, 98) as in the arcade), the boss, round clear;
  V  checkpoint 1: the vine over the chasm at x 2750, caught and let go of, landing on
     the far ledge (the arcade bot: 2863, 135).
"""
import os
import subprocess
import sys
import numpy as np
from PIL import Image
from peek import peek
from trace_player import TGRUN

rom, god, noen = sys.argv[1:4]
tmp = os.environ.get('TMPDIR', '/tmp')
fails = []
SEL, RIGHT, I = '10', '04', '40'
OPEN = '11'                   # UP + SELECT, held, opens the debug menu (DBG_HOLD)
ST_CLIMB, ST_DEAD, ST_SWING = 6, 8, 9


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


def w16(v):
    return v[0] | v[1] << 8


def s16(v):
    return (w16(v) ^ 0x8000) - 0x8000


def warp(cp):
    return ([40, 90, OPEN] + sum([[100 + 6 * k, 100 + 6 * k, RIGHT] for k in range(cp)], [])
            + [150, 150, I])


VARS = {'p_x': 2, 'p_y': 2, 'p_state': 1, 'p_vine': 1, 'scroll_x': 2, 'scroll_y': 2, 'cam_region': 1,
        'next_col': 2, 'score': 3, 'loop_cnt': 2}
OBJ = {'e_state': 17, 'e_kind': 17}


def run(r, end, keys, extra=None):
    a = peek(r, end, keys, VARS)
    if extra:
        b = peek(r, end, keys, extra)
        a = [dict(**x, **y) for x, y in zip(a, b)]
    return a


from routes import ROUTE_A, ROUTE_SHAFT, ROUTE_B, ROUTE_V

# A: up shaft 1 and across the lava hall.
r = run(god, 3600, warp(4) + ROUTE_A)
ys = [s16(f['scroll_y']) for f in r]
check('the floor spears of the middle corridor can be walked past', all(f['p_state'][0] != ST_DEAD for f in r),
      f"died at frame {next((i for i, f in enumerate(r) if f['p_state'][0] == ST_DEAD), None)}")
check('climbing out of the first room, the camera follows up into shaft 1', min(ys[:2800]) <= -450,
      f'highest scroll_y {min(ys[:2800])}')
top = next((i for i, f in enumerate(r) if f['cam_region'][0] == 2), None)
check("once the shaft's rows have all streamed, the lava hall's columns come next",
      top is not None and w16(r[top]['next_col']) >= 0x12 * 64, f"frame {top}")
vines = sorted({f['p_vine'][0] for f in r if f['p_state'][0] == ST_SWING})
check('the three vines over the lava are caught in turn', len(vines) == 3, f'vine slots {vines}')
end = r[-1]
check('he lands past the lava', w16(end['p_x']) >= 9280 and s16(end['p_y']) == -345
      and all(f['p_state'][0] != ST_DEAD for f in r[2800:]), f"at ({w16(end['p_x'])}, {s16(end['p_y'])})")
lc = [w16(f['loop_cnt']) for f in r]
slow = min((lc[i + 60] - lc[i]) & 0xffff for i in range(300, len(r) - 60, 60))
check('no slowdown on the way (60 logic frames a second)', slow >= 59, f'fewest {slow}')

# B: shaft 2, the door, the boss.
r = run(god, 4400, warp(5) + ROUTE_B, OBJ)
door = next((i for i, f in enumerate(r) if w16(f['p_x']) == 11728), None)
check('the door at the top of shaft 2 drops him into the boss room at (11728, 98)',
      door is not None and s16(r[door - 1]['p_y']) < -800 and 98 <= s16(r[door]['p_y']) < 130,
      f"frame {door}, from y {s16(r[door - 1]['p_y']) if door else None}")
boss = next((i for i in range(door or 0, len(r)) if any(r[i]['e_kind'][k] == 14 and r[i]['e_state'][k]
                                                       for k in range(6, 9))), None) if door else None
check('the boss comes', boss is not None and boss - door < 60, f'frame {boss}')
won = next((i for i in range(door or 0, len(r)) if r[i]['score'][0] == 0x50), None) if door else None
clear = next((i for i in range(won or 0, len(r)) if w16(r[i]['p_x']) == 48), None) if won else None
check('killing it scores 5000, and the round is clear (then a new game: test build)',
      won is not None and clear is not None, f"5000 at frame {won}, restart at {clear}")

# V: the vine over the chasm.
r = run(god, 1100, warp(1) + ROUTE_V)
sw = [i for i, f in enumerate(r) if f['p_state'][0] == ST_SWING]
check('the vine at x 2750 is caught from the cliff', sw and 2700 <= w16(r[sw[0]]['p_x']) <= 2780,
      f"at {(w16(r[sw[0]]['p_x']), s16(r[sw[0]]['p_y'])) if sw else None}")
xs = [w16(r[i]['p_x']) for i in sw]
check('it swings him out and back (the vine reaches 43 px either side of its anchor)',
      sw and max(xs) - min(xs) >= 60, f'x {min(xs) if xs else 0}..{max(xs) if xs else 0}')
land = next((i for i in range(sw[-1] if sw else 0, len(r)) if r[i]['p_state'][0] in (0, 1)), None)
check('jumping off on the far side lands on the ledge (arcade: 2863, 135)', land is not None
      and 2840 <= w16(r[land]['p_x']) <= 2890 and s16(r[land]['p_y']) == 135,
      f"at {(w16(r[land]['p_x']), s16(r[land]['p_y'])) if land else None}")


# The debug menu in a shaft: the tile map comes back.
def shot(keys, frame):
    out = os.path.join(tmp, f'castle_{os.getpid()}.ppm')
    subprocess.run([TGRUN, noen, str(frame), out] + [str(k) for k in keys], check=True, capture_output=True)
    return np.array(Image.open(out))[:224, 32:288]


base = warp(4) + ROUTE_SHAFT                   # (hanging still at a rope's top, nothing moving)
plain = shot(base, 2520)
menu = shot(base + [2430, 2480, OPEN, 2490, 2490, SEL], 2520)
diff = (plain != menu).any(-1).mean() * 100
check('in a shaft, closing the debug menu restores the screen', diff == 0, f'{diff:.2f}% pixels differ')

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
