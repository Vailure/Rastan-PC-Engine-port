"""Static extraction of Rastan's (player) metasprite frames from the program ROM.

The player is drawn from three parts, each up to 4 PC090OJ 16x16 cells
(builders at $054492, $054598, $0546A8):
  body    table $5BD40, frame index ($1244,A5)  -> sprite buffer $10D1D2
  weapon  table by weapon type ($12FA,A5):      -> sprite buffer $10D1B2
            1 $5CD8A, 4 $5D068, 2 $5D346, 3 $5D666; frame index ($1244,A5)
  legs    table $5C466, frame index ($1246,A5)  -> sprite buffer $10D1F2
Table: word offsets (relative to table start) per frame, then frames of
4 x 6-byte cells: [code word][dx byte][dy byte][attr word]. code 0 ends a frame.
Screen position: x = obj_x + dx (facing right, $1114 == 2), y = obj_y + dy + 1.
When facing left, the cell is X-flipped and x = obj_x - dx - 16.
"""
import numpy as np

PARTS = {
    'body': 0x5BD40,
    'legs': 0x5C466,
    'sword': 0x5CD8A,     # weapon type 1 (default)
    'weapon4': 0x5D068,
    'weapon2': 0x5D346,
    'weapon3': 0x5D666,
}


def w16(rom, a):
    return (rom[a] << 8) | rom[a + 1]


def s8(v):
    return v - 256 if v & 0x80 else v


def frames(rom, table):
    """List of frames; each is a list of (code, dx, dy, attr)."""
    first = w16(rom, table)
    n = first // 2
    out = []
    for i in range(n):
        a = table + w16(rom, table + 2 * i)
        cells = []
        for k in range(4):
            code = w16(rom, a)
            if code == 0:
                break
            cells.append((code, s8(rom[a + 2]), s8(rom[a + 3]), w16(rom, a + 4)))
            a += 6
        out.append(cells)
    return out
