"""Load and decode Rastan arcade ROM regions (layouts from MAME taito/rastan.cpp)."""
import os
import numpy as np

# (region, [(file, offset, size, interleave16)])
REGIONS = {
    "maincpu": [("b04-38.19", 0x00000, 0x10000, 0), ("b04-37.7", 0x00001, 0x10000, 1),
                ("b04-40.20", 0x20000, 0x10000, 0), ("b04-39.8", 0x20001, 0x10000, 1),
                ("b04-42.21", 0x40000, 0x10000, 0), ("b04-43-1.9", 0x40001, 0x10000, 1)],
    "pc080sn": [("b04-01.40", 0x00000, 0x20000, 0), ("b04-02.67", 0x00001, 0x20000, 1),
                ("b04-03.39", 0x40000, 0x20000, 0), ("b04-04.66", 0x40001, 0x20000, 1)],
    "pc090oj": [("b04-05.15", 0x00000, 0x20000, 0), ("b04-06.28", 0x00001, 0x20000, 1),
                ("b04-07.14", 0x40000, 0x20000, 0), ("b04-08.27", 0x40001, 0x20000, 1)],
    "audiocpu": [("b04-19.49", 0, 0x10000, None)],
    "adpcm": [("b04-20.76", 0, 0x10000, None)],
}
SIZES = {"maincpu": 0x60000, "pc080sn": 0x80000, "pc090oj": 0x80000,
         "audiocpu": 0x10000, "adpcm": 0x10000}


def load_region(romdir, name):
    out = bytearray(SIZES[name])
    for fn, off, size, il in REGIONS[name]:
        data = open(os.path.join(romdir, fn), "rb").read()
        assert len(data) == size, fn
        if il is None:
            out[off:off + size] = data
        else:  # ROM_LOAD16_BYTE: every other byte
            base = off & ~1
            out[base + il: base + il + 2 * size: 2] = data
    return bytes(out)


def decode_packed(region, w, h):
    """gfx_WxHx4_packed_msb: 4bpp, row-major, high nibble = left pixel."""
    a = np.frombuffer(region, dtype=np.uint8)
    hi, lo = a >> 4, a & 0xF
    px = np.stack([hi, lo], axis=1).reshape(-1)
    n = len(px) // (w * h)
    return px[: n * w * h].reshape(n, h, w)


def xbgr555(word):
    """Palette word -> (r,g,b) 8-bit. Palette RAM 0x200000, 2048 entries."""
    r = word & 0x1F
    g = (word >> 5) & 0x1F
    b = (word >> 10) & 0x1F
    return ((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2))
