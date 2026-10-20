"""contact.py snapfile out.png frame1 frame2 ... : render frames side by side (5 per row)."""
import os
import sys
import numpy as np
from PIL import Image
from snap import read_snaps, Renderer
from arcade_gfx import load_region
ROM = os.environ.get('RASTAN_ROMS', 'roms/rastan')
snapf, out = sys.argv[1], sys.argv[2]
want = [int(x) for x in sys.argv[3:]]
R = Renderer(load_region(ROM, 'pc080sn'), load_region(ROM, 'pc090oj'))
imgs = []
for s in read_snaps(snapf):
    if s.frame in want:
        imgs.append(R.render(s))
        print(s.frame, 'scrx', s.scrx, 'scry', s.scry, 'mode', hex(s.w(0x10c000)), hex(s.w(0x10c002)))
while len(imgs) % 5: imgs.append(np.zeros_like(imgs[0]))
rows = [np.concatenate(imgs[i:i + 5], 1) for i in range(0, len(imgs), 5)]
Image.fromarray(np.concatenate(rows, 0)).save(out)
