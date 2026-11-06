"""object_census.py run.snp [...] : list the arcade's object spawns with world positions.

Objects live in 9 slots of 64 bytes at $10C2C0 (+$09 variant/frame, +$0D state,
+$15 type, +$1E x, +$22 y in screen coordinates; y >= 300 means parked off-screen).
A spawn is a slot coming on screen. The FG scroll register only holds 9 bits, so the
camera position is unwrapped frame by frame (snapshots must be every 1-2 frames).
World x follows the port's convention: world = screen x + 16 - FG scroll.
"""
import sys
from snap import read_snaps
from enemy_capture import slot_pieces

TYPES = {0x33: 'lizardman', 0x17: 'item?', 0x48: 'block?'}


def census(path):
    events = []
    cam = None
    prev_reg = None
    prev_on = [False] * 9
    for s in read_snaps(path):
        if s.w(0x10c002) != 3:
            prev_reg, cam, prev_on = None, None, [False] * 9
            continue
        reg = s.scrx[1]
        if prev_reg is None:
            # First gameplay frame: the segment counter runs one ahead of the screen
            # (it is 1 at the start of the round).
            cam = (s.w(0x10c13e) - 1) * 512 + ((-reg) & 0x1ff)
        else:
            d = ((prev_reg - reg + 256) & 0x1ff) - 256   # register decreases as the camera moves right
            cam += d
        prev_reg = reg
        for e in events:                  # sprite palette, a few frames after the spawn
            if e.get('color') is None and s.frame >= e['frame'] + 4 and e['frame'] + 30 > s.frame:
                p = slot_pieces(s, e['slot'])
                if p:
                    cols = [q[0] & 0xf for q in p]
                    e['color'] = max(set(cols), key=cols.count)
        for k in range(9):
            b = 0x10c2c0 + k * 0x40
            o = b - 0x10c000
            y = s.w(b + 0x22)
            on = y < 300
            if on and not prev_on[k]:
                x = s.w(b + 0x1e)
                if x > 0x8000:
                    x -= 0x10000
                px = s.w(0x10d0be)
                events.append(dict(frame=s.frame, slot=k, type=s.wram[o + 0x15], var=s.wram[o + 9],
                                   state=s.wram[o + 0xd], wx=x + 16 + cam, y=y, cam=cam,
                                   wy=(y - s.scry[1]) & 0x1ff,          # same mapping as Rastan's p_y
                                   px=px + 16 + cam,                     # Rastan's world x at the spawn
                                   seg=s.w(0x10c13e), color=None))
            prev_on[k] = on
    return events


if __name__ == '__main__':
    for path in sys.argv[1:]:
        print('==', path)
        for e in census(path):
            print('{frame:5d} seg {seg:2d} cam {cam:5d}  type {type:02x} {name:10s} var {var:02x} state {state:02x}'
                  '  world ({wx:5d},{wy:3d})  rastan x {px:5d}  color {color}  slot {slot}'.format(
                      name=TYPES.get(e['type'], '?'), **e))
