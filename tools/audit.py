"""audit.py rom outdir : play each part of round 1 headless and keep what it looks like.

For each checkpoint (debug-menu warps) Rastan plays on: through the castle on the
test routes (tools/routes.py), elsewhere running right holding UP (he climbs the
ropes he meets), jumping and swinging now and then. Frames go to contact sheets
(outdir/cpN.png, two a second) for reading through by eye, and every frame is
checked for:
  - an object showing a pose its kind does not have (a pose read from the wrong bank),
  - frames where the game logic did not run once (slowdown), outside death restarts
    and doors,
  - pieces left undrawn because the SATB was full (en_full),
and it reports (without counting it as a problem) frames where the VDC's 16 sprite
cells a line would drop a visible sprite: where walkers crowd, enemies_draw turns
their order so that they flicker rather than one losing its cells for good.
Use an invincible build (god.pce) so that each part is seen to its end.

With AUDIT_PREVIEW=build/stage1/preview.png and the bgcheck build (god mode, the tile
map alone), each kept frame is also compared with the converter's preview at the scroll
position the game had: any pixel that differs is a tile streamed wrong or not yet.
"""
import os
import re
import subprocess
import sys
import tempfile
import numpy as np
from PIL import Image, ImageDraw
from peek import peek
from trace_player import TGRUN
from routes import ROUTE_A, ROUTE_B

HERE = os.path.dirname(os.path.abspath(__file__))
rom, out = sys.argv[1:3]
EVERY = int(os.environ.get('AUDIT_EVERY', 30))
CPS = [int(c) for c in os.environ.get('AUDIT_CPS', '0,1,2,3,4,5').split(',')]
OPEN, RIGHT, I = '11', '04', '40'
ST_DEAD = 8
os.makedirs(out, exist_ok=True)
PREVIEW = os.environ.get('AUDIT_PREVIEW')
if PREVIEW:
    Y0 = next(int(ln.split('=')[1].split(';')[0]) for ln in open(os.path.join(os.path.dirname(PREVIEW), 'stage.inc'))
              if ln.startswith('PREVIEW_Y0'))
    q3 = lambda a: np.rint(a.astype(int) * 7 / 255).astype(int)
    PREV = q3(np.array(Image.open(PREVIEW)))


def pose_counts():
    """Poses each object kind has: the length of its group's pose table."""
    data = open(os.path.join(HERE, '..', 'build', 'objects', 'objects_data.inc')).read()
    counts = {}
    for m in re.finditer(r'^(grp_\w+)_ptab:\n((?:\t\tdw\t.*\n)+)', data, re.M):
        counts[m.group(1)] = len(m.group(2).splitlines())
    src = open(os.path.join(HERE, '..', 'src', 'enemies.asm')).read()
    m = re.search(r'^kind_ptab_l:(.*?)\n(?=\S)', src, re.M | re.S)
    groups = re.findall(r'<(grp_\w+)_ptab', m.group(1))
    return [counts[g] for g in groups]


def warp(cp):
    if cp == 0:
        return []
    return ([40, 90, OPEN] + sum([[100 + 6 * k, 100 + 6 * k, RIGHT] for k in range(cp)], [])
            + [150, 150, I])


def route(cp):
    if cp == 4:
        return warp(cp) + ROUTE_A, 3600
    if cp == 5:
        return warp(cp) + ROUTE_B, 3800
    n = 2400
    keys = warp(cp) + [200, n, '05']                                    # UP + RIGHT held
    keys += sum([[f, f + 2, '41'] for f in range(260, n, 60)], [])      # high jumps
    keys += sum([[f, f + 1, '80'] for f in range(230, n, 150)], [])     # swings
    return keys, n


POSES = pose_counts()
VARS = {'p_x': 2, 'p_y': 2, 'p_state': 1, 'scroll_x': 2, 'scroll_y': 2, 'loop_cnt': 2, 'lives': 1, 'en_full': 1,
        'e_state': 17, 'e_kind': 17, 'e_pose': 17, 'e_shown': 17}
w = lambda v: v[0] | v[1] << 8
s16 = lambda v: (w(v) ^ 0x8000) - 0x8000
problems = 0


def overflow(satb):
    """Frames where the hardware would drop a visible sprite: the VDC fetches at most 16
    16-px-wide sprite units on a line (a 32-px sprite takes two), in SATB order, and
    every sprite whose rows cover the line takes its share, on screen or not.
    Returns [(frame, first such line, units wanted there)]."""
    out = []
    for f, t in enumerate(satb):
        y = (t[:, 0] & 0x3FF).astype(int) - 64
        x = (t[:, 1] & 0x3FF).astype(int) - 32
        attr = t[:, 3].astype(int)
        cgy = (attr >> 12) & 3
        h = np.where(cgy == 0, 16, np.where(cgy == 1, 32, 64))
        wide = (attr >> 8) & 1
        units = 1 + wide
        width = 16 << wide
        for line in range(224):
            on = (y <= line) & (line < y + h)
            if units[on].sum() <= 16:
                continue
            used, lost = 0, False
            for i in np.nonzero(on)[0]:
                used += units[i]
                if used > 16 and x[i] + width[i] > 0 and x[i] < 256:
                    lost = True
                    break
            if lost:
                out.append((f, line, int(units[on].sum())))
                break
    return out


def exact_near(shot, x0, y0, reach=40):
    """A position within reach px of (x0, y0) whose preview is exactly the screen: then
    what shows is right, only read at a moment the variables did not catch."""
    small = shot[::8, ::8]
    for dy in range(-reach, reach + 1):
        y = y0 + dy
        if y - Y0 < 0 or y - Y0 + 224 > PREV.shape[0]:
            continue
        for dx in range(-reach, reach + 1):
            x = x0 + dx
            if x < 0 or x + 256 > PREV.shape[1]:
                continue
            if (PREV[y - Y0:y - Y0 + 224:8, x:x + 256:8] != small).any():
                continue
            if not (PREV[y - Y0:y - Y0 + 224, x:x + 256] != shot).any():
                return x, y
    return None


for cp in CPS:
    keys, frames = route(cp)
    with tempfile.TemporaryDirectory() as d:
        subprocess.run([TGRUN, rom, str(frames), os.path.join(d, 'last.ppm')] + [str(k) for k in keys],
                       env=dict(os.environ, TGRUN_DUMP=f'{d},{EVERY}', TGRUN_SATB=os.path.join(d, 'satb')),
                       check=True, capture_output=True)
        satb = np.fromfile(os.path.join(d, 'satb'), '<u2').reshape(-1, 64, 4)
        names = sorted(f for f in os.listdir(d) if f[0].isdigit())
        tiles = [(int(f[:5]), Image.open(os.path.join(d, f)).crop((32, 0, 288, 224)).resize((128, 112)))
                 for f in names]
        shots = {int(f[:5]): np.array(Image.open(os.path.join(d, f)))[:224, 32:288].astype(int) >> 5
                 for f in names} if PREVIEW else {}
    cols = 10
    sheet = Image.new('RGB', (cols * 130, (len(tiles) + cols - 1) // cols * 124), (40, 40, 40))
    dr = ImageDraw.Draw(sheet)
    for i, (fr, im) in enumerate(tiles):
        x, y = (i % cols) * 130, (i // cols) * 124
        sheet.paste(im, (x + 1, y + 11))
        dr.text((x + 2, y), str(fr), fill=(255, 255, 0))
    sheet.save(os.path.join(out, f'cp{cp}.png'))

    r = peek(rom, frames, keys, VARS)
    bad = []
    with open(os.path.join(out, f'cp{cp}.txt'), 'w') as f:
        for i, x in enumerate(r):
            objs = [(k, x['e_kind'][k], x['e_pose'][k], x['e_shown'][k]) for k in range(17) if x['e_state'][k]]
            for k, kind, pose, shown in objs:
                if kind >= len(POSES) or pose >= POSES[kind] or (shown != 255 and shown >= POSES[kind]):
                    bad.append((i, k, kind, pose, shown))
            f.write(f"{i} x {w(x['p_x'])} y {s16(x['p_y'])} st {x['p_state'][0]} sx {w(x['scroll_x'])} "
                    f"sy {s16(x['scroll_y'])} lives {x['lives'][0]} objs {objs}\n")
    wrong = []
    for f, shot in sorted(shots.items()):
        if f < (200 if cp else 20) or (shot == shot[0, 0]).all():
            continue                      # (the warp's menu; a blank screen: a restart)
        best = None
        xs_, ys_ = set(), set()               # the displayed position lags the variables, and
        for g in range(f - 3, f + 4):         # RAM is read at one point of the frame: any
            if 0 <= g < len(r):               # pairing of x and y seen around then
                xs_.add(w(r[g]['scroll_x']))
                ys_.add(s16(r[g]['scroll_y']))
        cands = {(x, y) for x in xs_ for y in ys_}
        for x, y in cands:
            ref = PREV[y - Y0:y - Y0 + 224, x:x + 256] if y >= Y0 else np.zeros(0)
            if ref.shape != shot.shape:
                continue
            err = (ref != shot).any(-1).mean() * 100
            if best is None or err < best[0]:
                best = (err, x, y, ref)
        if best is None and cands:            # (the variables read past the map's edge)
            x, y = sorted(cands)[len(cands) // 2]
            y = min(max(y, Y0), Y0 + PREV.shape[0] - 224)
            x = min(max(x, 0), PREV.shape[1] - 256)
            best = (100.0, x, y, None)
        if best is not None and best[0] > 0:
            near = exact_near(shot, best[1], best[2])
            if near is not None:
                best = (0.0,) + near + (None,)
        if best is None or best[0] > 0:
            wrong.append((f, round(best[0], 2) if best else None, best[1:3] if best else None))
            if best and best[3] is not None and len(wrong) <= 6:
                diff = np.where((shot != best[3]).any(-1, keepdims=True), [255, 0, 0], [0, 0, 0])
                Image.fromarray(np.concatenate([shot * 255 // 7, best[3] * 255 // 7, diff], 1).astype(np.uint8)
                                ).save(os.path.join(out, f'cp{cp}_wrong_{f}.png'))
    problems += len(wrong)
    over = overflow(satb)                 # (reported, not counted: crowds flicker on the PCE)
    lc = [w(x['loop_cnt']) for x in r]
    dead = [i for i, x in enumerate(r) if x['p_state'][0] == ST_DEAD]
    dying = {j for i in dead for j in range(i, min(i + 60, len(r)))}   # (a restart streams the map)
    px, py = [w(x['p_x']) for x in r], [s16(x['p_y']) for x in r]
    cuts = {j for i in range(1, len(r)) if abs(px[i] - px[i - 1]) > 32 or abs(py[i] - py[i - 1]) > 64
            for j in range(i - 8, i + 8)}        # (a door: the screen is cut to the next room)
    slow = [i for i in range(250, len(lc)) if (lc[i] - lc[i - 1]) & 0xffff != 1 and i not in dying | cuts]
    deaths = sum(1 for i in range(1, len(r)) if r[i]['lives'][0] < r[i - 1]['lives'][0])
    full = sum(1 for i in range(1, len(r)) if r[i]['en_full'][0] != r[i - 1]['en_full'][0])
    problems += full
    xs = [w(x['p_x']) for x in r]
    problems += len(bad) + len(slow)
    print(f'cp{cp}: x {xs[200]} -> {xs[-1]} (max {max(xs)}), deaths {deaths}, '
          f'slow frames {len(slow)}{" at " + str(slow[:5]) if slow else ""}, '
          f'SATB full {full}, '
          f'bad poses {len(bad)}{" e.g. (frame, slot, kind, pose, shown) " + str(bad[:3]) if bad else ""}'
          + (f', tile map wrong in {len(wrong)} of {len(shots)} frames {wrong[:4]}' if PREVIEW else '')
          + f', sprites lost to the 16-a-line limit in {len(over)} frames'
          + (f' (frame, line, units) {over[:4]}' if over else ''))
print(f'{problems} problem(s)')
sys.exit(1 if problems else 0)
