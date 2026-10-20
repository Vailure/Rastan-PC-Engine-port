"""render_map.py maincpu.bin snapfile palframe out.png [col0 ncols] : render FG world strip."""
import os
import sys
import numpy as np
from PIL import Image
from arcade_gfx import load_region, decode_packed
from snap import read_snaps, palette_rgb
from fgmap import fg_tilemap, NCOLS

ROM = os.environ.get('RASTAN_ROMS', 'roms/rastan')
rom = open(sys.argv[1], 'rb').read()
palframe = int(sys.argv[3])
pal = next(palette_rgb(s.pal) for s in read_snaps(sys.argv[2]) if s.frame == palframe)
col0 = int(sys.argv[5]) if len(sys.argv) > 5 else 0
ncols = int(sys.argv[6]) if len(sys.argv) > 6 else NCOLS - col0
tiles = decode_packed(load_region(ROM, 'pc080sn'), 8, 8)
codes, attrs = fg_tilemap(rom, col0, ncols)
t = tiles[(codes & 0x3fff) % len(tiles)]
fx, fy = (attrs >> 14) & 1, (attrs >> 15) & 1
t = np.where(fx[..., None, None] == 1, t[..., :, ::-1], t)
t = np.where(fy[..., None, None] == 1, t[..., ::-1, :], t)
idx = (attrs & 0x1ff)[..., None, None].astype(np.int32) * 16 + t
img = pal[idx]
img[t == 0] = (255, 0, 255)  # transparent -> magenta
H, W = codes.shape
img = img.transpose(0, 2, 1, 3, 4).reshape(H * 8, W * 8, 3)
Image.fromarray(img).save(sys.argv[4])
print('rendered', img.shape)
