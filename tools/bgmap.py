"""Static decode of Rastan's BG (PC080SN layer 0) from the program ROM.

$3951C: list of 6-byte entries [attr word][long ptr to strip]. A strip is
64 rows x 16 columns of tile-code words (row stride 32 bytes). Each FG segment
(512 px) owns 2 entries (BG scrolls at half speed). Segment -> first entry
index*2 via table $507C5 (byte), see $050394.
"""
import numpy as np

BG_TABLE = 0x3951C
SEG_TO_BG = 0x507C5


def w16(rom, a):
    return (rom[a] << 8) | rom[a + 1]


def bg_entry(rom, i):
    a = BG_TABLE + i * 6
    return w16(rom, a), (w16(rom, a + 2) << 16) | w16(rom, a + 4)


def strip_codes(rom, ptr):
    a = np.frombuffer(rom, ">u2", count=64 * 16, offset=ptr)
    return a.reshape(64, 16).copy()


def bg_tilemap(rom, first_entry, n_entries):
    """codes[64, 16n], attrs[64, 16n] for consecutive BG entries."""
    codes = np.zeros((64, 16 * n_entries), np.uint16)
    attrs = np.zeros_like(codes)
    for k in range(n_entries):
        attr, ptr = bg_entry(rom, first_entry + k)
        codes[:, k * 16:(k + 1) * 16] = strip_codes(rom, ptr)
        attrs[:, k * 16:(k + 1) * 16] = attr
    return codes, attrs


def segment_bg_entry(rom, segment):
    return rom[SEG_TO_BG + segment] * 2
