"""Scroll the ROM through the stage in the headless emulator and compare
screenshots with the converter's preview at the scroll position read from RAM.

usage: test_scroll.py rom preview.png outdir frame1 frame2 ...
Pad: RIGHT + I (4 px/frame) from frame 61. Writes a side-by-side strip.
"""
import os
import subprocess
import sys
import numpy as np
from PIL import Image

TGRUN = os.path.join(os.path.dirname(__file__), 'tgrun', 'tgrun')
SCROLL_ZP = 0x04      # scroll_x, scroll_y (see src/main.lst)
PAD = os.environ.get('PAD', '44')   # tgemu bits: UP 01 DOWN 02 RIGHT 04 LEFT 08 I 40 II 80

rom, preview, out = sys.argv[1], sys.argv[2], sys.argv[3]
frames = [int(f) for f in sys.argv[4:]]
q3 = lambda a: np.rint(a.astype(int) * 7 / 255).astype(int)   # compare in PCE 3-bit color
prev = q3(np.array(Image.open(preview)))
os.makedirs(out, exist_ok=True)
rows, worst = [], 0
for f in frames:
    ppm = f'{out}/f{f}.ppm'
    r = subprocess.run([TGRUN, rom, str(f), ppm, '61', str(f), PAD], capture_output=True, text=True,
                       env=dict(os.environ, TGRUN_PEEK=f'{SCROLL_ZP:x},4'), check=True)
    lines = r.stdout.strip().splitlines()
    shot = np.array(Image.open(ppm))[:224, 32:288].astype(int) >> 5   # tgemu keeps 3-bit color in the top bits
    best = None
    for ln in lines[-3:]:          # the displayed position lags the variable by up to a frame
        b = [int(v, 16) for v in ln.split(':')[1].split()]
        x, y = b[0] | b[1] << 8, b[2] | b[3] << 8
        ref = prev[y:y + 224, x:x + 256]
        if ref.shape != shot.shape:
            continue
        err = (ref != shot).any(-1).mean() * 100     # % of pixels that differ
        if best is None or err < best[0]:
            best = (err, x, y, ref)
    err, x, y, ref = best
    worst = max(worst, err)
    print(f'frame {f}: scroll ({x},{y}) {err:.2f}% pixels differ')
    diff = np.where((shot != ref).any(-1, keepdims=True), [255, 0, 0], [0, 0, 0])
    rows.append(np.concatenate([shot * 255 // 7, ref * 255 // 7, diff], 1))
Image.fromarray(np.concatenate(rows, 0).astype(np.uint8)).save(f'{out}/compare.png')
print('worst', round(worst, 2))
sys.exit(0 if worst == 0 else 1)
