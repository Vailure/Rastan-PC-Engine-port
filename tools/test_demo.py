"""test_demo.py rastan.pce stilldir : the demo build's own screens and flow, headless.

The demo ROM (TITLE = 1, DEBUG_MENU = 0) starts on the arcade's title screen and
waits for RUN; RUN pauses a game; losing the last life shows the arcade's GAME OVER
and goes back to the title. The debug menu is a screen of its own, opened from the
title (UP + SELECT held), never in play. (The round-clear screen is
checked on the test builds, which can warp to the boss: tools/test_monsters.py.)
"""
import os
import subprocess
import sys
import numpy as np
from PIL import Image
from peek import peek
from trace_player import TGRUN

rom, stills = sys.argv[1:3]
tmp = os.environ.get('TMPDIR', '/tmp')
fails = []
RUN, OPEN = '20', '11'
ST_DEAD = 8


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


# The card: a Street Fighter II mapper image, 2.5 MB (what emulators go by), with the
# round's stage data only in page 1 (file 1 MB-1.5 MB): if the game never selected it,
# nothing in the tests below would draw right.
size = os.path.getsize(rom)
check('the ROM is a 2.5 MB SF2 mapper image', size == 0x280000, f'{size} bytes')


def shot(frame, keys):
    out = os.path.join(tmp, f'demo_{os.getpid()}.ppm')
    subprocess.run([TGRUN, rom, str(frame), out] + [str(k) for k in keys], check=True, capture_output=True)
    return np.array(Image.open(out))[:224, 32:288].astype(int) >> 5     # 3-bit colour


def still(name):
    """What tools/pce_still.py says the PC Engine shows (the right half of name.png)."""
    im = np.array(Image.open(os.path.join(stills, f'{name}.png')))[:, 256:]
    return np.rint(im.astype(int) * 7 / 255).astype(int)


w16 = lambda v: v[0] | v[1] << 8
VARS = {'st_n': 1, 'lives': 1, 'p_state': 1, 'p_x': 2, 'loop_cnt': 2, 'score': 3}

# 1. The title, as converted ("PUSH RUN BUTTON", its last row, blinks).
t = shot(80, [])
ref = still('title')
diff = (t[:216] != ref[:216]).any(-1).mean() * 100
check('it starts on the arcade title screen', diff == 0, f'{diff:.2f}% pixels differ')
on = [(shot(f, [])[216:] != 0).any() for f in (70, 100)]
check('"PUSH RUN BUTTON" blinks', on[0] != on[1], f'shown at 70 / 100: {on}')

# 2. RUN starts a game; RUN pauses it, RUN again goes on.
r = peek(rom, 600, [120, 121, RUN, 300, 301, RUN, 400, 401, RUN, 150, 600, '04'], VARS)
lc = [w16(x['loop_cnt']) for x in r]
start = next((i for i in range(1, 300) if lc[i] != lc[i - 1]), None)
check('RUN starts a new game at the start of round 1 (3 lives)', start is not None and start > 120
      and w16(r[start + 5]['p_x']) == 48 and r[start]['lives'][0] == 3, f'the game runs from frame {start}')
check('RUN pauses (the game logic stops) and RUN resumes', lc[390] == lc[310] and lc[450] > lc[410],
      f'loop count {lc[310]} {lc[390]} {lc[410]} {lc[450]}')

# 3. There is no debug menu in play: UP + SELECT held does not stop the game.
r = peek(rom, 500, [120, 121, RUN, 250, 400, OPEN], VARS)
lc = [w16(x['loop_cnt']) for x in r]
check('in play there is no debug menu (UP + SELECT held: the game goes on)', lc[450] - lc[250] >= 199,
      f'{lc[450] - lc[250]} logic frames in 200')

# 3b. UP + SELECT held on the title: the debug menu, a screen of its own (no game runs
# under it). SELECT goes back to the title; its lines set the new game: here
# checkpoint 4 (RIGHT x4), invincible (DOWN, RIGHT), 5 lives (DOWN x2, RIGHT x2), the
# axe (DOWN x2, RIGHT); I on START GAME (DOWN) starts it.
r = peek(rom, 200, [60, 110, OPEN, 150, 150, '10'], VARS)
lc = [w16(x['loop_cnt']) for x in r]
m = shot(140, [60, 110, OPEN])
t = shot(80, [])
check('UP + SELECT held on the title opens the debug menu, with no game under it',
      lc[140] == 0 and (m != t).any(-1).mean() > 0.5, f'loop count {lc[140]}')
check('SELECT goes back to the title', (shot(199, [60, 110, OPEN, 150, 150, '10'])[:216] != still('title')[:216])
      .any(-1).mean() * 100 < 1 and lc[199] == 0)
seq = [(130, '04'), (136, '04'), (142, '04'), (148, '04'), (154, '02'), (160, '04'), (166, '02'), (172, '02'),
       (178, '04'), (184, '04'), (190, '02'), (196, '02'), (202, '04'), (208, '02'), (214, '40')]
keys = [60, 110, OPEN] + sum([[f, f, k] for f, k in seq], []) + [400, 460, OPEN]
r = peek(rom, 520, keys, dict(VARS, dbg_god=1, p_weapon=1))
lc = [w16(x['loop_cnt']) for x in r]
go = next((i for i in range(len(r)) if lc[i]), None)
check("its new game starts where and as it says (checkpoint 4, invincible, 5 lives, the axe)",
      go and w16(r[go + 30]['p_x']) == 8240 and r[go + 30]['dbg_god'][0] == 1 and r[go + 30]['lives'][0] == 5
      and r[go + 30]['p_weapon'][0] == 2,
      f"at x {w16(r[go + 30]['p_x']) if go else None}, god {r[go + 30]['dbg_god'][0] if go else None}, "
      f"lives {r[go + 30]['lives'][0] if go else None}, weapon {r[go + 30]['p_weapon'][0] if go else None}")
check('and in that game UP + SELECT held still opens nothing', lc[500] - lc[400] >= 99,
      f'{lc[500] - lc[400]} logic frames in 100')

# 4. Idle until the last life goes: GAME OVER, then the title, then a new game.
r = peek(rom, 3400, [120, 121, RUN, 3100, 3101, RUN], VARS)
last = next((i for i in range(200, len(r)) if r[i]['lives'][0] == 0), None)
over = [i for i in range(last or 0, len(r)) if r[i]['st_n'][0] == 2] if last else []
check('losing the last life shows GAME OVER for about 4 s', 230 <= len(over) <= 260, f'{len(over)} frames')
g = shot(over[len(over) // 2], [120, 121, RUN]) if over else None
ref = still('gameover')
diff = (g[24:] != ref[24:]).any(-1).mean() * 100 if g is not None else 100   # (the HUD's score above it)
check('as the arcade draws it', diff == 0, f'{diff:.2f}% pixels differ')
title = next((i for i in range(over[-1] if over else 0, len(r)) if r[i]['st_n'][0] == 1), None)
again = next((i for i in range(3100, len(r)) if w16(r[i]['p_x']) == 48 and r[i]['lives'][0] == 3), None)
check('then the title, and RUN there starts a new game', title is not None and again is not None
      and w16(r[again]['score'][:2]) == 0 and r[again]['score'][2] == 0, f'title at {title}, new game at {again}')

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
