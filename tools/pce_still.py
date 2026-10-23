"""Turn one arcade screen into a PC Engine still: tiles, a tile map and palettes.

usage: pce_still.py name snapshot frame x0 y0 layers sprites outdir
                    [--keep X0,Y0,X1,Y1] [--clear X0,Y0,X1,Y1]... [--grey] [--text X,Y,STRING]

Renders frame `frame` of an arcade snapshot (sim/sim) with the given tile layers
("0", "1", "01", or "-" for none) and, with sprites=1, the sprites. --keep blacks
out everything outside one rectangle, --clear blacks out a rectangle (arcade screen
coordinates), --grey keeps only white and grey pixels (lettering), --text writes a line in the arcade's own 8x8 font (the FG layer's
tiles are ASCII), on a palette of its own so the game can blink it. Then it crops
the 256x224 window at (x0, y0) of the 320x240 screen and converts it:

  name.bin   tiles (32 bytes each, tile 0 blank), then the 32x28 tile map
             (words, ready for the BAT: palette << 12 | tile + $100, i.e. tiles
             loaded at VRAM $1000), then the palettes (16 VCE words each)
  name.inc   NAME_TILES, NAME_PALS, NAME_MAP_OFS, NAME_PAL_OFS (byte offsets),
             NAME_BLINK_PAL (the text's palette, or $FF)
  name.png   what the PC Engine will show (for checking by eye)

Colour 0 of every palette is black: the screens this is for are text and
pictures on black, and the backdrop around them (and the display while it is
off) then matches.
"""
import os
import sys
import numpy as np
from PIL import Image
from arcade_gfx import load_region
from snap import read_snaps, Renderer, palette_rgb
from pce_stage import pack_palettes, unpack, word9

W, H = 256, 224
ROMDIR = os.environ.get('RASTAN_ROMS', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'roms', 'rastan'))


def to9(rgb):
    """8-bit RGB -> packed 9-bit r<<6|g<<3|b (PCE 3 bits a channel)."""
    q = np.clip((rgb.astype(int) * 7 + 127) // 255, 0, 7)
    return (q[..., 0] << 6) | (q[..., 1] << 3) | q[..., 2]


def tile_bytes(t):
    """8x8 palette indices -> PCE BG tile: rows of planes 0/1, then rows of planes 2/3."""
    b = bytearray(32)
    for y in range(8):
        for p in range(4):
            v = 0
            for x in range(8):
                if (t[y, x] >> p) & 1:
                    v |= 0x80 >> x
            b[(p >> 1) * 16 + y * 2 + (p & 1)] = v
    return bytes(b)


def main():
    args = sys.argv[1:]
    opts = {'keep': None, 'clear': [], 'text': None, 'grey': False}
    pos = []
    while args:
        a = args.pop(0)
        if a == '--grey':
            opts['grey'] = True
        elif a.startswith('--'):
            v = args.pop(0)
            if a == '--clear':
                opts['clear'].append([int(n) for n in v.split(',')])
            elif a == '--keep':
                opts['keep'] = [int(n) for n in v.split(',')]
            elif a == '--text':
                x, y, t = v.split(',', 2)
                opts['text'] = (int(x), int(y), t)
        else:
            pos.append(a)
    name, snapf, frame, x0, y0, layers, sprites, out = pos
    frame, x0, y0 = int(frame), int(x0), int(y0)
    os.makedirs(out, exist_ok=True)
    R = Renderer(load_region(ROMDIR, 'pc080sn'), load_region(ROMDIR, 'pc090oj'))
    snap = next(s for s in read_snaps(snapf) if s.frame == frame)
    lay = tuple(int(c) for c in layers if c != '-')
    img = np.array(R.render(snap, lay, sprites == '1')).astype(np.uint8)
    if opts['keep']:
        a, b, c, d = opts['keep']
        kept = img[b:d, a:c].copy()
        img[:] = 0
        img[b:d, a:c] = kept
    for a, b, c, d in opts['clear']:
        img[b:d, a:c] = 0
    if opts['grey']:                                  # only the white/grey pixels (lettering)
        g = (np.ptp(img.astype(int), axis=-1) > 24)
        img[g] = 0
    text_tiles = set()
    if opts['text']:
        tx, ty, t = opts['text']
        pal = palette_rgb(snap.pal)
        for i, ch in enumerate(t):
            g = R.tiles[ord(ch)]                      # FG tile = ASCII code, colour 0
            px = np.where(g[..., None] > 0, pal[g], 0)
            img[ty:ty + 8, tx + 8 * i:tx + 8 * i + 8] = px
        assert (tx - x0) % 8 == 0 and (ty - y0) % 8 == 0, 'text must sit on the tile grid'
        r0, c0 = (ty - y0) // 8, (tx - x0) // 8
        text_tiles = {r0 * (W // 8) + c0 + i for i in range(len(t))}
    img = img[y0:y0 + H, x0:x0 + W]
    c9 = to9(img)
    black = 0
    tiles = c9.reshape(H // 8, 8, W // 8, 8).transpose(0, 2, 1, 3)        # [28, 32, 8, 8]
    sets = [set(int(v) for v in np.unique(t)) - {black} for t in tiles.reshape(-1, 8, 8)]
    others = [sets[n] if n not in text_tiles else set() for n in range(len(sets))]
    pals, assign = pack_palettes(others, black)
    blink = 0xFF
    if text_tiles:                                    # the text: a palette of its own
        blink = len(pals)
        pals.append(sorted(set().union(*(sets[n] for n in text_tiles))))
        for n in text_tiles:
            assign[n] = blink
    assert len(pals) <= 16, f'{len(pals)} palettes'
    blob_tiles = [bytes(32)]
    index = {bytes(32): 0}
    bat = []
    shown = np.zeros((H, W, 3), np.uint8)
    for n, t in enumerate(tiles.reshape(-1, 8, 8)):
        if not sets[n]:
            bat.append(0x100)
            continue
        p = assign[n]
        cols = [black] + pals[p]
        lut = {c: i for i, c in enumerate(cols)}
        # colours a palette had no room for: the nearest it has
        idx = np.vectorize(lambda c: lut[c] if c in lut else
                           1 + int(np.argmin([sum((np.array(unpack(c)) - unpack(k)) ** 2) for k in pals[p]])))(t)
        tb = tile_bytes(idx)
        if tb not in index:
            index[tb] = len(blob_tiles)
            blob_tiles.append(tb)
        bat.append((p << 12) | (0x100 + index[tb]))
        r, c = divmod(n, W // 8)
        shown[r * 8:r * 8 + 8, c * 8:c * 8 + 8] = np.array([[unpack(cols[i]) for i in row] for row in idx]) * 255 // 7
    pal_words = []
    for p in pals:
        ws = [0] + [word9(c) for c in p]
        pal_words += ws + [0] * (16 - len(ws))
    blob = b''.join(blob_tiles)
    map_ofs = len(blob)
    blob += b''.join(w.to_bytes(2, 'little') for w in bat)
    pal_ofs = len(blob)
    blob += b''.join(w.to_bytes(2, 'little') for w in pal_words)
    up = name.upper()
    open(os.path.join(out, f'{name}.bin'), 'wb').write(blob)
    with open(os.path.join(out, f'{name}.inc'), 'w') as f:
        f.write(f'; Generated by tools/pce_still.py from {os.path.basename(snapf)} frame {frame}\n')
        f.write(f'{up}_TILES\t= {len(blob_tiles)}\n{up}_PALS\t= {len(pals)}\n')
        f.write(f'{up}_MAP_OFS\t= {map_ofs}\n{up}_PAL_OFS\t= {pal_ofs}\n{up}_BYTES\t= {len(blob)}\n')
        f.write(f'{up}_BLINK_PAL\t= ${blink:02X}\n')
    Image.fromarray(np.concatenate([img, shown], 1)).save(os.path.join(out, f'{name}.png'))
    assert len(blob) <= 16384, 'a still must fit in MPR3 and MPR4'
    print(f'{name}: {len(blob_tiles)} tiles, {len(pals)} palettes, {len(blob)} bytes')


if __name__ == '__main__':
    main()
