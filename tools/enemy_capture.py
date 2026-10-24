"""Capture group-A object poses from simulator snapshots.

Objects: 64-byte slots at $10C2C0 (9 slots). +$08 active, +$09 animation frame,
+$0D state, +$1E x, +$22 y (screen coordinates, like the player).
Slot k (0-8) draws with hardware sprite entries 140+10k .. 149+10k (block k - 1), so
its pieces can be read exactly, even when objects overlap.
"""
from snap import read_snaps


def block_pieces(s, blk, x, y):
    pieces = []
    for i in range(150 + 10 * blk, 160 + 10 * blk):
        d0, py, code, px = (int(v) for v in s.spr[i * 4:i * 4 + 4])
        code &= 0x1fff; px &= 0x1ff; py &= 0x1ff
        if not code:
            continue
        if px > 0x140: px -= 0x200
        if py > 0x140: py -= 0x200
        if py - y < -100:          # parked off-screen
            continue
        pieces.append((d0 & 0xc00f, py - y, code, px - x))
    return pieces


def slot_pieces(s, k):
    """Pieces of slot k: its own 10-entry block (slot k draws block k - 1), else
    the block that best matches its position."""
    b = 0x10c2c0 + k * 0x40
    x, y = s.w(b + 0x1e), s.w(b + 0x22)
    p = block_pieces(s, k - 1, x, y)
    if p:
        return p
    best, best_d = [], None
    for blk in range(9):
        p = block_pieces(s, blk, x, y)
        if not p:
            continue
        cx = sum(q[3] for q in p) / len(p) + 8
        cy = sum(q[1] for q in p) / len(p) + 8
        d = abs(cx) + abs(cy + 16)
        if best_d is None or d < best_d:
            best, best_d = p, d
    return best if best_d is not None and best_d < 40 else []


def capture(paths, keyfn=lambda anim, st: (anim, st)):
    found = {}
    for fn in paths:
        for s in read_snaps(fn):
            if s.w(0x10c002) != 3:
                continue
            for k in range(9):
                b = 0x10c2c0 + k * 0x40
                o = b - 0x10c000
                if not s.wram[o + 8] or s.w(b + 0x22) >= 300:
                    continue
                key = keyfn(s.wram[o + 9], s.wram[o + 0xd])
                if key in found:
                    continue
                p = slot_pieces(s, k)
                if p:
                    found[key] = dict(file=fn, frame=s.frame, slot=k, pieces=p, sprctrl=s.sprctrl, pal=s.pal)
    return found
