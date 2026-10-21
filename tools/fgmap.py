"""Static decode of Rastan's FG (PC080SN layer 1) world map from the program ROM.

Layout (from routines at $0502cc / $055904 / $0559b2):
  16 block rows; row r array at ROW_BASE + r*ROW_STRIDE, one 4-byte entry per
  32px block column: [attr word][block address word (ROM $0000-$FFFF)].
  Block = 4x4 tile codes (row-major words), +$20: collision info.
"""
import numpy as np

ROW_BASE, ROW_STRIDE, NROWS = 0x1691C, 0x22C0, 16
NCOLS = ROW_STRIDE // 4


def w16(rom, a):
    return (rom[a] << 8) | rom[a + 1]


def fg_blocks(rom):
    """attr[16, NCOLS], blk[16, NCOLS]"""
    a = np.frombuffer(rom, ">u2")
    attr = np.zeros((NROWS, NCOLS), np.uint16)
    blk = np.zeros((NROWS, NCOLS), np.uint16)
    for r in range(NROWS):
        base = (ROW_BASE + r * ROW_STRIDE) // 2
        e = a[base:base + NCOLS * 2].reshape(NCOLS, 2)
        attr[r], blk[r] = e[:, 0], e[:, 1]
    return attr, blk


def block_tiles(rom, addr):
    return np.array([[w16(rom, addr + r * 8 + c * 2) for c in range(4)] for r in range(4)])


def fg_tilemap(rom, col0=0, ncols=None):
    """Tile-level map: (codes[64, 4n], attrs[64, 4n]) for block columns col0..col0+n."""
    attr, blk = fg_blocks(rom)
    ncols = ncols or NCOLS - col0
    codes = np.zeros((64, ncols * 4), np.uint16)
    attrs = np.zeros((64, ncols * 4), np.uint16)
    cache = {}
    for r in range(NROWS):
        for c in range(ncols):
            b = int(blk[r, col0 + c])
            if b not in cache:
                cache[b] = block_tiles(rom, b)
            codes[r * 4:r * 4 + 4, c * 4:c * 4 + 4] = cache[b]
            attrs[r * 4:r * 4 + 4, c * 4:c * 4 + 4] = attr[r, col0 + c]
    return codes, attrs


def block_collision(rom, addr):
    """4x4 collision words for a block: +$20 == $FF -> uniform value at +$22,
    else a 4x4 row-major table at +$20 (see $0559B2). The game keeps a 64x64
    copy in RAM at $10DE00 (one word per 8x8 tile)."""
    if w16(rom, addr + 0x20) == 0xFF:
        return np.full((4, 4), w16(rom, addr + 0x22))
    return np.array([[w16(rom, addr + 0x20 + r * 8 + c * 2) for c in range(4)] for r in range(4)])


def fg_collision(rom, col0=0, ncols=None):
    """Collision words [64, 4n] per 8x8 tile for block columns col0..col0+n."""
    _, blk = fg_blocks(rom)
    ncols = ncols or NCOLS - col0
    out = np.zeros((64, ncols * 4), np.uint16)
    cache = {}
    for r in range(NROWS):
        for c in range(ncols):
            b = int(blk[r, col0 + c])
            if b not in cache:
                cache[b] = block_collision(rom, b)
            out[r * 4:r * 4 + 4, c * 4:c * 4 + 4] = cache[b]
    return out


def block_collision(rom, addr):
    """4x4 collision codes for a block (+$20: $FF then one code for all, or 16 codes)."""
    if w16(rom, addr + 0x20) == 0xFF:
        return np.full((4, 4), w16(rom, addr + 0x22), np.uint16)
    return np.array([[w16(rom, addr + 0x20 + r * 8 + c * 2) for c in range(4)] for r in range(4)], np.uint16)


def fg_collision(rom, col0=0, ncols=None):
    """Per-8x8-tile collision codes [64, 4n] for block columns col0..col0+n."""
    attr, blk = fg_blocks(rom)
    ncols = ncols or NCOLS - col0
    out = np.zeros((64, ncols * 4), np.uint16)
    cache = {}
    for r in range(NROWS):
        for c in range(ncols):
            b = int(blk[r, col0 + c])
            if b not in cache:
                cache[b] = block_collision(rom, b)
            out[r * 4:r * 4 + 4, c * 4:c * 4 + 4] = cache[b]
    return out
