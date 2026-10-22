"""test_enemies.py rom god_rom : headless checks for the stage 1 lizardmen and blue
club throwers (god_rom: the same game with Rastan unhurt, to reach them).

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
rom, god = sys.argv[1], sys.argv[2]
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
# Slot counts from src/enemies.asm (walkers, all objects).
_c = {}
for _ln in open(os.path.join(HERE, '..', 'src', 'enemies.asm')):
    _m = re.match(r'(NUM_EN|NUM_BIG|NUM_OBJ)\s*=\s*([^;]+)', _ln)
    if _m:
        _c[_m.group(1)] = eval(_m.group(2), {}, dict(_c))
NE, NO = _c['NUM_EN'], _c['NUM_OBJ']
HI = max(sym['e_kind'] + NO, sym['e_yh'] + NO, sym['p_y'] + 2, sym['e_state'] + NE, sym['loop_cnt'] + 2, sym['lives'] + 1, sym['hud_disp'] + 1)


def run(frames, args, rom=rom):
    out = subprocess.run([TGRUN, rom, str(frames), '/dev/null'] + [str(a) for a in args], capture_output=True,
                         text=True, check=True, env=dict(os.environ, TGRUN_PEEK=f'{LO:x},{HI}')).stdout
    rows = []
    for ln in out.splitlines():
        f, r = ln.split(':')
        b = [int(v, 16) for v in r.split()]
        rows.append(dict(frame=int(f), hp=b[sym['p_hp']], x=b[sym['p_x']] | b[sym['p_x'] + 1] << 8,
                         es=b[sym['e_state']:sym['e_state'] + NE],
                         ey=[b[sym['e_yl'] + i] | b[sym['e_yh'] + i] << 8 for i in range(NE)],
                         py=b[sym['p_y']] | b[sym['p_y'] + 1] << 8,
                         obj=[dict(kind=b[sym['e_kind'] + i], st=b[sym['e_state'] + i],
                                   x=b[sym['e_xl'] + i] | b[sym['e_xh'] + i] << 8,
                                   y=b[sym['e_yl'] + i] | b[sym['e_yh'] + i] << 8) for i in range(NO)],
                         loop=b[sym['loop_cnt']] | b[sym['loop_cnt'] + 1] << 8,
                         lives=b[sym['lives']], bar=b[sym['hud_disp']]))
    return rows


# 1. Passive: hits of 3, death on the fourth, stage restarts at full health.
r = run(900, [])
hps = [x['hp'] for x in r[10:]]
drops = [a - b for a, b in zip(hps, hps[1:]) if b < a]
check('passive Rastan is hit for 12 units (arcade 3072) each time', len(drops) >= 3 and set(drops) == {12}, f'drops {drops[:6]}')
restart = next((i for i in range(11, len(hps)) if hps[i] == 48 and min(hps[10:i]) == 0), None)
check('fourth hit kills him and the stage restarts', restart is not None, f'restart at frame {restart}')

# HUD: the bar drains a unit every 2 frames to 4 units per health point (arcade:
# 48 units for 12288); a death costs a life and refills the bar.
hp_all = [x['hp'] for x in r]
first = next(i for i in range(11, len(r)) if hp_all[i] < 48)
bars = [x['bar'] for x in r[first:first + 40]]
steps = [a - b for a, b in zip(bars, bars[1:])]
settle = bars.index(hp_all[first])
check('health bar drains 1 unit / 2 frames to the new value', set(steps) <= {0, 1} and abs(settle - 24) <= 1,
      f'{bars[0]} -> {bars[settle]} in {settle} frames')
dead = next(i for i in range(first, len(r)) if hp_all[i] == 0)
back = next(i for i in range(dead, len(r)) if hp_all[i] == 48)
check('a death costs a life and refills the bar', r[back]['lives'] == r[first]['lives'] - 1 and r[back]['bar'] == 48,
      f"lives {r[first]['lives']} -> {r[back]['lives']}, bar {r[back]['bar']}")

# Spawns (arcade, passive Rastan): gaps of 49, 81, 65 frames in turn while a slot is
# free, at most 4 alive, on the enemy lane at Rastan's height (round 1 start: y 304).
r = run(400, [])
spawns = [(b['frame'], b['ey'][i]) for a, b in zip(r, r[1:]) for i in range(NE) if not a['es'][i] and b['es'][i]]
gaps = [b[0] - a[0] for a, b in zip(spawns, spawns[1:])]
check('lizardmen come at gaps of 49, 81, 65 frames', gaps[:3] == [49, 81, 65] or gaps[:3] == [81, 65, 49]
      or gaps[:3] == [65, 49, 81], f'gaps {gaps}')
check('they spawn on the lane at his height (y 304)', spawns and {y for _, y in spawns} == {304},
      f'y {sorted({y for _, y in spawns})}, Rastan y {r[-1]["py"]}')
check('at most 4 alive', max(sum(1 for s in x['es'] if s) for x in r) <= 4)

# 2. Swinging every 30 frames: lizardmen die in one hit, Rastan stays healthy.
args = []
for f in range(100, 1500, 30):
    args += [f, f + 1, '80']
r = run(1500, args)
kills = sum(1 for a, b in zip(r, r[1:]) for i in range(NE) if a['es'][i] != 4 and b['es'][i] == 4)
check('swinging kills lizardmen', kills >= 10, f'{kills} kills')
check('swinging keeps him unhurt', min(x['hp'] for x in r[20:]) == 48, f"min hp {min(x['hp'] for x in r[20:])}")

# 3. Blue club throwers (god build: the rope route with a jump every second up to
# x 1500, then he stands): only lizardmen before x 1500, then the two take turns;
# they throw clubs that fly at 1.5 px/frame, a high pair (anchor - 20) then a low
# pair (anchor - 13, sinking 7).
args = ['60', '1215', '05']
for f in range(100, 1215, 60):
    args += [f, f + 3, '40']
r = run(1900, args, god)
spawned = [(b['frame'], o['kind'], o['x']) for a, b in zip(r, r[1:]) for i, o in enumerate(b['obj'][:NE])
           if not a['obj'][i]['st'] and o['st']]
kinds = [k for _, k, _ in spawned]
check('only lizardmen before x 1500', all(k == 0 for _, k, x in spawned if x < 1500), f'{spawned[:4]}')
late = [k for _, k, x in spawned if x >= 1500]
check('lizardmen and blue throwers take turns from x 1500', late[:4] in ([1, 0, 1, 0], [0, 1, 0, 1]), f'kinds {late}')
tracks, cur = [], {}
for x in r:
    for i, o in enumerate(x['obj'][NE:]):
        if o['st'] and o['kind'] == 2:
            cur.setdefault(i, []).append((x['frame'], o['x'], o['y']))
        elif i in cur:
            tracks.append(cur.pop(i))
check('blue throwers throw clubs', len(tracks) >= 4, f'{len(tracks)} clubs, flights of {[len(t) for t in tracks]} frames')
# Over whole flights: RAM is sampled at a fixed point of each emulated frame, and
# the game's logic can finish just before or just after it, so one sample may lag.
speeds = [round(abs(t[-1][1] - t[0][1]) / (len(t) - 1), 2) for t in tracks if len(t) > 30]
check('clubs fly at 1.5 px/frame', speeds and all(abs(s - 1.5) < 0.05 for s in speeds), f'{speeds}')
heights = [(t[0][2], t[-1][2]) for t in tracks if len(t) >= 14]
check('high clubs fly straight, low ones sink 7 px',
      all(b - a in (0, 7) for a, b in heights) and {b - a for a, b in heights} == {0, 7}, f'{heights}')

# 4. Frame budget with enemies on screen while walking and fighting.
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
