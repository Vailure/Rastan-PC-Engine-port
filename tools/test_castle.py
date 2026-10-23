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


from routes import ROUTE_A, ROUTE_SHAFT, ROUTE_B, ROUTE_V, SHAFT_HANG, A_LATE, keys as route_keys

# A: up shaft 1 and across the lava hall.
ka, base = route_keys(god, 4, ROUTE_A)
r = run(god, base + 3377 + A_LATE, ka)       # (+A_LATE: the column and spears, routes.py)
ys = [s16(f['scroll_y']) for f in r]
check('the floor spears of the middle corridor can be walked past', all(f['p_state'][0] != ST_DEAD for f in r),
      f"died at frame {next((i for i, f in enumerate(r) if f['p_state'][0] == ST_DEAD), None)}")
# The spears are map objects: the arcade puts them in play as the camera rises past
# the middle room's floor (its view's top at y 247: camy 239, sim/scripts/spikes.txt),
# not at the restart below, where the floor's underside shows; the second trap rises
# 10 frames after they appear (trap_t 22), the first 32 after that.
rt = peek(god, base + 900, ka, {'trap_on': 1, 'trap_t': 1, 'scroll_y': 2})
on = next((i for i, f in enumerate(rt) if f['trap_on'][0]), None)
check('the floor spears appear as the camera rises past y 248, not at the restart below',
      on is not None and on > base + 100 and s16(rt[on]['scroll_y']) < 248 <= s16(rt[on - 1]['scroll_y'])
      and rt[on]['trap_t'][0] == 22, f"at {on}, scroll_y {s16(rt[on]['scroll_y']) if on else None}, "
      f"clock {rt[on]['trap_t'][0] if on else None}")
check('climbing out of the first room, the camera follows up into shaft 1', min(ys[:base + 2577 + A_LATE]) <= -450,
      f'highest scroll_y {min(ys[:base + 2577 + A_LATE])}')
top = next((i for i, f in enumerate(r) if f['cam_region'][0] == 2), None)
check("once the shaft's rows have all streamed, the lava hall's columns come next",
      top is not None and w16(r[top]['next_col']) >= 0x12 * 64, f"frame {top}")
vines = sorted({f['p_vine'][0] for f in r if f['p_state'][0] == ST_SWING})
check('the three vines over the lava are caught in turn', len(vines) == 3, f'vine slots {vines}')
end = r[-1]
check('he lands past the lava', w16(end['p_x']) >= 9280 and s16(end['p_y']) == -345
      and all(f['p_state'][0] != ST_DEAD for f in r[base + 2577 + A_LATE:]), f"at ({w16(end['p_x'])}, {s16(end['p_y'])})")
lc = [w16(f['loop_cnt']) for f in r]
slow = min((lc[i + 60] - lc[i]) & 0xffff for i in range(300, len(r) - 60, 60))
check('no slowdown on the way (60 logic frames a second)', slow >= 59, f'fewest {slow}')

# B: shaft 2, the door, the boss.
kb, base = route_keys(god, 5, ROUTE_B)
r = run(god, base + 4172, kb, OBJ)
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
kv, base = route_keys(god, 1, ROUTE_V)
r = run(god, base + 927, kv)
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


# The castle wall: outside, the camera stops short of the castle's rooms (whose palettes
# are not loaded then); through the gate, it stays inside. (Running right from checkpoint 3,
# holding UP, high jumps.)
keys = warp(3) + [200, 2000, '05'] + sum([[f, f + 2, '41'] for f in range(260, 2000, 60)], [])
r = run(god, 2000, keys)
# (RAM is sampled once a frame, partway through the game's frame: a sample can catch
# scroll_x between camera_update and its clamp. A frame's scroll is what the next
# sample still shows, so a camera past the wall shows in two samples running.)
outside = [min(w16(f['scroll_x']), w16(g['scroll_x'])) for f, g in zip(r[200:], r[201:]) if w16(f['p_x']) < 8192]
inside = [w16(f['scroll_x']) for f in r[200:] if w16(f['p_x']) >= 8192]
check('outside the castle the camera stops at its wall (scroll_x <= 7936)', outside and max(outside) <= 7936,
      f'max {max(outside) if outside else None}')
check('through the gate it stays inside the castle (scroll_x >= 8192)', inside and min(inside) >= 8192,
      f'min {min(inside) if inside else None}')


# The debug menu in a shaft: the tile map comes back.
def shot(keys, frame):
    out = os.path.join(tmp, f'castle_{os.getpid()}.ppm')
    subprocess.run([TGRUN, noen, str(frame), out] + [str(k) for k in keys], check=True, capture_output=True)
    return np.array(Image.open(out))[:224, 32:288]


ks, b4 = route_keys(noen, 4, ROUTE_SHAFT)     # (hanging still at a rope's top, nothing moving)
km, _ = route_keys(noen, 4, ROUTE_SHAFT, [SHAFT_HANG - 42, SHAFT_HANG + 8, OPEN, SHAFT_HANG + 18, SHAFT_HANG + 18, SEL])
plain = shot(ks, b4 + SHAFT_HANG + 48)
menu = shot(km, b4 + SHAFT_HANG + 48)
diff = (plain != menu).any(-1).mean() * 100
check('in a shaft, closing the debug menu restores the screen', diff == 0, f'{diff:.2f}% pixels differ')


# A restart at checkpoint 5 (the room past the lava hall's wall, on its floor at y -33):
# the camera follows him there, as the arcade's does (the hall's lower view is for
# the fire's room only).
from routes import resume
r5 = peek(god, resume(god, 5) + 30, warp(5), {'p_y': 2, 'scroll_y': 2})[-1]
feet = s16(r5['p_y']) + 24 - s16(r5['scroll_y'])
check('restarted at checkpoint 5, Rastan stands on the screen (on the room\'s floor at its bottom, as in the arcade)',
      150 <= feet <= 216,
      f'feet at {feet}')


# The top corridor's hanging column (marker $47): once seen it cycles every 540 frames
# (down to 112 below its top, up to 34); it shuts the corridor while down: Rastan,
# walking right on route A, is held 21 px left of its middle (8475) until it rises.
rc = peek(god, base + 2020 + A_LATE, ka, {'col_act': 1, 'col_len': 1, 'p_x': 2, 'p_y': 2})
act = next((i for i, f in enumerate(rc) if f['col_act'][0]), None)
lens = [f['col_len'][0] for f in rc[act:]] if act else []
downs = [i for i in range(1, len(lens)) if lens[i] > 34 and lens[i - 1] == 34]
check('the hanging column comes down and goes up again every 540 frames', act is not None and max(lens) == 112
      and len(downs) >= 2 and all(abs(b - a - 540) <= 1 for a, b in zip(downs, downs[1:])), f'downs at {downs[:3]}')   # (samples: +/-1)
held = [i for i, f in enumerate(rc) if w16(f['p_x']) == 8475 and s16(f['p_y']) == 135]
past = next((i for i in range(len(rc)) if w16(rc[i]['p_x']) > 8517 and s16(rc[i]['p_y']) == 135), None)
check('down, it holds Rastan back (8475); risen, he walks through', len(held) > 200 and past is not None
      and past > held[-1] and rc[held[-1]]['col_len'][0] <= 70, f'held {len(held)} frames, through at {past}')

# The lava hall's sealing wall (marker $4D): 257 frames after Rastan comes into the
# hall it slides out of the shaft's wall, 2 px every 7 frames; left standing on the
# ledge before the fire, he is pushed off into it at its 29th step (the arcade's).
J = ROUTE_A.index(2990 - 221 + A_LATE)                  # (route A up to the lava hall's ledge)
kw, bw = route_keys(god, 4, ROUTE_A[:J - 2] + [3263 - 540 + A_LATE, '04'])
rw = peek(god, bw + 3360 + A_LATE, kw, {'p_x': 2, 'p_y': 2, 'p_state': 1, 'wl_act': 1, 'wl_step': 1})
seen = next((i for i, f in enumerate(rw) if f['wl_act'][0]), None)
out = next((i for i, f in enumerate(rw) if f['wl_step'][0]), None)
fell = next((i for i, f in enumerate(rw) if out and i > out and f['p_state'][0] == ST_DEAD), None)
check('the sealing wall comes out 257 frames after he comes into the hall', seen and out and abs(out - seen - 257) <= 1,
      f'in at {seen}, out at {out}')
check('and pushes him off the ledge into the fire', fell is not None and 27 <= rw[fell]['wl_step'][0] <= 31
      and w16(rw[fell]['p_x']) >= 8768, f"dead at {fell}, step {rw[fell]['wl_step'][0] if fell else None}")

# Shaft 2's spiked weights (marker $45, sim/scripts/weights.txt): they appear when the
# camera comes up to y -744 (the arcade's view at -752), wait 8, 40 and 72 frames, then
# cycle every 147 (down to 31). Route B, cut where it walks the corridor: standing under
# the middle one (x 10016) he dies as it reaches length 23 (the arcade: 2868); crouched
# he lives through its whole cycle.
_i = next(j for j in range(0, len(ROUTE_B), 3) if ROUTE_B[j] == 2066 and ROUTE_B[j + 2] == '04')
_pre = ROUTE_B[:_i]
WT = {'p_x': 2, 'p_y': 2, 'p_state': 1, 'scroll_y': 2, 'wt_act': 1, 'wt_len': 3}
ks, bs = route_keys(god, 5, _pre + [2066, 2193, '04'])
rs = peek(god, bs + 2700, ks, WT)
act = next((i for i, f in enumerate(rs) if f['wt_act'][0]), None)
check('the weights appear as the camera comes up to y -744', act is not None
      and s16(rs[act]['scroll_y']) <= -744 < s16(rs[act - 2]['scroll_y']),
      f"at {act - bs if act else None}, scroll_y {s16(rs[act]['scroll_y']) if act else None}")
starts = [[i for i in range(act or 0, len(rs)) if rs[i]['wt_len'][k] == 1 and rs[i - 1]['wt_len'][k] == 0]
          for k in range(3)]
check('they come down 8, 40, 72 frames later, then every 147 frames', act is not None
      and all(abs(starts[k][0] - act - (9 + 32 * k)) <= 2 for k in range(3))
      and all(abs(b - a - 147) <= 1 for a, b in zip(starts[0], starts[0][1:]))
      and max(f['wt_len'][0] for f in rs) == 31, f'starts {[s[:2] for s in starts]}')
dead = next((i for i, f in enumerate(rs) if i > bs + 2100 and f['p_state'][0] == ST_DEAD), None)
check('standing under the middle one, he dies as it reaches 23', dead is not None
      and w16(rs[dead]['p_x']) == 10016 and rs[dead]['wt_len'][1] in (22, 23, 24),
      f"at {dead - bs if dead else None}, length {rs[dead]['wt_len'][1] if dead else None}")
kc, bc = route_keys(god, 5, _pre + [2066, 2193, '04', 2194, 2700, '02'])
rc = peek(god, bc + 2700, kc, WT)
check('crouched under it, he lives through its cycle', all(f['p_state'][0] != ST_DEAD for f in rc[bc + 2100:])
      and max(f['wt_len'][1] for f in rc[bc + 2194:]) == 31)

# The soldiers swing high or low at random (the arcade: bit 2 of the slot's byte $21);
# the high swing's box (13 to 19 px above the anchor) passes over a crouching Rastan, the
# low one's (3 above to 3 below) does not. Crouched in the first room (normal build),
# he is hit only by low swings; standing, by both.
inc = open(os.path.join(os.path.dirname(os.path.abspath(god)), 'objects', 'objects.inc')).read()
pose = lambda n: int(inc.split(n)[1].split('=')[1].split()[0])
LOW = {pose('POSE_SWORD_LOW'), pose('POSE_MACE_LOW')}
HIGH = {pose('POSE_SWORD_OUT'), pose('POSE_MACE_OUT')}
def soldier_hits(extra):
    r = peek(rom, 3000, warp(4) + extra, {'p_hp': 1, 'e_pose': 4, 'e_kind': 4})
    drops = [i for i in range(201, len(r)) if r[i]['p_hp'][0] < r[i - 1]['p_hp'][0]]
    by = lambda i, poses: any(r[j]['e_pose'][k] in poses and r[j]['e_kind'][k] in (11, 12)
                              for j in range(i - 3, i + 1) for k in range(4))
    return drops, [i for i in drops if by(i, LOW)], [i for i in drops if by(i, HIGH)]
d, lo, hi = soldier_hits([200, 3000, '02'])
check('crouched, he is hit by the soldiers\' low swings only', d and len(lo) == len(d) and not hi,
      f'{len(d)} hits, {len(lo)} low, {len(hi)} high')
d, lo, hi = soldier_hits([])
check('standing, by both', lo and hi, f'{len(d)} hits, {len(lo)} low, {len(hi)} high')

# The arcade's sprite colour bank: 48 through round 1 (gold and blue soldiers), 64
# after a restart at checkpoint 4 or 5 (green): the object palettes the VCE holds.
def sprite_pals(keys, frame):
    out = os.path.join(tmp, f'castle_vce_{os.getpid()}.bin')
    subprocess.run([TGRUN, god, str(frame), '/dev/null'] + [str(k) for k in keys],
                   env=dict(os.environ, TGRUN_VCE=out), check=True, capture_output=True)
    return np.frombuffer(open(out, 'rb').read(), '<u2')[256:512]


objdir = os.path.join(os.path.dirname(os.path.abspath(god)), 'objects')
slots = [int(v) for v in open(os.path.join(objdir, 'objects.inc')).read().split('obj_pal_slots:')[1]
         .split('\n')[0].replace('db', '').split(',')]
want48 = np.frombuffer(open(os.path.join(objdir, 'objpal.bin'), 'rb').read(), '<u2')
want64 = np.frombuffer(open(os.path.join(objdir, 'objpal_b64.bin'), 'rb').read(), '<u2')
held = lambda v: np.concatenate([v[ps * 16:ps * 16 + 16] for ps in slots])
v3 = held(sprite_pals(warp(3), 300))
v4 = held(sprite_pals(warp(4), 300))
check('colour bank 48 after a restart before the castle (gold and blue soldiers)', (v3 == want48).all())
check('colour bank 64 after a restart at checkpoint 4 (green soldiers)', (v4 == want64).all()
      and (want64 != want48).any())

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
