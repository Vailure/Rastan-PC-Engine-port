"""census_all.py out.pkl run.snp [...] : every arcade object, all slots, with its exact sprite pieces.

Needs snapshots written every frame by sim/sim, with the .own sidecar (sprite entry -> slot).
Objects live in 64-byte slots from $10C2C0 (+$08 active, +$09 anim, +$0D state, +$15 type,
+$1E x, +$22 y, screen coordinates). An object's pieces are the sprite entries its slot wrote this
frame, relative to (x, y). A "kind" is (first sprite cell >> 4, main palette) of the pieces at the
object's first drawn frame. Camera x is unwrapped from the FG scroll register (see object_census.py).

The pickle holds {'kinds': {key: info}, 'tracks': [track]} where a track is one object's life:
kind, slot, file, frames [(frame, world x, world y, anim, state, pieces)].
"""
import pickle
import sys
from snap import read_snaps

NSLOTS = 40


def pieces_of(s, k, x, y):
    out = []
    for e in range(256):
        if s.owner[e] != k:
            continue
        d0, py, code, px = (int(v) for v in s.spr[e * 4:e * 4 + 4])
        code &= 0x1fff
        px &= 0x1ff
        py &= 0x1ff
        if not code:
            continue
        dx, dy = px - x, py - y
        dx = (dx + 256) % 512 - 256          # wrap into -256..255
        dy = (dy + 256) % 512 - 256
        out.append((d0 & 0xc00f, dy, code, dx))
    return out


def run(paths):
    tracks = []
    for path in paths:
        live = {}
        cam = prev_reg = None
        for s in read_snaps(path):
            if s.owner is None:
                raise SystemExit(f'{path}: no .own sidecar (rerun sim/sim)')
            if s.w(0x10c002) != 3:
                live, cam, prev_reg = {}, None, None
                continue
            reg = s.scrx[1]
            if prev_reg is None:
                cam = (s.w(0x10c13e) - 1) * 512 + ((-reg) & 0x1ff)
            else:
                cam += ((prev_reg - reg + 256) & 0x1ff) - 256
            prev_reg = reg
            camy = (-s.scry[1]) & 0x1ff
            for k in range(NSLOTS):
                b = 0x10c2c0 + k * 64
                o = b - 0x10c000
                x, y = s.w(b + 0x1e), s.w(b + 0x22)
                x = x - 0x10000 if x & 0x8000 else x
                y = y - 0x10000 if y & 0x8000 else y
                p = pieces_of(s, k, x, y)
                if not p:
                    if k in live:
                        tracks.append(live.pop(k))
                    continue
                codes = sorted(q[2] for q in p)
                if k not in live:
                    cols = [q[0] & 15 for q in p]
                    key = (codes[0] >> 4, max(set(cols), key=cols.count))
                    live[k] = dict(kind=key, slot=k, file=path, type=s.wram[o + 0x15], frames=[],
                                   seg=s.w(0x10c13e), bank=(s.sprctrl & 0xe0) >> 1, pal=bytes(s.pal.tobytes()))
                live[k]['frames'].append((s.frame, x + 16 + cam, (y + camy) & 0x1ff, s.wram[o + 9], s.wram[o + 0xd], p,
                                          s.w(0x10d0be) + 16 + cam, (s.w(0x10d0c0) + camy) & 0x1ff))
        tracks += live.values()
    kinds = {}
    for t in tracks:
        kd = kinds.setdefault(t['kind'], dict(n=0, segs=set(), files=set()))
        kd['n'] += 1
        kd['segs'].add(t['seg'])
        kd['files'].add(t['file'])
    return dict(kinds=kinds, tracks=tracks)


if __name__ == '__main__':
    out = run(sys.argv[2:])
    pickle.dump(out, open(sys.argv[1], 'wb'))
    for key, v in sorted(out['kinds'].items(), key=lambda kv: min(kv[1]['segs'])):
        print(f'kind cells {key[0] << 4:03x} color {key[1]:2d}: {v["n"]:3d} objects, segments {sorted(v["segs"])}')
