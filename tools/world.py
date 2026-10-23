"""Round 1 as a 2-D world of 512 px squares (the arcade streams some map segments as rows).

The arcade keeps a 512x512 window (FG tilemap and the collision copy at $10DE00)
and streams the map into it one 512 px segment (16 block columns) at a time.
A byte per segment (table from $50F6C, read at $0558E0 into $10D0A8) says how:
0 streams block columns to the right; 1 streams block rows upwards, map column
k of the segment becoming the k-th block row above, map row r becoming block
column r ($055990/$055A14). 4 and 6 are transitions: the camera stops and the
next room is loaded whole (4: the castle gate, when Rastan reaches screen x
$D8; 6: the door at the top of the second castle shaft, into the boss room).

Round 1 (map segments of 512 px):
  $00-$10  horizontal, world row 0. Between $0F and $10 the arcade's castle
           gate (a door, $7E) takes Rastan into $10; here the squares also
           join, as the PCE build has always scrolled in.
  $11      a shaft upwards, above $10
  $12-$14  horizontal, right of the shaft's top
  $15      a shaft upwards, above $14
  $16      the boss room, through the door: placed at its map position on
           world row 0, so that map x = world x there (the arcade streams $17
           as well, but its camera stays in $16).

World y grows downwards and is negative above row 0.

The PCE streams the world as a sequence of 64-tile lines (a column of a
horizontal square, a row of a shaft) into its 64x64 BAT, in play order.
Every line has a trigger: a column at world x streams once
scroll_x + LEAD >= x, a row at world y once scroll_y - LEAD_Y <= y. The camera
is held inside a box that depends on the next line to stream (the arcade's
streaming mode decides which way it may scroll in the same way).
"""
import numpy as np
from fgmap import fg_blocks, block_tiles, block_collision

H, UP = 'H', 'UP'
LEAD = 33 * 8           # a column at x streams once scroll_x + LEAD >= x
LEAD_Y = 32             # a row at y streams once scroll_y - LEAD_Y <= y (just in time: the BAT
                        # rows it takes over are those of the square below)
SCREEN_W, SCREEN_H = 256, 224
ROW_REACH = 512 - SCREEN_H     # scroll_y stays <= (y of the last row streamed) + this
COL_REACH = 512 - 8            # scroll_x stays >= (x of the last column streamed) - this

# map segment -> (square x, square y, orientation), in play order
LAYOUT = {s: (s, 0, H) for s in range(0x11)}
LAYOUT.update({0x11: (0x10, -1, UP), 0x12: (0x11, -1, H), 0x13: (0x12, -1, H), 0x14: (0x13, -1, H),
               0x15: (0x13, -2, UP), 0x16: (0x16, 0, H)})
DOOR_TO = 0x16          # the door at the top of shaft 2 leads here
# Camera boxes (x0, x1, y0, y1 of scroll_x/scroll_y) while a segment's lines are next.
BOXES = {}
for s in range(0x11):
    BOXES[s] = (0, 0x10 * 512 + 512 - SCREEN_W, 0, 512 - SCREEN_H)
BOXES[0x11] = (0x10 * 512, 0x10 * 512 + 512 - SCREEN_W, -512, 512 - SCREEN_H)
for s in (0x12, 0x13, 0x14):
    BOXES[s] = (0x10 * 512, 0x13 * 512 + 512 - SCREEN_W, -512, -SCREEN_H)
BOXES[0x15] = (0x13 * 512, 0x13 * 512 + 512 - SCREEN_W, -1024, -SCREEN_H)
BOX_END = (0x16 * 512, 0x16 * 512 + 512 - SCREEN_W, 0, 512 - SCREEN_H)   # the boss room: square $16
BOXES[0x16] = BOX_END
ORDER = sorted(LAYOUT)
# Where the arcade holds the camera lower than following Rastan would: the lava
# hall (squares $12, $13), whose fire fills the bottom of its screen. Its camera
# stays at world y -457 there (hall.snp, census camy 55), so the 240 lines it shows
# (from line 8) are -449..-210; the PC Engine's 224 centred on the same middle start
# at -441. While Rastan is in x0..x1, the camera sinks toward that y as far as his
# head (8 px below the top) allows. (x0, x1, scroll_y)
CAMERA_REST = (0x11 * 512, 0x13 * 512, -441)
# Segments whose camera follows Rastan both ways (the shafts, and the boss room the
# arcade's camera pans across).
FREE = {s for s, v in LAYOUT.items() if v[2] == UP} | {0x16}


def square_blocks(m, orient):
    """[16, 16] of a segment's block-level map m in world orientation (rows top-down)."""
    if orient == H:
        return m
    return np.array([[m[r, 15 - row] for r in range(16)] for row in range(16)])


def square_tiles(rom, seg, cache={}):
    """(codes[64, 64], attrs[64, 64], collision[64, 64]) of a segment in world orientation."""
    if seg in cache:
        return cache[seg]
    attr, blk = fg_blocks(rom)
    orient = LAYOUT[seg][2]
    b = square_blocks(blk[:, seg * 16:seg * 16 + 16], orient)
    a = square_blocks(attr[:, seg * 16:seg * 16 + 16], orient)
    codes = np.zeros((64, 64), np.uint16)
    attrs = np.zeros((64, 64), np.uint16)
    coll = np.zeros((64, 64), np.uint16)
    for r in range(16):
        for c in range(16):
            codes[r * 4:r * 4 + 4, c * 4:c * 4 + 4] = block_tiles(rom, int(b[r, c]))
            attrs[r * 4:r * 4 + 4, c * 4:c * 4 + 4] = a[r, c]
            coll[r * 4:r * 4 + 4, c * 4:c * 4 + 4] = block_collision(rom, int(b[r, c]))
    cache[seg] = (codes, attrs, coll)
    return cache[seg]


def square_origin(seg):
    sx, sy, _ = LAYOUT[seg]
    return sx * 512, sy * 512


def lines():
    """Stream lines in play order: dicts with seg, row (bool), world pos (x of a column,
    y of a row), the square-local tile index i (column or row), trigger, flags."""
    out = []
    for seg in ORDER:
        x0, y0 = square_origin(seg)
        orient = LAYOUT[seg][2]
        for k in range(64):
            if orient == H:
                d = dict(seg=seg, row=False, i=k, pos=x0 + 8 * k, trigger=x0 + 8 * k)
            else:
                i = 63 - k                       # bottom row first
                d = dict(seg=seg, row=True, i=i, pos=y0 + 8 * i, trigger=y0 + 8 * i)
            d['stop'] = seg == DOOR_TO and k == 0
            # Camera box while this line is the next to stream; at the door, the shaft's.
            d['box'] = out[-1]['box'] if d['stop'] else BOXES[seg]
            out.append(d)
    return out


def camera_reach(lines):
    """For each line c: (x_lo, y_hi), bounds that scroll_x and scroll_y keep from the
    time line c has streamed on (until a door). The engine's camera rules:
      - in a horizontal square, scroll_x never decreases (and a column at x has
        streamed only once scroll_x >= x - LEAD);
      - in a shaft and in the boss room (FREE), scroll_x is free inside the box;
      - the BAT holds 512 px each way, so scroll_x never goes back past the last
        column streamed minus COL_REACH (a square's columns overwrite the BAT
        cells of the square 512 px before it);
      - scroll_y <= min(box y1, y of the last row streamed + 512 - SCREEN_H - LEAD_Y... )
        i.e. the rows a shaft took over from the square below never show.
    Boxes are those of world.BOXES for the segment of the next line."""
    n = len(lines)
    out = [None] * n
    xfwd = -10 ** 9
    xcol = -10 ** 9
    row_top = 10 ** 9
    for c, ln in enumerate(lines):
        if ln['stop']:
            row_top = 10 ** 9
            xcol = -10 ** 9
        if not ln['row']:
            xfwd = max(xfwd, ln['trigger'] - LEAD)
            xcol = ln['trigger'] - COL_REACH
        else:
            row_top = ln['pos']
        # Regions still to come (the next line's on): the lowest x0 of a shaft among them,
        # and the highest y1.
        lo_x, hi_y = xfwd, -10 ** 9
        stop = False
        for d in range(c + 1, n + 1):
            if d == n or lines[d]['stop']:
                box = BOX_END if d == n else lines[d]['box']
                hi_y = max(hi_y, box[3] if d > c + 1 else min(box[3], row_top + ROW_REACH))
                if d == n:
                    lo_x = min(lo_x, BOX_END[0])
                break
            box = lines[d]['box']
            if lines[d]['seg'] in FREE:
                lo_x = min(lo_x, box[0])
            yb = box[3] if d > c + 1 else min(box[3], row_top + ROW_REACH)
            hi_y = max(hi_y, yb)
        out[c] = (lo_x, hi_y)
    return out


def segment_at(x, y):
    """The segment whose square holds world (x, y), or None."""
    for s, (sx, sy, _) in LAYOUT.items():
        if sx * 512 <= x < sx * 512 + 512 and sy * 512 <= y < sy * 512 + 512:
            return s
    return None


def census_to_world(x, y, seg):
    """census_all coordinates -> world. census x is (streamed segment - 1) * 512 + the
    screen, y is wrapped to 0-511; seg is the streamed-segment count it was seen at.
    The camera's square is the one before the streamed segment (or the shaft being
    streamed, whose census x stays in the square below it)."""
    m = x // 512
    if m <= 0x10 or m >= 0x16:
        return x, y
    if m in (0x12, 0x13, 0x14):
        return x - 512, y - 512
    if m == 0x15:
        return x - 512, y - 1024
    return x, y            # m == 0x11 cannot happen: shaft 1 has census x in $10
