"""test_monsters.py rastan.pce god.pce : round 1's later enemies, headless.

Arcade values (round 1 census, sim/scripts/chimera.txt; see README):
- From x 2400 throwers, chimeras and lizardmen come in turn.
- A chimera walks left at 1/2 px/frame, stops once to breathe two fireballs
  (24 px ahead of it, 33 and 81 frames into the breath), then walks on.
- Fireballs fly left at 1.75 px/frame. A chimera is worth 300.
- Boulders appear when Rastan is 169 px left of their spot; the one at 4601
  lands on the ledge at y 311, rolls left at 7/6 px/frame and drops to y 343.
- The gargoyle at 4608 flies the arcade's fixed path: at (4512, 289) 126 frames
  after appearing, (4418, 334) at 199, (4495, 316) at 249, (4572, 295) at 349.
- The woman warrior appears at (4523, 304) when Rastan reaches 4355, runs left
  hopping down 32 px steps, and turns about 50 px past him.
- In the castle (x 8200 on) sword and mace soldiers come in turn, stop about
  60 px away and swing; a swing that reaches costs 12 units.
- Fire jets at 9870, 9966, 10062 (lava hall, arcade census 10382-10574) erupt when Rastan is 172 px left of them.
- The boss drops in when Rastan enters the last room and lands at y 446; ten
  hits kill it for 5000, and the round is clear (round 1 again, score kept).
"""
import sys
from peek import peek

rom, god = sys.argv[1:3]
fails = []


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


EK_LIZARD, EK_BLUE, EK_CHIM, EK_FIRE, EK_ROCK, EK_GARG, EK_WOMAN, EK_SWORD, EK_MACE, EK_JET, EK_BOSS = 0, 1, 5, 6, 7, 8, 10, 11, 12, 13, 14
ES_WALK, ES_ATTACK, ES_DYING = 1, 2, 4
OBJ = {'e_state': 17, 'e_kind': 17, 'e_xl': 17, 'e_xh': 17, 'e_yl': 17, 'e_yh': 17, 'e_alt': 17}
SEL, I, RIGHT = '10', '40', '04'
OPEN = '11'                   # UP + SELECT opens the debug menu


def run(r, frames, keys):
    a = peek(r, frames, keys, {'p_x': 2, 'score': 3})
    b = peek(r, frames, keys, OBJ)
    return [dict(**x, **y) for x, y in zip(a, b)]


def w16(v):
    return v[0] | v[1] << 8


def x_of(f, k):
    return f['e_xl'][k] | f['e_xh'][k] << 8


def lives(r, kind):
    """Each object of a kind: [(frame, x, state)] over its life."""
    out, cur = [], {}
    for i, f in enumerate(r):
        for k in range(17):
            if f['e_state'][k] and f['e_kind'][k] == kind:
                cur.setdefault(k, []).append((i, x_of(f, k), f['e_state'][k]))
            elif k in cur:
                out.append(cur.pop(k))
    return out + list(cur.values())


# Warp to checkpoint 1, then the jumping route right (god build).
keys = [100, 100, OPEN, 110, 110, RIGHT, 150, 150, I, 200, 1400, '05']
for f in range(220, 1400, 60):
    keys += [f, f + 3, I]
r = run(god, 1400, keys)
spawns = []
for i in range(1, len(r)):
    for k in range(4):
        if r[i]['e_state'][k] and not r[i - 1]['e_state'][k]:
            spawns.append((x_of(r[i], k), r[i]['e_kind'][k]))
late = [kd for x, kd in spawns if x >= 2400]
check('from x 2400 throwers, chimeras and lizardmen come in turn',
      EK_CHIM in late and all(late[i] != late[i + 1] for i in range(len(late) - 1)), f'kinds {late}')
chims = lives(r, EK_CHIM)
c = max(chims, key=len)
walk = [x for _, x, s in c if s == ES_WALK]
steps = [a - b for a, b in zip(walk, walk[1:])]
check('a chimera walks left at 1/2 px/frame', walk and set(steps) <= {0, 1} and abs(sum(steps) / len(steps) - 0.5) < 0.05,
      f'{sum(steps)} px in {len(steps)} frames')
breath = [i for i, _, s in c if s == ES_ATTACK]
check('it stops once to breathe fire, then walks on', breath and breath[-1] - breath[0] + 1 == len(breath)
      and c[-1][2] == ES_WALK, f'breath frames {breath[0] if breath else None}-{breath[-1] if breath else None}')
fires = [f for f in lives(r, EK_FIRE) if breath and breath[0] <= f[0][0] <= breath[-1] + 1]
starts = [f[0][0] - breath[0] for f in fires]
# (RAM is sampled at a fixed point of each emulated frame; a step can show a frame late.)
check('two fireballs, 33 and 81 frames into the breath', len(starts) == 2
      and abs(starts[0] - 33) <= 1 and abs(starts[1] - 81) <= 1, f'{starts}')
x0 = [x for i, x, _ in c if i == fires[0][0][0]] if fires else []
check('from 24 px ahead of its anchor', fires and x0 and x0[0] - fires[0][0][1] == 24,
      f'chimera {x0}, fireball {fires[0][0][1] if fires else None}')
fl = max(fires, key=len) if fires else []
v = (fl[0][1] - fl[-1][1]) / (len(fl) - 1) if len(fl) > 20 else 0
check('fireballs fly left at 1.75 px/frame', abs(v - 1.75) < 0.1, f'{v:.2f}')

# A chimera dies in one hit for 300 (the same route, with a down thrust in each jump).
keys = [100, 100, OPEN, 110, 110, RIGHT, 150, 150, I, 200, 1400, '05']
for f in range(220, 1400, 60):
    keys += [f, f + 3, I, f + 8, f + 10, '82']
r = run(god, 1400, keys)
kills = [(i, k) for i in range(1, len(r)) for k in range(4) if r[i]['e_kind'][k] == EK_CHIM
         and r[i]['e_state'][k] == ES_DYING and r[i - 1]['e_state'][k] != ES_DYING]


def bcd(v):
    return int(''.join(f'{b:02x}' for b in reversed(v))) * 100


gain = [bcd(r[i]['score']) - bcd(r[i - 1]['score']) for i, _ in kills]
check('a sword hit kills a chimera, worth 300', kills and 300 in gain, f'{len(kills)} killed, score steps {gain}')

# Boulder at 4601 (checkpoint 2, the same jumping route).
keys = [100, 100, OPEN, 110, 110, RIGHT, 116, 116, RIGHT, 150, 150, I, 200, 1100, "05"]
for f in range(220, 1100, 60):
    keys += [f, f + 3, I]
r = run(god, 1100, keys)
rk = [(i, x_of(f, k), f['e_yl'][k] | f['e_yh'][k] << 8, w16(f['p_x'])) for i, f in enumerate(r) for k in (6, 7, 8)
      if f['e_state'][k] and f['e_kind'][k] == EK_ROCK]
check('a boulder appears when Rastan is 169 px left of 4601', rk and rk[0][1] == 4601 and abs(rk[0][3] - (4601 - 169)) <= 3,
      f'at x {rk[0][1] if rk else None}, Rastan {rk[0][3] if rk else None}')
ys = sorted({y for _, _, y, _ in rk})
check('it lands at y 311, rolls, then drops to y 343', 311 in ys and 343 in ys, f'rests {[y for y in ys if y in (311, 343)]}')
roll = [(i, x) for i, x, y, _ in rk if y == 311]
v = (roll[0][1] - roll[-1][1]) / (roll[-1][0] - roll[0][0]) if len(roll) > 30 else 0
check('rolling left at 7/6 px/frame', abs(v - 7 / 6) < 0.05, f'{v:.3f}')

# The gargoyle (same run).
g = [(i, x_of(f, k), f['e_yl'][k] | f['e_yh'][k] << 8) for i, f in enumerate(r) for k in (6, 7, 8)
     if f['e_state'][k] and f['e_kind'][k] == EK_GARG]
ARC = {126: (4512, 289), 199: (4418, 334), 249: (4495, 316), 349: (4572, 295)}
got = {d: next(((x, y) for i, x, y in g if i - g[0][0] == d), None) for d in ARC} if g else {}
check("the gargoyle flies the arcade's path", g and all(got[d] and abs(got[d][0] - ARC[d][0]) <= 1
      and abs(got[d][1] - ARC[d][1]) <= 1 for d in ARC), f'{got}')

# The woman warrior (same run).
w = [(i, x_of(f, k), f['e_yl'][k] | f['e_yh'][k] << 8, w16(f['p_x']), f['e_alt'][k]) for i, f in enumerate(r)
     for k in range(4) if f['e_state'][k] and f['e_kind'][k] == EK_WOMAN]
check('the woman warrior appears at (4523, 304) when Rastan reaches 4355', w and w[0][1] >= 4521 and w[0][2] in (304, 305)
      and abs(w[0][3] - 4355) <= 3, f'{w[0][1:4] if w else None}')
ys = sorted({y for _, _, y, _, _ in w})
check('she hops down the 32 px steps', 336 in ys and 368 in ys, f'levels {[y for y in ys if y % 32 == 16]}')
turn = next(((x, px) for _, x, _, px, m in w if m == 2), None)
check('she turns about 50 px past him', turn and 45 <= turn[1] - turn[0] <= 60, f'{turn}')

# Castle soldiers: warp to checkpoint 4 and walk right (they hurt; no god mode).
keys = [100, 100, OPEN] + sum([[110 + 6 * k, 110 + 6 * k, RIGHT] for k in range(4)], []) + [150, 150, I, 200, 900, '04']
r = run(rom, 900, keys)
r2 = peek(rom, 900, keys, {'p_hp': 1})
kinds = []
for i in range(200, len(r)):          # (after the warp)
    for k in range(4):
        if r[i]['e_state'][k] and not r[i - 1]['e_state'][k]:
            kinds.append(r[i]['e_kind'][k])
check('in the castle, sword and mace soldiers come in turn', len(kinds) >= 2 and all(a != b and {a, b} == {EK_SWORD, EK_MACE} for a, b in zip(kinds, kinds[1:])),
      f'kinds {kinds}')
att = [(i, k) for i in range(1, len(r)) for k in range(4) if r[i]['e_state'][k] == ES_ATTACK
       and r[i - 1]['e_state'][k] != ES_ATTACK and r[i]['e_kind'][k] in (EK_SWORD, EK_MACE)]
dist = [x_of(r[i], k) - w16(r[i]['p_x']) for i, k in att]
check('they stop about 60 px away to swing', att and all(50 <= abs(d) <= 62 for d in dist), f'{dist}')
drops = [r2[i - 1]['p_hp'][0] - r2[i]['p_hp'][0] for i in range(1, len(r2)) if r2[i]['p_hp'][0] < r2[i - 1]['p_hp'][0]]
check('a swing that reaches costs 12 units', drops and set(drops) == {12}, f'{drops}')

# Fire jets: checkpoint 5 (god build): up the rope and along the top of the lava
# hall, down into the jets' room, jumping its three pits.
CASTLE_ROUTE = [100, 100, OPEN] + sum([[110 + 6 * k, 110 + 6 * k, RIGHT] for k in range(5)], []) + [150, 150, I, 200, 830, '05']
for f in range(220, 830, 60):
    CASTLE_ROUTE += [f, f + 3, I]
CASTLE_ROUTE += [831, 1100, RIGHT, 864, 867, I, 914, 917, I, 964, 967, I]
r = run(god, 1100, CASTLE_ROUTE)
starts = {}
for i in range(1, len(r)):
    for k in (6, 7, 8):
        if r[i]['e_kind'][k] == EK_JET and r[i]['e_state'][k] and not r[i - 1]['e_state'][k]:
            starts.setdefault(x_of(r[i], k), w16(r[i]['p_x']))
check('fire jets erupt when Rastan is 172 px left of them', len(starts) == 3
      and all(abs(px - (jx - 172)) <= 3 for jx, px in starts.items()), f'{starts}')

# The boss: the debug warp to the boss room (7th line), swinging every 25 frames.
keys = [100, 100, OPEN] + sum([[110 + 6 * k, 110 + 6 * k, RIGHT] for k in range(6)], []) + [150, 150, I]
for f in range(300, 1000, 25):
    keys += [f, f + 1, '80']
r = run(god, 1000, keys)
r3 = peek(god, 1000, keys, {'e_range': 17})
bo = [(i, f['e_yl'][6] | f['e_yh'][6] << 8) for i, f in enumerate(r) if f['e_state'][6] and f['e_kind'][6] == EK_BOSS]
check('the boss drops in and lands at y 446', bo and bo[0][1] < 400 and any(y == 446 for _, y in bo), f'from y {bo[0][1] if bo else None}')
dead = next((i for i, f in enumerate(r) if f['e_kind'][6] == EK_BOSS and f['e_state'][6] == ES_DYING), None)
hits = r3[dead]['e_range'][6] if dead else None
check('ten hits kill it, for 5000', dead and hits == 10 and bcd(r[dead]['score']) - bcd(r[dead - 1]['score']) == 5000,
      f'hits {hits}, score {bcd(r[dead]["score"]) if dead else None}')
back = next((i for i in range(dead or 0, len(r)) if w16(r[i]['p_x']) == 48), None) if dead else None
check('then the round is clear: round 1 again, score kept', back and bcd(r[back]['score']) >= 5000,
      f'restart at frame {back}')

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
