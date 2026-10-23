"""Build PC Engine stage data: one composited BG layer with streamed tile patterns.

usage: pce_stage.py maincpu.bin snapfile palframe seg_first seg_last outdir [dynsnap [castlesnap:frame]]

The castle (segments from CASTLE_SEG) has colours of its own in the arcade's palette
line $2x (its stone), and the lava hall (HALL_SEG) in line $14x too (its fire),
which the arcade loads as Rastan enters them; they are taken from castlesnap at
that frame, a frame in the hall. (sim/scripts/castle.txt, from checkpoint $13 on,
shows line $14x back to its round-start colours past the hall.)

The arcade FG layer is composited over the BG layer locked at 1:1 scroll
(the round's BG strips repeat to cover the FG width). Colors are quantized to
the PCE's 9-bit RGB and packed into 16 BG palettes of 15 colors + shared color 0.

The world (see world.py) streams as lines of 64 tiles, columns and rows, in
play order. VRAM is managed offline with a model of the 64x64 BAT: a pattern is
resident while some BAT cell shows it, and a line uploads the patterns it
needs that are not resident.

Outputs (outdir):
  stage.bin   pointer table (3 bytes/line: bank offset, addr lo, addr hi
              relative to $6000 window) then line records (under 256 bytes each):
                u8 flags (1 row, 2 stop: a door loads the rest), u8 BAT column/row,
                s16 trigger (world x of a column, y of a row), u8 camera region;
                u8 n; n * 3 bytes upload: slot lo, pattern # lo,
                  slot hi | pattern # hi << 3  (slot: VRAM tile #, pattern: stage_pats.bin);
                the line's 64 BAT words as 16 quads (4 words each), codes:
                  $00-$DF        quad # (the 224 most used quads)
                  $E0-$EF        the previous quad again, 1-16 times
                  $F0-$FF, lo    quad # ((code & $0F) << 8 | lo)
  stage_pats.bin  every BG pattern once, 32 bytes each (PCE format), by first use
  stage_quads.bin every distinct quad once, 8 bytes each (4 BAT words), most used first
  stage.inc   equates and the camera box of each region
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
import world

ROMDIR = os.environ.get('RASTAN_ROMS', os.path.join(os.path.dirname(__file__), '..', 'roms', 'rastan'))
FIRST_SLOT = 0x100     # tile # of first streamed slot (VRAM $1000)
CASTLE_SEG = 0x10      # the castle's first room (the gate loads its colours: line $2x)
HALL_SEG = 0x12        # the lava hall, whose fire takes line $14x as well
# The lava hall's fire (markers $4C, $52-$55): the arcade draws 32x32 flames, cells
# $224-$233 (4 phases of 4 cells, a phase every 4 frames, neighbouring blocks one phase
# apart), along the lava from FIRE_X0 to FIRE_X1, top at FIRE_Y (hall.snp: two of the
# five strips seen, 80 px each, on a 32 px grid from 8768). The wall behind repeats
# every 32 px, so the port bakes them into the tile map instead (the VDC could not
# show 13 sprite flames a line): the strip's cells show 32 fixed tiles at FIRE_TILE0,
# even blocks' 16 then odd blocks', and the game rewrites them each phase.
FIRE_X0, FIRE_X1, FIRE_Y = 8768, 9168, -320
FIRE_CELL = 0x224
FIRE_TILE0 = 0x4C0     # VRAM $4C00: the stage props' cells, unused in the castle
NUM_SLOTS = 936       # $1000-$4A7F; $4A80-$4AFF the swarm's bat cells, $4B00-$4BFF the floor spears'
                      # cells, $4C00-$4FFF stage props
ROWS = 64
QUAD_SHORT = 0xE0   # line codes: $00-$DF quad #, $E0-$EF repeat, $F0-$FF long quad #


def arcade_pixels(rom, tiles, seg0, seg1):
    """Palette-index tiles [ROWS, L, 8, 8] of the world's stream lines (world.lines()),
    FG composited over the BG locked at 1:1. The BG strips of segments seg0..seg1
    repeat along the map columns; a shaft takes its map columns' strips too."""
    ents = []
    for s in range(seg0, seg1 + 1):
        e = segment_bg_entry(rom, s)
        ents += [e, e + 1]
    bc = np.concatenate([strip_codes(rom, bg_entry(rom, e)[1]) for e in ents], 1)
    ba = np.concatenate([np.full((64, 16), bg_entry(rom, e)[0], np.uint16) for e in ents], 1)
    out = []
    squares = {}
    for ln in world.lines():
        s = ln['seg']
        if s not in squares:
            fc, fa, _ = world.square_tiles(rom, s)
            ft = tiles[fc & 0x3fff]
            fx, fy = (fa >> 14) & 1, (fa >> 15) & 1
            ft = np.where(fx[..., None, None] == 1, ft[..., :, ::-1], ft)
            ft = np.where(fy[..., None, None] == 1, ft[..., ::-1, :], ft)
            fidx = (fa & 0x1ff)[..., None, None].astype(np.int32) * 16 + ft
            cols = (s * 64 + np.arange(64)) % bc.shape[1]
            bt = tiles[bc[:, cols] & 0x3fff]
            bidx = (ba[:, cols] & 0x1ff)[..., None, None].astype(np.int32) * 16 + bt
            squares[s] = np.where(ft == 0, bidx, fidx)       # [64, 64, 8, 8]
        sq = squares[s]
        out.append(sq[ln['i'], :] if ln['row'] else sq[:, ln['i']])
    return np.stack(out, 1)    # [64, L, 8, 8]


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
    sky, sky_cols = find_skies([snapf] + [f for f in os.environ.get('SKY_SNAPS', '').split(',') if f],
                               used, set(cycle))
    return cycle, sky, sky_cols


SKY_STEP = 128          # (columns between the sky's steps)


def find_skies(snapfs, used, cycle):
    """The sky's steps toward dusk. The arcade changes some colours (palette line 2) a
    few times along the outdoor stage, each time while it streams a column 2 before an
    odd segment (190, 318, ...); a restart loads the step its checkpoint is at. From
    runs (the round start's, and from later checkpoints): the distinct states, in order,
    and the column each begins at. Returns (sky, cols): sky maps an arcade index to its
    colour in each state; cols[k] the column state k begins at (cols[0] = 0)."""
    seen = []                       # (column, state) events: a change, or a restart's load
    for f in snapfs:
        prev, age = None, 0
        for sn in read_snaps(f):
            g = sn.w(0x10c002) == 3
            p = np.array(sn.pal)
            col = sn.w(0x10c13e) * 64 + sn.w(0x10d0cc) * 4 + sn.w(0x10d0ca)
            if not g or not p[used].any():
                prev, age = None, 0
                continue
            age += 1
            q = p.copy()
            q[list(cycle)] = 0
            key = tuple(int(v) for v in q[used])
            if age == 30:                   # (a load settles over a few frames)
                seen.append((col, q, False))
            elif age > 30 and key != prev:
                seen.append((col, q, True))
            prev = key
    states, cols = [], []
    for col, q, change in sorted(seen, key=lambda e: (e[0], not e[2])):
        if any((q == s).all() for s in states):
            continue
        states.append(q)
        cols.append(col if change else None)
    # Steps seen only as a restart's load lie on the same 128-column grid.
    base = next(c - k * SKY_STEP for k, c in enumerate(cols) if k and c is not None)
    for k in range(1, len(cols)):
        want = base + k * SKY_STEP
        assert cols[k] in (None, want), f'sky step {k} at column {cols[k]}, not {want}'
        cols[k] = want
    cols[0] = 0
    idx = sorted(int(x) for x in np.where(used)[0] if len({int(s[x]) for s in states}) > 1)
    sky = {x: tuple(int(s[x]) for s in states) for x in idx}
    return sky, cols


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
    castle = np.array([ln['seg'] >= CASTLE_SEG for ln in world.lines()])
    cpal = pal
    hall = np.array([ln['seg'] == HALL_SEG for ln in world.lines()])
    hpal = pal
    if len(sys.argv) > 8:                                 # the castle's own colours
        cf, cfr = sys.argv[8].rsplit(':', 1)
        hpal = np.array(next(s.pal for s in read_snaps(cf) if s.frame == int(cfr)))
        cpal = hpal.copy()
        cpal[0x140:0x150] = np.array(pal)[0x140:0x150]  # (the fire's line: the hall only)
        crgb, hrgb = to_pce_rgb(np.array(cpal)), to_pce_rgb(hpal)
        px[:, castle] = crgb[idx[:, castle]]
        px[:, hall] = hrgb[idx[:, hall]]
        print(f'castle colours from {os.path.basename(cf)} frame {cfr}: '
              f'{int((rgb != crgb).any(1).sum())} palette entries differ, {int((crgb != hrgb).any(1).sum())} more in the hall')
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
        code[(idx == x) & ~castle[None, :, None, None]] = 512 + i   # (outdoors only)
    print(f'dynamic colors: {len(cycle)} cycling entries, {len(sky)} sky entries ({len(sky_col)} steps, from '
          f'columns {sky_col}), {len(dyn_states)} virtual colors')
    # Two sets of 16 palettes: outdoors and the castle. The camera never shows both
    # (it stops at the castle gate outside and keeps inside the castle wall), and the
    # game loads the set for where Rastan is. Colour 0 of each: its most frequent.
    pset = np.broadcast_to(castle[None, :], (ROWS, W)).astype(np.int64)
    color0s = []
    for k in (0, 1):
        vals, counts = np.unique(code[:, castle == bool(k)], return_counts=True)
        color0s.append(int(vals[np.argmax(counts)]))
        print(f'palette set {k}: {len(vals)} distinct 9-bit colors, color0={color0s[k]:03o}')
    print(f'{W} tile columns')

    # unique composited tiles (per palette set)
    flat = np.concatenate([code.reshape(-1, 64), pset.reshape(-1, 1)], 1)
    uniq, inv = np.unique(flat, axis=0, return_inverse=True)
    inv = inv.reshape(ROWS, W)
    uset = uniq[:, 64]
    uniq = uniq[:, :64]
    print('unique composited tiles', len(uniq))

    def reduce(cols, n=15):
        cols = list(cols)
        while len(cols) > n:          # merge closest pair
            c = [((k >> 6) & 7, (k >> 3) & 7, k & 7) for k in cols]
            d = cdist(c, c); np.fill_diagonal(d, 1e9)
            a, b = np.unravel_index(np.argmin(d), d.shape)
            cols.pop(max(a, b))
        return cols
    psets = []                    # per set: (color0, pals, rgb of each palette)
    assign = [0] * len(uniq)
    for k in (0, 1):
        c0 = color0s[k]
        ti = [i for i in range(len(uniq)) if uset[i] == k]
        sets = [frozenset(reduce(sorted(set(int(v) for v in uniq[i]) - {c0}))) for i in ti]
        over = sum(1 for i in ti if len(set(uniq[i].tolist()) - {c0}) > 15)
        pals_k, asg = pack_palettes(sets, c0)
        for i, a in zip(ti, asg):
            assign[i] = a
        psets.append((c0, pals_k, [np.array([unpack(c0)] + [unpack(c) for c in p]) for p in pals_k]))
        print(f'set {k}: {len(pals_k)} palettes, sizes {[len(p) for p in pals_k]}, tiles needing >15 colors: {over}')
    color0, pals, pal_rgb = psets[0]           # (outdoors: the dynamic colours' set)

    # ---- the fire: its composite tiles (4 phases x 16 positions), their palettes
    fire = None
    if len(sys.argv) > 8:
        fsnap = next(s_ for s_ in read_snaps(cf) if s_.frame == int(cfr))
        bank = (fsnap.sprctrl & 0xe0) >> 1
        spr = decode_packed(load_region(ROMDIR, 'pc090oj'), 16, 16).astype(int)
        lines_ = world.lines()
        hx0, hy0 = world.square_origin(HALL_SEG)
        col_line = {ln['i']: c for c, ln in enumerate(lines_) if ln['seg'] == HALL_SEG and not ln['row']}
        c0i, r0 = (FIRE_X0 - hx0) // 8, (FIRE_Y - hy0) // 8
        bg = np.zeros((32, 32), np.int64)                 # the wall behind a block (9-bit keys)
        for tx in range(4):
            for ty in range(4):
                bg[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8] = code[r0 + ty, col_line[c0i + tx]]
        hkey = lambda i: (lambda c: (int(c[0]) << 6) | (int(c[1]) << 3) | int(c[2]))(hrgb[i])
        comps = []
        for ph in range(4):
            b = bg.copy()
            for k, (ox, oy) in enumerate(((0, 0), (16, 0), (0, 16), (16, 16))):
                g = spr[FIRE_CELL + ph * 4 + k]
                for y in range(16):
                    for x in range(16):
                        if g[y, x]:
                            b[oy + y, ox + x] = hkey(bank * 16 + g[y, x])
            comps.append(b)
        c0c = psets[1][0]
        pos_sets = []
        for ty in range(4):
            for tx in range(4):
                cs = set()
                for b in comps:
                    cs |= set(int(v) for v in np.unique(b[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8]))
                pos_sets.append(frozenset(reduce(sorted(cs - {c0c}))))
        fpals, fasg = pack_palettes(pos_sets, c0c)
        base = len(psets[1][1])
        assert base + len(fpals) <= 16, f'castle palettes: {base} + fire {len(fpals)}'
        psets[1][1].extend(fpals)
        psets[1][2].extend(np.array([unpack(c0c)] + [unpack(c) for c in p_]) for p_ in fpals)
        ftiles = bytearray()
        fpix = []
        for ph in range(4):
            for pos in range(16):
                ty, tx = divmod(pos, 4)
                keys = [c0c] + list(fpals[fasg[pos]])
                t = comps[ph][ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8]
                lut = {k: i for i, k in enumerate(keys)}
                pix = np.array([[lut[int(v)] if int(v) in lut else
                                 int(np.argmin(ccost([int(v)], keys)[0])) for v in row] for row in t], np.uint8)
                fpix.append(pix)
        fire = dict(c0i=c0i, r0=r0, pal=[base + a for a in fasg], pix=fpix, col_line=col_line)
        print(f'fire: {len(fpals)} palettes (castle set {base} + {len(fpals)})')

    # remap each unique tile to (palette, 4bpp pattern)
    pat_of = []
    for t, pi, k in zip(uniq, assign, uset):
        c0, pals_k, rgb_k = psets[k]
        cols = rgb_k[pi]
        keys = [c0] + list(pals_k[pi])
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

    # ---- offline VRAM streaming schedule: a model of the BAT. A pattern stays
    # resident while a BAT cell shows it; a line's upload list holds the patterns
    # it brings that are not resident.
    lines = world.lines()
    free = list(range(FIRST_SLOT + NUM_SLOTS - 1, FIRST_SLOT - 1, -1))
    resident = {}        # pattern -> slot
    refs = {}            # pattern -> number of live BAT cells showing it
    bat_pat = -np.ones((64, 64), np.int64)
    bat_x = np.zeros((64, 64), np.int64)     # world position of each cell's tile
    bat_y = np.zeros((64, 64), np.int64)
    records = []
    max_res = 0
    # Bounds on where the camera can still go (see world.camera_bounds): cells out of
    # reach are released, so their patterns can go.
    reach = world.camera_reach(lines)

    def release(br, bc_):
        old = int(bat_pat[br, bc_])
        if old >= 0:
            bat_pat[br, bc_] = -1
            refs[old] -= 1
            if not refs[old]:
                del refs[old]
                free.append(resident.pop(old))

    for c, ln in enumerate(lines):
        if ln['stop']:          # A door loads the next room whole: the BAT starts empty.
            for br in range(64):
                for bc_ in range(64):
                    release(br, bc_)
        ox, oy = world.square_origin(ln['seg'])
        ups, bat = [], []
        for r in range(ROWS):
            br, bc_ = (ln['i'], r) if ln['row'] else (r, ln['i'])
            p = int(colpat[r, c])
            if p not in resident:
                slot = free.pop()
                resident[p] = slot
                ups.append((slot, p))
            refs[p] = refs.get(p, 0) + 1
            release(br, bc_)
            bat_pat[br, bc_] = p
            bat_x[br, bc_], bat_y[br, bc_] = ox + bc_ * 8, oy + br * 8
            bat.append(resident[p] | (int(colpal[r, c]) << 12))
        x_lo, y_hi = reach[c]
        for br, bc_ in zip(*np.nonzero((bat_pat >= 0) & ((bat_x + 8 <= x_lo) | (bat_y >= y_hi + 224)))):
            release(br, bc_)
        max_res = max(max_res, len(resident))
        records.append((ups, bat))
    print(f'max resident patterns {max_res}/{NUM_SLOTS}, total uploads {sum(len(u) for u, _ in records)}')
    if fire:                      # the fire strip's cells: its fixed tiles
        ncol = (FIRE_X1 - FIRE_X0) // 8
        for k in range(ncol):
            c = fire['col_line'][fire['c0i'] + k]
            j, tx = divmod(k, 4)
            for ty in range(4):
                pos = ty * 4 + tx
                records[c][1][fire['r0'] + ty] = (FIRE_TILE0 + (j % 2) * 16 + pos) | (fire['pal'][pos] << 12)

    def pce_pattern(p):  # noqa: E306
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
    if fire:                      # fire.bin: 4 phases x 16 tiles, by position
        open(f'{out}/fire.bin', 'wb').write(b''.join(pce_pattern(p) for p in fire['pix']))

    # Compressed stream (see the module docstring): each pattern is stored once in
    # stage_pats.bin, numbered by first upload, and an upload is (slot, pattern #).
    # The BAT words of a line are 16 quads (a 4-tile slice of an arcade block): each
    # distinct quad is stored once in stage_quads.bin, most used first, and a line
    # is a short code stream over them.
    pat_num = {}
    for ups, _ in records:
        for _, p in ups:
            pat_num.setdefault(p, len(pat_num))
    assert len(pat_num) <= 32 * 256, f'{len(pat_num)} patterns: the upload code has 13 bits'
    quad_use = {}
    for _, bat in records:
        for k in range(0, 64, 4):
            q = tuple(bat[k:k + 4])
            quad_use[q] = quad_use.get(q, 0) + 1
    quads = sorted(quad_use, key=lambda q: -quad_use[q])
    assert len(quads) <= 4096, f'{len(quads)} quads: the long code has 12 bits'
    quad_num = {q: i for i, q in enumerate(quads)}

    def bat_codes(bat):
        qs = [quad_num[tuple(bat[k:k + 4])] for k in range(0, 64, 4)]
        code = bytearray()
        k = 0
        while k < 16:
            q = qs[k]
            code += bytes([q]) if q < QUAD_SHORT else bytes([0xF0 | q >> 8, q & 0xff])
            j = k + 1
            while j < 16 and j - k <= 16 and qs[j] == q:
                j += 1
            if j - k > 1:
                code.append(0xE0 | (j - k - 2))
            k = j
        return code

    body = bytearray()
    offs = []
    table_size = 3 * W
    regions = []
    n_up = 0
    for (ups, bat), ln in zip(records, lines):
        offs.append(table_size + len(body))
        box = ln['box'] + (int(ln['stop'] or ln['seg'] in world.FREE),)
        if box not in regions:
            regions.append(box)
        trig = ln['trigger'] & 0xffff
        rec = bytearray([(1 if ln['row'] else 0) | (2 if ln['stop'] else 0), ln['i'], trig & 0xff, trig >> 8,
                         regions.index(box), len(ups)])
        for slot, p in ups:
            n = pat_num[p]
            assert FIRST_SLOT <= slot < 0x800
            rec += bytes([slot & 0xff, n & 0xff, (slot >> 8) | (n >> 8) << 3])
        rec += bat_codes(bat)
        assert len(rec) < 256, 'a record is read with one 8-bit index'
        body += rec
        n_up += len(ups)
    table = bytearray()
    for o in offs:
        table += bytes([o // 8192, 0x6000 + o % 8192 & 0xff, (0x6000 + o % 8192) >> 8])
    assert table_size <= 8192, 'pointer table must fit in one bank'
    blob = bytes(table + body)
    pats_blob = b''.join(pce_pats[p] for p in sorted(pat_num, key=pat_num.get))
    quads_blob = b''.join(v.to_bytes(2, 'little') for q in quads for v in q)
    open(f'{out}/stage.bin', 'wb').write(blob)
    open(f'{out}/stage_pats.bin', 'wb').write(pats_blob)
    open(f'{out}/stage_quads.bin', 'wb').write(quads_blob)
    # Decode it back as the engine does (stream_line) and compare.
    pnum_pat = {n: pce_pats[p] for p, n in pat_num.items()}
    for c, (ups, bat) in enumerate(records):
        o = blob[3 * c] * 8192 + (blob[3 * c + 1] | blob[3 * c + 2] << 8) - 0x6000
        n, y = blob[o + 5], o + 6
        got = []
        for _ in range(n):
            b0, b1, b2 = blob[y:y + 3]
            got.append(((b2 & 7) << 8 | b0, pats_blob[((b2 >> 3) << 8 | b1) * 32:][:32]))
            y += 3
        assert got == [(sl, pce_pats[p]) for sl, p in ups], f'line {c} uploads'
        words, last = [], None
        while len(words) < 64:
            code = blob[y]
            y += 1
            if code < QUAD_SHORT:
                last = code
                words += quads[last]
            elif code < 0xF0:
                words += quads[last] * ((code & 15) + 1)
            else:
                last = (code & 15) << 8 | blob[y]
                y += 1
                words += quads[last]
        assert words == list(bat), f'line {c} BAT'
    raw = sum(6 + 34 * len(u) + 128 for u, _ in records) + table_size
    total = len(blob) + len(pats_blob) + len(quads_blob)
    print(f'stage: lines {len(blob)} + patterns {len(pats_blob)} ({len(pat_num)}) + quads {len(quads_blob)}'
          f' ({len(quads)}) = {total} bytes, {raw / total:.2f}x smaller than raw ({raw}); {n_up} uploads')

    for k, name in ((0, 'palette.bin'), (1, 'palette_castle.bin')):
        c0, pals_k, _ = psets[k]
        vce = bytearray()
        for i in range(16):
            cols = [unpack(c0)] + ([unpack(c) for c in pals_k[i]] if i < len(pals_k) else [])
            cols += [(0, 0, 0)] * (16 - len(cols))
            for r, g, b in cols:
                vce += ((g << 6) | (r << 3) | b).to_bytes(2, 'little')
        open(f'{out}/{name}', 'wb').write(vce)

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
        nsky = len(sky_col)
        cols = [c - seg0 * 64 for c in sky_col]
        assert all(0 <= c < W for c in cols)
        f.write(f'DYN_SKY_N\t= {nsky}\t; the sky\'s steps; streaming past dyn_sky_col[k] begins step k\n')
        f.write('dyn_sky_col:\tdw\t' + ', '.join(str(c) for c in cols + [0xFFFF]) + '\n')
        f.write('dyn_sky_l:\tdb\t' + ', '.join(f'<dyn_sky{k}' for k in range(nsky)) + '\n')
        f.write('dyn_sky_h:\tdb\t' + ', '.join(f'>dyn_sky{k}' for k in range(nsky)) + '\n')
        for s_ in range(4):
            pairs = [(a, word9(dyn_states[i][s_])) for i in slots if len(dyn_states[i]) == 4 for a in slots[i]]
            f.write(vce_list(f'dyn_cycle{s_}', pairs))
        for s_ in range(nsky):
            pairs = [(a, word9(dyn_states[i][s_])) for i in slots if len(dyn_states[i]) == nsky for a in slots[i]]
            f.write(vce_list(f'dyn_sky{s_}', pairs))
    print(f'dynamic slots: ' + ', '.join(f'{i}:{len(v)}' for i, v in sorted(slots.items())))
    with open(f'{out}/stage.inc', 'w') as f:
        f.write(f'STAGE_LINES = {W}\nSTAGE_BANKS = {(len(blob) + 8191) // 8192}\n')
        f.write(f'STAGE_PAT_BANKS = {(len(pats_blob) + 8191) // 8192}\t; stage_pats.bin: 256 patterns a bank\n')
        f.write(f'STAGE_QUAD_BANKS = {(len(quads_blob) + 8191) // 8192}\t; stage_quads.bin: 1024 quads a bank\n')
        f.write(f'QUAD_SHORT = ${QUAD_SHORT:02X}\t; quad codes below this are the quad # itself\n')
        f.write(f'STAGE_LEAD_X = {world.LEAD}\t; a column streams once scroll_x + this reaches it\n')
        f.write(f'STAGE_LEAD_Y = {world.LEAD_Y}\t; a row streams once scroll_y - this reaches it\n')
        regions.append(world.BOX_END + (1,))
        f.write(f'STAGE_REGION_END = {len(regions) - 1}\n')
        f.write(f'STAGE_ROW_REACH = {world.ROW_REACH}\t; scroll_y <= last row streamed + this\n')
        f.write(f'STAGE_COL_REACH = {world.COL_REACH}\t; scroll_x >= last column streamed - this\n')
        x0, x1, y = world.CAMERA_REST
        f.write(f'CAM_REST_X0 = {x0}\nCAM_REST_X1 = {x1}\nCAM_REST_Y = {y}\t; the lava hall (world.CAMERA_REST)\n')
        f.write(f'CASTLE_X = {world.square_origin(CASTLE_SEG)[0]}\t; from here on the castle\'s palettes\n')
        f.write(f'FIRE_X0 = {FIRE_X0}\nFIRE_X1 = {FIRE_X1}\nFIRE_TILE0 = ${FIRE_TILE0:03X}\t; the lava hall\'s fire\n')
        f.write(f'STAGE_DOOR_LINE = {next(i for i, ln in enumerate(lines) if ln["stop"])}\t; the boss room door\'s line\n')
    with open(f'{out}/stage_regions.inc', 'w') as f:
        f.write('; Generated by tools/pce_stage.py.\n')
        f.write('; Camera boxes per region (the region of the next line to stream): x0, x1, y0, y1;\n')
        f.write('; region_free: 1 in a shaft (scroll_x follows Rastan both ways), else scroll_x only grows.\n')
        f.write('region_free:\tdb\t' + ', '.join(str(r[4]) for r in regions) + '\n')
        for k, name in enumerate(('x0', 'x1', 'y0', 'y1')):
            f.write(f'region_{name}_l:\tdb\t' + ', '.join(f'${r[k] & 0xff:02X}' for r in regions) + '\n')
            f.write(f'region_{name}_h:\tdb\t' + ', '.join(f'${(r[k] >> 8) & 0xff:02X}' for r in regions) + '\n')

    # Previews of the world (origin at world (0, PREVIEW_Y0)): as the PCE shows it and the arcade.
    x0s, y0s = [], []
    for s in world.ORDER:
        ox, oy = world.square_origin(s)
        x0s.append(ox)
        y0s.append(oy)
    PW, PY0 = max(x0s) + 512, min(y0s)
    PH = max(y0s) + 512 - PY0
    prev = np.zeros((PH, PW, 3), np.uint8)
    arc = np.zeros((PH, PW, 3), np.uint8)
    def to8(pw):
        ref = np.array(pw, dtype=np.int32)
        rr, gg, bb = ref & 31, (ref >> 5) & 31, (ref >> 10) & 31
        return (np.stack([rr, gg, bb], 1) * 255 // 31).astype(np.uint8)
    ref8s = (to8(pal), to8(cpal), to8(hpal))
    for c, ln in enumerate(lines):
        ox, oy = world.square_origin(ln['seg'])
        for r in range(ROWS):
            ty, tx = (ln['i'], r) if ln['row'] else (r, ln['i'])
            y, x = oy - PY0 + ty * 8, ox + tx * 8
            p = pat_list[colpat[r, c]]
            k = int(castle[c])
            prev[y:y + 8, x:x + 8] = (psets[k][2][colpal[r, c]][p] * 255 // 7)
            arc[y:y + 8, x:x + 8] = ref8s[2 if hall[c] else k][idx[r, c]]
    if fire:
        hx0, hy0 = world.square_origin(HALL_SEG)
        for k in range((FIRE_X1 - FIRE_X0) // 8):
            j, tx = divmod(k, 4)
            for ty in range(4):
                pos = ty * 4 + tx
                pix = fire['pix'][(j % 2) * 16 + pos]
                y, x = FIRE_Y - PY0 + ty * 8, FIRE_X0 + k * 8
                prev[y:y + 8, x:x + 8] = psets[1][2][fire['pal'][pos]][pix] * 255 // 7
    Image.fromarray(prev).save(f'{out}/preview.png')
    Image.fromarray(arc).save(f'{out}/arcade.png')
    with open(f'{out}/stage.inc', 'a') as f:
        f.write(f'PREVIEW_Y0 = {PY0}\t; world y of preview.png row 0\n')


if __name__ == '__main__':
    main()
