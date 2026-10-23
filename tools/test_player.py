"""test_player.py rom : behavior checks for Rastan, run headless.

Each check drives the pad and compares the trace with values measured in the
arcade program (see README). Exits non-zero on any failure.
"""
import sys
from trace_player import trace, symbols, TGRUN
import os
import subprocess

rom = sys.argv[1]
fails = []


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


def run(frames, *inputs):
    return trace(rom, frames, list(inputs))


# Start position (arcade x 32 / y 112 mapped to world) and idle.
r = run(60)
check('starts idle at (48,295)', (r[-1]['x'], r[-1]['y'], r[-1]['state']) == (48, 295, 0),
      f"{r[-1]['x']},{r[-1]['y']} state {r[-1]['state']}")

# Walk: 1 px/frame for 15 frames, then 2 px/frame (measured in the arcade).
r = run(140, 60, 139, '04')
d = [r[f]['x'] - r[f - 1]['x'] for f in range(61, 120)]
check('walk speed ramp 1px x15 then 2px', d[:15] == [1] * 15 and set(d[15:]) == {2}, f'{d[:20]}')

# Low jump: 36 px up, back on the ground after 36 frames.
r = run(200, 100, 102, '40')
ys = [x['y'] for x in r[100:180]]
peak = 295 - min(ys)
land = next(i for i, x in enumerate(r[101:], 101) if x['state'] == 0) - 100
check('low jump height 36', peak == 36, f'{peak}')
check('low jump lands after 36 frames', abs(land - 37) <= 1, f'{land}')

# High jump (UP+I): 68 px.
r = run(200, 100, 102, '41')
peak = 295 - min(x['y'] for x in r[100:200])
check('high jump height 68', peak == 68, f'{peak}')

# Standing attack: 21 frames, then idle.
r = run(160, 100, 101, '80')
atk = [x['state'] for x in r[100:140]]
n = sum(1 for s in atk if s == 4)
check('attack lasts 21 frames', abs(n - 21) <= 1, f'{n}')
check('attack returns to idle', r[-1]['state'] == 0)

# UP+attack standing: the sword over his head (arcade bodies 12, 13, 14, 13, 12 for
# 4, 4, 8, 2, 4 frames), then idle.
r = run(160, 100, 101, '81')
up = [x['pose'] for x in r[100:140] if x['state'] == 10]
seq = [p for i, p in enumerate(up) if i == 0 or up[i - 1] != p]
check('UP+attack swings over his head: 3 poses there and back, 22 frames',
      abs(len(up) - 22) <= 1 and len(seq) == 5 and seq == seq[::-1], f'{len(up)} frames, poses {seq}')
check('UP+attack returns to idle', r[-1]['state'] == 0)

# Down thrust: jump, then DOWN+II - sword-down pose held through the fall, lands crouched.
r = run(200, 100, 102, '40', 110, 113, '82', 113, 160, '02')
air = [x for x in r[120:160] if x['state'] == 3]
poses = sorted({x['pose'] for x in air})
landed = next((x for x in r[110:200] if x['state'] != 3), None)
check('down thrust holds a single pose while falling', len(air) > 5 and len({x['pose'] for x in air[-5:]}) == 1,
      f'poses {poses}')
check('down thrust lands crouched', landed is not None and landed['state'] == 2,
      f"state {landed['state'] if landed else None}")

# Crouch while DOWN is held.
r = run(130, 100, 120, '02')
check('crouch while DOWN held', r[110]['state'] == 2 and r[-1]['state'] == 0)

# Rope route: hold RIGHT+UP, jump every second; must reach the rope and get past the pit.
args = ['60', '1600', '05']
for f in range(100, 1600, 60):
    args += [str(f), str(f + 3), '40']
r = trace(rom, 1600, args)
climbed = any(x['state'] == 6 for x in r)
past = max(x['x'] for x in r)
check('catches and climbs the first rope', climbed)
check('gets past the rope pit (x > 1500)', past > 1500, f'max x {past}')

# Frame budget: the main loop runs exactly once per frame during that run.
lst = os.path.join(os.path.dirname(__file__), '..', 'src', 'main.lst')
import re
off = None
for ln in open(lst):
    m = re.match(r'\s*\d+\s+F8:(20[0-9A-F]{2})\s+loop_cnt:', ln)
    if m:
        off = int(m.group(1), 16) - 0x2000
out = subprocess.run([TGRUN, rom, '1500', '/dev/null'] + args, capture_output=True, text=True, check=True,
                     env=dict(os.environ, TGRUN_PEEK=f'{off:x},2')).stdout.split('\n')
cnt = [int(l.split(':')[1].split()[0], 16) | int(l.split(':')[1].split()[1], 16) << 8 for l in out if ':' in l]
slow = sum(1 for i in range(200, len(cnt)) if cnt[i] - cnt[i - 1] != 1)
check('no slow frames during play', slow == 0, f'{slow} frames')

# Cave block (x 798-830 over the 32 px gap): walking right crosses it; a down
# thrust onto it crumbles it (arcade: 3 steps of 6 frames) and he drops into the cave.
r = run(600, 60, 600, '04')
on = [x for x in r if 800 <= x['x'] <= 830]
check('the cave block holds him up', on and all(x['y'] == 295 for x in on), f"y {sorted({x['y'] for x in on})}")
r = run(600, 60, 448, '04', 450, 453, '40', 460, 463, '82', 463, 540, '02')
land = next((x['frame'] for x in r if x['frame'] > 470 and x['state'] == 2), None)
fall = next((x['frame'] for x in r if x['frame'] > 470 and x['y'] > 300), None)
check('a down thrust breaks it and he falls into the cave', land and fall and 10 <= fall - land <= 40
      and r[-1]['y'] > 400, f'landed {land}, falling {fall}, y {r[-1]["y"]}')

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
