"""track.py run.snp slot first last [lo-hi cell range] : one arcade object slot over time.

Prints a line whenever the slot's pose, state (+$0D) or animation byte (+$09) changes:
frame, state, anim, pose id, piece count, position (screen), Rastan's position, and the
step in x/y since the last line. Poses are numbered in order of first appearance and
listed at the end with their cells. Needs snapshots with the .own sidecar.
"""
import sys
from snap import read_snaps


def pieces(s, k):
    b = 0x10c2c0 + k * 64
    x, y = s.w(b + 0x1e), s.w(b + 0x22)
    out = []
    for e in range(256):
        if s.owner[e] != k:
            continue
        d0, py, code, px = (int(v) for v in s.spr[e * 4:e * 4 + 4])
        code &= 0x1fff
        if code:
            out.append((d0 & 0xc00f, ((py - y + 256) & 511) - 256, code, ((px - x + 256) & 511) - 256))
    return tuple(sorted(out)), x, y


def main():
    path, k, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    lo, hi = (int(v, 16) for v in sys.argv[5].split('-')) if len(sys.argv) > 5 else (0, 0x2000)
    poses, prev, last = {}, None, None
    for s in read_snaps(path):
        if not a <= s.frame <= b:
            continue
        p, x, y = pieces(s, k)
        if p and not any(lo <= q[2] < hi for q in p):
            p = ()
        o = 0x2c0 + k * 64
        st, an = s.wram[o + 0xd], s.wram[o + 9]
        pid = poses.setdefault(p, len(poses)) if p else -1
        key = (pid, st, an)
        if key != prev:
            dx = x - last[0] if last else 0
            dy = y - last[1] if last else 0
            print(f'{s.frame:5d} state {st:02x} anim {an:02x} pose {pid:3d} ({len(p):2d} pieces) at ({x:4d},{y:4d}) '
                  f'step ({dx:+d},{dy:+d})  rastan ({s.w(0x10d0be)},{s.w(0x10d0c0)})')
            prev, last = key, (x, y)
    for p, i in poses.items():
        print(f'pose {i}: ' + ' '.join(f'{q[2]:03x}' for q in p))


if __name__ == '__main__':
    main()
