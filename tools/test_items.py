"""test_items.py rastan.pce god.pce noenemy.pce : weapons, weapon items, bats and the score, headless.

Arcade values (sim/scripts/item*.txt, see README): the cave's axe appears when
Rastan reaches x 840 (164 px left of it), its bat 20 px below it. Touching the
axe gives weapon 2 for 3000 frames. The bat bites 4 units in flight, 8 every 45
frames once clinging, and dies in one hit.
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


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


def w16(v):
    return v[0] | v[1] << 8


def shift(keys, d):
    return [k + d if isinstance(k, int) else k for k in keys]


ITEM, BAT = 4, 5
# Break the cave block, drop in, walk right under the axe (x 986).
CAVE = [60, 448, '04', 450, 453, '40', 460, 463, '82', 463, 540, '02', 560, 655, '04']
# Debug menu: ENEMIES OFF (walkers only; items still come), then the cave route.
MENU_OFF = [10, 60, '11', 66, 66, '02', 72, 72, '02', 78, 78, '40', 86, 86, '10']   # (UP + SELECT held)
VARS = {'p_weapon': 1, 'p_wtime': 2, 'p_hp': 1, 'p_x': 2, 'p_y': 2, 'items_done': 1, 'score': 3, 'hiscore': 3}
OBJ = {'e_state': 17, 'e_range': 17, 'e_xl': 17, 'e_xh': 17, 'e_yl': 17, 'e_yh': 17}


def run(r, frames, keys):
    a = peek(r, frames, keys, VARS)
    b = peek(r, frames, keys, OBJ)
    return [dict(**x, **y) for x, y in zip(a, b)]


def obj(f, k):
    return (f['e_xl'][k] | f['e_xh'][k] << 8, f['e_yl'][k] | f['e_yh'][k] << 8)


# 1. Spawn and pickup (invulnerable build; a high jump under the axe).
r = run(god, 3800, CAVE + [670, 672, '41'])
sp = next(i for i, f in enumerate(r) if f['e_state'][ITEM])
check('the axe appears when Rastan reaches x 840', abs(w16(r[sp]['p_x']) - 840) <= 2,
      f"x {w16(r[sp]['p_x'])}")
bx, by = obj(r[sp], BAT)       # (it has taken its first step)
check('at (1004, 340), its bat 20 px below', obj(r[sp], ITEM) == (1004, 340) and abs(bx - 1004) <= 2
      and abs(by - 360) <= 1,
      f'item {obj(r[sp], ITEM)}, bat {obj(r[sp], BAT)}')
took = next((i for i, f in enumerate(r) if f['p_weapon'][0] == 2), None)
check('a high jump into it takes the axe (weapon 2)', took is not None and not r[took]['e_state'][ITEM],
      f'frame {took}')
check('it lasts 3000 frames, then the sword is back', took and r[took + 2998]['p_weapon'][0] == 2
      and r[took + 3001]['p_weapon'][0] == 1, f"{r[took + 2998]['p_weapon'][0]}, {r[took + 3001]['p_weapon'][0]}")

# 2. The bat (walkers off, Rastan standing under the axe).
r = run(rom, 1500, MENU_OFF + shift(CAVE, 100))
hp = [f['p_hp'][0] for f in r]
drops = [(i, hp[i - 1] - hp[i]) for i in range(10, len(hp)) if hp[i] < hp[i - 1]]
phases = [f['e_range'][BAT] for f in r if f['e_state'][BAT]]
check('the bat flies off, hovers, dives, clings', [p for i, p in enumerate(phases) if i == 0 or phases[i - 1] != p]
      == [0, 1, 2, 3], f'phases {sorted(set(phases))}')
cl = [d for d in drops if r[d[0]]['e_range'][BAT] == 3]
check('it bites 4 units in flight', drops and drops[0][1] == 4, f'{drops[:2]}')
cl = cl[:-1]                   # (the last bite takes what is left)
check('clinging, 8 units every 45 frames', len(cl) >= 3 and all(d == 8 for _, d in cl)
      and {b[0] - a[0] for a, b in zip(cl, cl[1:])} == {45}, f'{cl[:4]}')
dead = next((i for i, f in enumerate(r) if i > 700 and f['p_hp'][0] == 0), None)
check('its bites can kill', dead is not None, f'frame {dead}')

# 3. Swinging kills the clinging bat.
keys = MENU_OFF + shift(CAVE, 100)
for f in range(1100, 1300, 25):
    keys += [f, f + 1, '80']
r = run(rom, 1300, keys)
gone = next((i for i in range(1100, 1300) if not r[i]['e_state'][BAT]), None)
check('a swing kills the bat', gone is not None, f'frame {gone}')
check('a bat is worth 200', gone and r[gone]['score'][0] - r[gone - 1]['score'][0] == 2,
      f"score {r[gone - 1]['score']} -> {r[gone]['score'] if gone else None} (hundreds, BCD)")

# Score: lizardmen are worth 300 (walking right, swinging every 20 frames).
keys = [60, 1000, '04'] + sum([[f, f + 1, '80'] for f in range(80, 1000, 20)], [])
r = run(rom, 1000, keys)
def bcd(v):
    return int(''.join(f'{b:02x}' for b in reversed(v))) * 100


deaths = sum(1 for i in range(1, len(r)) for k in range(4)
             if r[i]['e_state'][k] == 4 and r[i - 1]['e_state'][k] != 4)
check('each lizardman killed adds 300', deaths >= 5 and bcd(r[-1]['score']) == 300 * deaths,
      f"{deaths} kills, score {bcd(r[-1]['score'])}")
check('the high score starts at 273100', bcd(r[-1]['hiscore']) == 273100, f"{bcd(r[-1]['hiscore'])}")

# 4. A death brings the items back.
r = run(rom, 1600, MENU_OFF + shift(CAVE, 100))
after = [f['items_done'][0] for f in r[-60:]]
check('after a death the items can come again', r[1000]['items_done'][0] == 1 and all(v == 0 for v in after),
      f"{r[1000]['items_done'][0]} -> {set(after)}")


# 5. Each weapon is drawn: debug menu WEAPON (line 6), then a swing.
def shot(w, frame):
    keys = [10, 60, '11'] + sum([[66 + 6 * k, 66 + 6 * k, '02'] for k in range(6)], [])
    keys += sum([[110 + 6 * k, 110 + 6 * k, '04'] for k in range(w - 1)], []) + [140, 140, '10', 160, 161, '80']
    out = os.path.join(tmp, f'items_{os.getpid()}.ppm')
    subprocess.run([TGRUN, noen, str(frame), out] + [str(k) for k in keys], check=True, capture_output=True)
    return np.array(Image.open(out))[40:150, 32:200].astype(int)


# Over a few frames of the swing: the fire sword's flame cycles (4 steps, 2 frames
# each), and at its smallest it hides behind the blade on a single frame.
FRAMES = (166, 168, 170, 172)
sword = [shot(1, f) for f in FRAMES]
for w, name in ((2, 'axe'), (3, 'morning star'), (4, 'fire sword')):
    d = max(int((shot(w, f) != s_).any(-1).sum()) for f, s_ in zip(FRAMES, sword))
    check(f'the {name} is drawn in his swing', d > 20, f'up to {d} pixels differ from the sword')
flame = (shot(4, 150) != shot(4, 152)).any(-1).sum()
check('the fire sword flickers (flame steps every 2 frames)', flame > 0, f'{flame} pixels')

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
