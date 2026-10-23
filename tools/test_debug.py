"""test_debug.py rastan.pce noenemy.pce : checkpoints and the debug menu, headless.

- Opening and closing the menu leaves the screen exactly as it was.
- Warping to each checkpoint puts Rastan where the arcade restarts him, standing.
- INVINCIBLE stops the lizardmen's hits.
- A death restarts at the last checkpoint reached, not at the start.
"""
import os
import subprocess
import sys
import numpy as np
from PIL import Image
from trace_player import trace, TGRUN

rom, noen = sys.argv[1], sys.argv[2]
tmp = os.environ.get('TMPDIR', '/tmp')
fails = []
SEL, I, RIGHT, DOWN = '10', '40', '04', '02'
# Checkpoint 5 is in the lava hall, square ($12, -1) of the world (tools/world.py): y -57.
CP = [(48, 295), (2096, 263), (4144, 295), (6192, 295), (8240, 455), (9296, 65536 - 57)]


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


def shot(r, frames, args):
    out = os.path.join(tmp, f'dbg_{os.getpid()}.ppm')
    subprocess.run([TGRUN, r, str(frames), out] + [str(a) for a in args], check=True, capture_output=True)
    return np.array(Image.open(out))[:224, 32:288]


def press(frames_keys):
    """[(frame, key)] -> tgrun args, one frame each."""
    a = []
    for f, k in frames_keys:
        a += [f, f, k]
    return a


# 1. Menu open/close restores the screen (no enemies, Rastan idle).
plain = shot(noen, 200, [])
menu = shot(noen, 200, press([(120, SEL), (140, SEL)]))
diff = (plain != menu).any(-1).mean() * 100
check('closing the menu restores the screen exactly', diff == 0, f'{diff:.2f}% pixels differ')
inmenu = shot(noen, 130, press([(120, SEL)]))
check('the menu is drawn while open', (inmenu != shot(noen, 130, [])).any(-1).mean() > 0.3)

# 2. Warp to each checkpoint: Rastan at the arcade's restart point, standing still.
for cp in range(1, 6):
    keys = [(100, SEL)] + [(110 + 6 * k, RIGHT) for k in range(cp)] + [(150, I)]
    r = trace(noen, 400, press(keys))
    end = r[-1]
    stood = all(x['state'] == 0 and (x['x'], x['y']) == CP[cp] for x in r[-60:])
    check(f'warp to checkpoint {cp} puts Rastan at {CP[cp]}, standing', stood,
          f"at ({end['x']},{end['y']}) state {end['state']}")

# 3. INVINCIBLE: passive Rastan, lizardmen attack; no health lost.
args = press([(60, SEL), (66, DOWN), (72, I), (80, SEL)])
import re
LST = os.path.join(os.path.dirname(__file__), '..', 'src', 'main.lst')
sym = {}
for ln in open(LST):
    m = re.match(r'\s*\d+\s+F8:([0-9A-F]{4})\s+(\w+):', ln)
    if m:
        sym[m.group(2)] = int(m.group(1), 16) - 0x2000


def peek(r, frames, args, name):
    out = subprocess.run([TGRUN, r, str(frames), '/dev/null'] + [str(a) for a in args], capture_output=True,
                         text=True, check=True, env=dict(os.environ, TGRUN_PEEK=f'{sym[name]:x},1')).stdout
    return [int(l.split(':')[1].split()[0], 16) for l in out.splitlines()]


hp_god = peek(rom, 900, args, 'p_hp')
hp_plain = peek(rom, 900, [], 'p_hp')
check('INVINCIBLE: lizardmen do no damage', min(hp_god[100:]) == 48 and min(hp_plain[100:]) < 48,
      f'min hp {min(hp_god[100:])} (without: {min(hp_plain[100:])})')

# 4. Death restarts at the checkpoint: warp to 2, run right (UP+RIGHT, jumping) into
#    the second waterfall (x 5568-5919, before checkpoint 3); he must come back at 2.
args = press([(100, SEL), (110, RIGHT), (116, RIGHT), (150, I)]) + [200, 2000, '05']
for f in range(220, 2000, 60):
    args += [f, f + 3, I]
r = trace(noen, 2000, args)
died = next((i for i in range(200, len(r)) if r[i]['state'] == 8), None)
back = next((x for x in r[died:] if x['state'] != 8), None) if died else None
check('a death restarts at the checkpoint reached', died is not None and back is not None
      and (back['x'], back['y']) == CP[2], f"died at x {r[died]['x'] if died else None}, "
      f"restart at {(back['x'], back['y']) if back else None}")

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
