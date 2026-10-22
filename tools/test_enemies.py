"""test_enemies.py rom : headless checks for the stage 1 lizardmen.

Compared with the arcade (sim/scripts/lizard.txt): a passive Rastan is hit in
quarters of his health and dies on the fourth hit; swinging regularly kills
them in one hit each without being hurt.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(__file__)
TGRUN = os.path.join(HERE, 'tgrun', 'tgrun')
LST = os.path.join(HERE, '..', 'src', 'main.lst')
rom = sys.argv[1]
fails = []


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


sym = {}
for ln in open(LST):
    m = re.match(r'\s*\d+\s+F8:([0-9A-F]{4})\s+(\w+):', ln)
    if m:
        sym[m.group(2)] = int(m.group(1), 16) - 0x2000
LO = 0
HI = max(sym['e_state'] + 3, sym['loop_cnt'] + 2)


def run(frames, args):
    out = subprocess.run([TGRUN, rom, str(frames), '/dev/null'] + [str(a) for a in args], capture_output=True,
                         text=True, check=True, env=dict(os.environ, TGRUN_PEEK=f'{LO:x},{HI}')).stdout
    rows = []
    for ln in out.splitlines():
        f, r = ln.split(':')
        b = [int(v, 16) for v in r.split()]
        rows.append(dict(frame=int(f), hp=b[sym['p_hp']], x=b[sym['p_x']] | b[sym['p_x'] + 1] << 8,
                         es=b[sym['e_state']:sym['e_state'] + 3],
                         loop=b[sym['loop_cnt']] | b[sym['loop_cnt'] + 1] << 8))
    return rows


# 1. Passive: hits of 3, death on the fourth, stage restarts at full health.
r = run(900, [])
hps = [x['hp'] for x in r[10:]]
drops = [a - b for a, b in zip(hps, hps[1:]) if b < a]
check('passive Rastan is hit for 3 health each time', len(drops) >= 3 and set(drops) == {3}, f'drops {drops[:6]}')
restart = next((i for i in range(11, len(hps)) if hps[i] == 12 and min(hps[10:i]) == 0), None)
check('fourth hit kills him and the stage restarts', restart is not None, f'restart at frame {restart}')

# 2. Swinging every 30 frames: lizardmen die in one hit, Rastan stays healthy.
args = []
for f in range(100, 1500, 30):
    args += [f, f + 1, '80']
r = run(1500, args)
kills = sum(1 for a, b in zip(r, r[1:]) for i in range(3) if a['es'][i] != 4 and b['es'][i] == 4)
check('swinging kills lizardmen', kills >= 10, f'{kills} kills')
check('swinging keeps him unhurt', min(x['hp'] for x in r[20:]) == 12, f"min hp {min(x['hp'] for x in r[20:])}")

# 3. Frame budget with enemies on screen while walking and fighting.
args = [60, 1500, '04']
for f in range(80, 1500, 30):
    args += [f, f + 1, '80']
r = run(1500, args)
slow = 0
for a, b in zip(r[200:], r[201:]):
    if b['loop'] - a['loop'] != 1 and not (b['x'] == 48 or a['x'] == 48):   # stage restarts load with the display off
        slow += 1
active = max(sum(1 for s in x['es'] if s) for x in r)
check('no slow frames with enemies active', slow == 0, f'{slow} slow frames, up to {active} enemies')

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
