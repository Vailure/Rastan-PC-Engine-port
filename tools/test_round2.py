"""test_round2.py rastan_r2.pce : round 2's build, headless (the snakes so far).

Arcade values (sim/scripts/snake.txt; README, round 2):
- Lizardmen and snakes take turns from the round's start.
- A snake level with Rastan and 57 px or nearer turns to him and strikes three
  times, 18 frames each (the arcade's 771-823 in snake.txt: 52 frames).
- Then it crawls on, turns away at 48-51 px and flees at twice its 7/8 px a
  frame until 104 px away.
- Its strike (box $5F: x 16 .. 32, y -20 .. -12) drains 8 units (type 2).
- A crouching Rastan's swing kills it, for 200 points.
"""
import sys
from peek import peek

rom = sys.argv[1]
fails = []


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


EK_LIZARD, EK_SNAKE = 0, 18
ES_WALK, ES_ATTACK, ES_DYING = 1, 2, 4
OBJ = {'e_state': 17, 'e_kind': 17, 'e_xl': 17, 'e_xh': 17, 'e_alt': 17, 'e_face': 17}


def run(frames, keys):
    a = peek(rom, frames, keys, {'p_x': 2, 'score': 3})
    b = peek(rom, frames, keys, OBJ)
    return [dict(**x, **y) for x, y in zip(a, b)]


def x_of(f, k):
    return f['e_xl'][k] | f['e_xh'][k] << 8


def bcd(v):
    return sum(((b >> 4) * 10 + (b & 15)) * 100 ** n for n, b in enumerate(v))


def p_x(f):
    return f['p_x'][0] | f['p_x'][1] << 8


# Rastan stands still at the round's start.
r = run(700, [])
kinds = []
for i in range(1, len(r)):
    for k in range(4):
        if r[i]['e_state'][k] and not r[i - 1]['e_state'][k]:
            kinds.append(r[i]['e_kind'][k])
check('the first walkers are lizardmen and snakes in turn', kinds[:4] == [EK_LIZARD, EK_SNAKE] * 2, f'kinds {kinds[:6]}')

strikes, flee = [], []
for k in range(4):
    for i in range(1, len(r)):
        f, g = r[i], r[i - 1]
        if f['e_kind'][k] != EK_SNAKE or not f['e_state'][k]:
            continue
        if f['e_state'][k] == ES_ATTACK and g['e_state'][k] != ES_ATTACK:
            end = next(j for j in range(i, len(r)) if r[j]['e_state'][k] != ES_ATTACK)
            strikes.append((abs(x_of(f, k) - p_x(f)), end - i, f['e_face'][k] == (p_x(f) > x_of(f, k))))
        if f['e_alt'][k] & 1 and not g['e_alt'][k] & 1:          # turned to flee
            d0 = abs(x_of(g, k) - p_x(g))
            j = next(j for j in range(i, len(r)) if not r[j]['e_alt'][k] & 1)
            flee.append((d0, (x_of(r[j], k) - x_of(f, k)) / (j - i), abs(x_of(r[j], k) - p_x(r[j]))))
check('snakes strike at 57 px, facing Rastan', strikes and all(52 <= d <= 57 and face for d, n, face in strikes), f'{strikes}')
check('a strike is three of 18 frames', strikes and all(50 <= n <= 56 for d, n, face in strikes), f'{strikes}')
check('then it turns away at 48-51 px', flee and all(48 <= d0 <= 51 for d0, v, d1 in flee), f'{flee}')
check('and flees at 7/4 px a frame to 104 px', flee and all(1.6 <= v <= 1.9 and 104 <= d1 <= 108 for d0, v, d1 in flee), f'{flee}')

# Walking into a strike (from its first frame, 16 frames right): its reach drains 8 units.
F = next(i for i in range(1, len(r)) for k in range(4)
         if r[i]['e_kind'][k] == EK_SNAKE and r[i]['e_state'][k] == ES_ATTACK and r[i - 1]['e_state'][k] != ES_ATTACK)
h = peek(rom, F + 70, [F + 1, F + 16, '04'], {'p_hp': 1})
drops = [h[i - 1]['p_hp'][0] - h[i]['p_hp'][0] for i in range(F, F + 70) if h[i]['p_hp'][0] != h[i - 1]['p_hp'][0]]
check('walking into a strike costs 8 units', drops == [8], f'health steps {drops}')

# Crouched, swinging (DOWN, II every 20 frames): snakes die to it, for 200.
keys = [250, 1000, '02'] + sum([[f, f + 3, '82'] for f in range(250, 1000, 20)], [])
r = run(1000, keys)
kills = []
for i in range(1, len(r)):
    for k in range(17):
        if r[i]['e_state'][k] == ES_DYING and r[i - 1]['e_state'][k] != ES_DYING and r[i]['e_kind'][k] == EK_SNAKE:
            kills.append(bcd(r[i]['score']) - bcd(r[i - 1]['score']))
check('a crouching swing kills snakes, 200 each', len(kills) >= 2 and all(v == 2 for v in kills), f'score steps {kills}')

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
