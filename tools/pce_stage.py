"""Build PC Engine stage data: one composited BG layer with streamed tile patterns.

usage: pce_stage.py maincpu.bin snapfile palframe seg_first seg_last outdir [dynsnap]

The arcade FG layer is composited over the BG layer locked at 1:1 scroll
(the round's BG strips repeat to cover the FG width). Colors are quantized to
the PCE's 9-bit RGB and packed into 16 BG palettes of 15 colors + shared color 0.

Rastan scrolls forward only, so VRAM is managed offline: a window of WINDOW
block-columns is resident; when column k+WINDOW-1 enters, any pattern no longer
used by the window is freed and the new column's missing patterns are uploaded.

Outputs (outdir):
  stage.bin   pointer table (3 bytes/column: bank offset, addr lo, addr hi
              relative to $6000 window) then column records:
                u8 n; n * (u16 tile#, 32 bytes pattern); 64 * u16 BAT word
  stage.inc   equates (columns, window, first slot)
  palette.bin 256 words (16 palettes) in VCE format
  preview.png converted stage as the PCE would show it
  dyncolor.inc VCE update lists for colors the arcade changes at run time
              (from dynsnap, a run that reaches the waterfall): the waterfall
              cycle (4 states, 8 frames each) and the sky colors that change
              when segment 3 begins. Those colors get palette slots of their own.
"""
import os
import sys
import numpy as np
from PIL import Image
from arcade_gfx import load_region, decode_packed
from fgmap import fg_tilemap
from bgmap import bg_entry, strip_codes, segment_bg_entry
from snap import read_snaps

ROMDIR = os.environ.get('RASTAN_ROMS', os.path.join(os.path.dirname(__file__), '..', 'roms', 'rastan'))
WINDOW = 35            # resident: 33 visible + 1 preloaded + 1 lagging (no overwrite of on-screen tiles)
FIRST_SLOT = 0x100     # tile # of first streamed slot (VRAM $1000)
NUM_SLOTS = 960       # $1000-$4BFF; $4C00-$4FFF holds stage prop cells
ROWS = 64


def arcade_pixels(rom, tiles, seg0, seg1):
    """Composite palette-index image [ROWS*8, W*8] of FG over 1:1 BG."""
    ncols = (seg1 - seg0 + 1) * 16
    fc, fa = fg_tilemap(rom, seg0 * 16, ncols)
    ft = tiles[fc & 0x3fff]
    fx, fy = (fa >> 14) & 1, (fa >> 15) & 1
    ft = np.where(fx[..., None, None] == 1, ft[..., :, ::-1], ft)
    ft = np.where(fy[..., None, None] == 1, ft[..., ::-1, :], ft)
    fidx = (fa & 0x1ff)[..., None, None].astype(np.int32) * 16 + ft

    ents = []
    for s in range(seg0, seg1 + 1):
        e = segment_bg_entry(rom, s)
        ents += [e, e + 1]
    bc = np.concatenate([strip_codes(rom, bg_entry(rom, e)[1]) for e in ents], 1)
    ba = np.concatenate([np.full((64, 16), bg_entry(rom, e)[0], np.uint16) for e in ents], 1)
    W = fc.shape[1]
    reps = (W + bc.shape[1] - 1) // bc.shape[1]
    bc = np.tile(bc, (1, reps))[:, :W]
    ba = np.tile(ba, (1, reps))[:, :W]
    bt = tiles[bc & 0x3fff]
    bidx = (ba & 0x1ff)[..., None, None].astype(np.int32) * 16 + bt   # BG opaque: pen 0 shows too
    return np.where(ft == 0, bidx, fidx)    # [64, W, 8, 8]


def to_pce_rgb(palwords):
    """Arcade xBGR555 -> PCE 3-bit per channel (r, g, b) tuples."""
    p = palwords.astype(np.int32)
    r, g, b = p & 31, (p >> 5) & 31, (p >> 10) & 31
    q = lambda v: np.clip((v * 7 + 15) // 31, 0, 7)
    return np.stack([q(r), q(g), q(b)], 1)


# Dynamic colors: codes >= 512 are virtual colors (512 + id). DYN_REP maps an
# id to the 9-bit color it shows first (used for packing and previews).
DYN_REP = {}


def unpack(k):
    if k >= 512:
        k = DYN_REP[k - 512]
    return ((k >> 6) & 7, (k >> 3) & 7, k & 7)


def word9(k):
    """9-bit packed (r<<6|g<<3|b) -> VCE word (g<<6|r<<3|b)."""
    r, g, b = unpack(k)
    return (g << 6) | (r << 3) | b


def find_dynamic(snapf, used_lines):
    """Arcade palette entries that change during play, from a run that reaches
    the waterfall. Returns (cycle, sky, sky_col): cycle maps arcade index ->
    4 colors (8 frames each); sky maps index -> (before, after) for a one-time
    change, made by the arcade while it streams tile column sky_col (counted
    from segment 0; the arcade changes the sky two columns before segment 3)."""
    snaps = [sn for sn in read_snaps(snapf) if sn.w(0x10c002) == 3]
    pals = np.array([np.array(sn.pal) for sn in snaps])
    used = np.zeros(2048, bool)
    for ln in used_lines:
        used[ln * 16:ln * 16 + 16] = True
    # Cycling: entries that keep changing at the end of the run.
    late = pals[-240:]
    ch = [int(x) for x in np.where((late != late[0]).any(0) & used)[0]]
    cycle = {}
    if ch:
        t0 = next(t for t in range(1, len(late)) if (late[t, ch] != late[t - 1, ch]).any())
        for x in ch:
            seq = [int(late[t0 + 8 * k, x]) for k in range(4)]
            assert all(late[t0 + 32 + 8 * k, x] == seq[k] for k in range(4)), 'cycle is not 4 x 8 frames'
            cycle[x] = seq
    # One-time changes to colors already in use (not the initial load from 0).
    sky, sky_col = {}, None
    for i in range(1, len(pals)):
        d = [int(x) for x in np.where((pals[i] != pals[i - 1]) & used)[0]
             if x not in cycle and pals[i - 1][x] != 0 and (pals[i:, x] == pals[i][x]).all()]
        if d:
            sky = {x: (int(pals[i - 1][x]), int(pals[i][x])) for x in d}
            sn = snaps[i]
            sky_col = sn.w(0x10c13e) * 64 + sn.w(0x10d0cc) * 4 + sn.w(0x10d0ca)
            break
    return cycle, sky, sky_col


def ccost(a, b):
    """Distance matrix between lists of packed 9-bit colors."""
    return cdist([unpack(int(k)) for k in a], [unpack(int(k)) for k in b])


def cdist(a, b):
    a = np.asarray(a, float); b = np.asarray(b, float)
    return (((a[:, None, :] - b[None, :, :]) * [3, 4, 2]) ** 2).sum(-1)   # rough luma weighting


def pack_palettes(tile_sets, color0, max_pals=16, size=15):
    """Greedy packing of tile color sets into palettes. Returns list of color lists and tile->palette."""
    order = sorted(range(len(tile_sets)), key=lambda i: -len(tile_sets[i]))
    pals = []
    assign = [0] * len(tile_sets)
    for i in order:
        s = tile_sets[i]
        best, best_cost = None, None
        for pi, p in enumerate(pals):
            grow = len(s - p)
            if len(p) + grow <= size:
                cost = grow
                if best_cost is None or cost < best_cost:
                    best, best_cost = pi, cost
        if best is not None:
            pals[best] |= s
            assign[i] = best
            continue
        if len(pals) < max_pals:
            pals.append(set(s))
            assign[i] = len(pals) - 1
            continue
        # no room: choose palette with least mapping error (filling spare slots first)
        errs = []
        for pi, p in enumerate(pals):
            cols = list(p) if p else [color0]
            missing = [c for c in s if c not in p]
            d = ccost(missing, cols).min(1) if missing else np.zeros(1)
            errs.append(d.sum())
        best = int(np.argmin(errs))
        p = pals[best]
        for c in sorted(s - p, key=lambda c: -ccost([c], list(p) or [color0]).min()):
            if len(p) < size:
                p.add(c)
        assign[i] = best
    return [sorted(p) for p in pals], assign


def main():
    rom = open(sys.argv[1], 'rb').read()
    snapf, palframe = sys.argv[2], int(sys.argv[3])
    seg0, seg1 = int(sys.argv[4], 0), int(sys.argv[5], 0)
    out = sys.argv[6]
    os.makedirs(out, exist_ok=True)

    tiles = decode_packed(load_region(ROMDIR, 'pc080sn'), 8, 8)
    pal = next(s.pal for s in read_snaps(snapf) if s.frame == palframe)
    rgb = to_pce_rgb(np.array(pal))                      # [2048, 3]
    as9 = lambda w: int((lambda c: (c[0] << 6) | (c[1] << 3) | c[2])(to_pce_rgb(np.array([w]))[0]))

    idx = arcade_pixels(rom, tiles, seg0, seg1)           # [64, W, 8, 8]
    W = idx.shape[1]
    px = rgb[idx]                                         # [64, W, 8, 8, 3]
    code = (px[..., 0] << 6) | (px[..., 1] << 3) | px[..., 2]   # r<<6|g<<3|b packed key

    # Dynamic colors become virtual colors with slots of their own.
    cycle, sky, sky_col = ({}, {}, None)
    if len(sys.argv) > 7:
        cycle, sky, sky_col = find_dynamic(sys.argv[7], sorted(set((np.unique(idx) // 16).tolist())))
    dyn_ids = {}                  # arcade index -> id ; id -> states (9-bit)
    dyn_states = []
    for x, seq in list(cycle.items()) + list(sky.items()):
        st = tuple(as9(w) for w in seq)
        if st not in dyn_states:
            dyn_states.append(st)
        dyn_ids[x] = dyn_states.index(st)
    for i, st in enumerate(dyn_states):
        DYN_REP[i] = st[0] if len(st) == 2 else st[0]
    for x, i in dyn_ids.items():
        code[idx == x] = 512 + i
    print(f'dynamic colors: {len(cycle)} cycling entries, {len(sky)} sky entries (at column {sky_col}), '
          f'{len(dyn_states)} virtual colors')
    # shared color 0 = most frequent color
    vals, counts = np.unique(code, return_counts=True)
    color0 = int(vals[np.argmax(counts)])
    print(f'{W} tile columns, {len(vals)} distinct 9-bit colors, color0={color0:03o}')

    # unique composited tiles
    flat = code.reshape(-1, 64)
    uniq, inv = np.unique(flat, axis=0, return_inverse=True)
    inv = inv.reshape(ROWS, W)
    print('unique composited tiles', len(uniq))

    def reduce(cols, n=15):
        cols = list(cols)
        while len(cols) > n:          # merge closest pair
            c = [((k >> 6) & 7, (k >> 3) & 7, k & 7) for k in cols]
            d = cdist(c, c); np.fill_diagonal(d, 1e9)
            a, b = np.unravel_index(np.argmin(d), d.shape)
            cols.pop(max(a, b))
        return cols
    sets = [frozenset(reduce(sorted(set(int(v) for v in t) - {color0}))) for t in uniq]
    over = sum(1 for t in uniq if len(set(t.tolist()) - {color0}) > 15)
    pals, assign = pack_palettes(sets, color0)
    print(f'{len(pals)} palettes, sizes {[len(p) for p in pals]}, tiles needing >15 colors: {over}')

    # remap each unique tile to (palette, 4bpp pattern)
    pal_rgb = [np.array([unpack(color0)] + [unpack(c) for c in p]) for p in pals]
    pat_of = []
    for t, pi in zip(uniq, assign):
        cols = pal_rgb[pi]
        keys = [color0] + list(pals[pi])
        c = np.array([unpack(int(v)) for v in t])
        d = cdist(c, cols)
        virt = np.array([k >= 512 for k in keys])
        d[:, virt] = 1e9                       # nothing maps onto a dynamic slot...
        for j, v in enumerate(t):
            if int(v) in keys:                 # ...except that exact color
                d[j] = 1e9
                d[j, keys.index(int(v))] = 0
        pix = d.argmin(1)
        pat_of.append((pi, pix.astype(np.uint8).tobytes()))
    patterns = {}
    tile_pat = np.zeros(len(uniq), np.int32)
    tile_pal = np.zeros(len(uniq), np.int32)
    for i, (pi, p) in enumerate(pat_of):
        tile_pat[i] = patterns.setdefault(p, len(patterns))
        tile_pal[i] = pi
    pat_list = [np.frombuffer(p, np.uint8).reshape(8, 8) for p in patterns]
    print('unique PCE patterns', len(pat_list))

    colpat = tile_pat[inv]          # [64, W]
    colpal = tile_pal[inv]

    # ---- offline VRAM streaming schedule
    free = list(range(FIRST_SLOT + NUM_SLOTS - 1, FIRST_SLOT - 1, -1))
    resident = {}        # pattern -> slot
    users = {}           # pattern -> set of columns in window using it
    records = []
    max_res = 0

    def add_column(c):
        ups = []
        bat = []
        for r in range(ROWS):
            p = int(colpat[r, c])
            if p not in resident:
                slot = free.pop()
                resident[p] = slot
                ups.append((slot, p))
            users.setdefault(p, set()).add(c)
            bat.append(resident[p] | (int(colpal[r, c]) << 12))
        return ups, bat

    def drop_column(c):
        for r in range(ROWS):
            p = int(colpat[r, c])
            u = users.get(p)
            if u is None:
                continue
            u.discard(c)
            if not u:
                del users[p]
                free.append(resident.pop(p))

    for c in range(W):
        if c >= WINDOW:
            drop_column(c - WINDOW)
        ups, bat = add_column(c)
        max_res = max(max_res, len(resident))
        records.append((ups, bat))
    print(f'max resident patterns {max_res}/{NUM_SLOTS}, total uploads {sum(len(u) for u, _ in records)}')

    def pce_pattern(p):
        b = bytearray(32)
        for y in range(8):
            for pl in range(4):
                v = 0
                for x in range(8):
                    if (p[y, x] >> pl) & 1:
                        v |= 0x80 >> x
                off = (pl >> 1) * 16 + y * 2 + (pl & 1)
                b[off] = v
        return bytes(b)
    pce_pats = [pce_pattern(p) for p in pat_list]

    body = bytearray()
    offs = []
    table_size = 3 * W
    for ups, bat in records:
        offs.append(table_size + len(body))
        body.append(len(ups))
        for slot, p in ups:
            body += slot.to_bytes(2, 'little') + pce_pats[p]
        for v in bat:
            body += v.to_bytes(2, 'little')
    table = bytearray()
    for o in offs:
        table += bytes([o // 8192, 0x6000 + o % 8192 & 0xff, (0x6000 + o % 8192) >> 8])
    assert table_size <= 8192, 'pointer table must fit in one bank'
    blob = bytes(table + body)
    open(f'{out}/stage.bin', 'wb').write(blob)
    print(f'stage.bin {len(blob)} bytes ({(len(blob) + 8191) // 8192} banks)')

    vce = bytearray()
    for i in range(16):
        cols = [unpack(color0)] + ([unpack(c) for c in pals[i]] if i < len(pals) else [])
        cols += [(0, 0, 0)] * (16 - len(cols))
        for r, g, b in cols:
            vce += ((g << 6) | (r << 3) | b).to_bytes(2, 'little')
    open(f'{out}/palette.bin', 'wb').write(vce)

    # VCE update lists: entries (address, color) for every slot holding a virtual color.
    slots = {}
    for pi in range(len(pals)):
        for si, k in enumerate([color0] + list(pals[pi])):
            if k >= 512 and (si > 0 or pi == 0):
                slots.setdefault(k - 512, []).append(pi * 16 + si)

    def vce_list(label, pairs):
        lines = [f'{label}:\t\tdb\t{len(pairs)}']
        for a, c in pairs:
            lines.append(f'\t\tdw\t${a:03X}, ${c:03X}')
        return '\n'.join(lines) + '\n'
    with open(f'{out}/dyncolor.inc', 'w') as f:
        f.write('; Generated by tools/pce_stage.py: run-time BG color changes.\n')
        col = sky_col - seg0 * 64 if sky_col is not None and 0 <= sky_col - seg0 * 64 < W else 0xFFFF
        f.write(f'DYN_SKY_COLUMN\t= ${col:04X}\t; streaming this column switches the sky\n')
        for s_ in range(4):
            pairs = [(a, word9(dyn_states[i][s_])) for i in slots if len(dyn_states[i]) == 4 for a in slots[i]]
            f.write(vce_list(f'dyn_cycle{s_}', pairs))
        for s_, name in ((0, 'dyn_sky_a'), (1, 'dyn_sky_b')):
            pairs = [(a, word9(dyn_states[i][s_])) for i in slots if len(dyn_states[i]) == 2 for a in slots[i]]
            f.write(vce_list(name, pairs))
    print(f'dynamic slots: ' + ', '.join(f'{i}:{len(v)}' for i, v in sorted(slots.items())))
    with open(f'{out}/stage.inc', 'w') as f:
        f.write(f'STAGE_COLUMNS = {W}\nSTAGE_WINDOW = {WINDOW}\nSTAGE_BANKS = {(len(blob) + 8191) // 8192}\n')

    # preview: render from the PCE-side data (patterns + palettes)
    prev = np.zeros((ROWS * 8, W * 8, 3), np.uint8)
    for c in range(W):
        for r in range(ROWS):
            p = pat_list[colpat[r, c]]
            prev[r * 8:r * 8 + 8, c * 8:c * 8 + 8] = (pal_rgb[colpal[r, c]][p] * 255 // 7)
    Image.fromarray(prev).save(f'{out}/preview.png')
    # arcade reference at full color for comparison
    ref = np.array(pal, dtype=np.int32)
    rr, gg, bb = ref & 31, (ref >> 5) & 31, (ref >> 10) & 31
    ref8 = np.stack([rr, gg, bb], 1) * 255 // 31
    arc = ref8[idx].transpose(0, 2, 1, 3, 4).reshape(ROWS * 8, W * 8, 3).astype(np.uint8)
    Image.fromarray(arc).save(f'{out}/arcade.png')


if __name__ == '__main__':
    main()
