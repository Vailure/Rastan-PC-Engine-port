"""swarm_budget.py god.pce [cp] [frames] : how often the hurry-up swarm's bats go undrawn.

Rastan waits (from a debug-menu warp to checkpoint cp, or the round start) until the swarm
comes, then swings at it. Per frame: the bats on the screen (sw_st, positions), those with a
SATB entry, and those the VDC drops on some line (more than 16 sprite units before them).
"""
import os
import subprocess
import sys
import numpy as np
from peek import peek
from trace_player import TGRUN
from routes import warp

tmp = os.environ.get('TMPDIR', '/tmp')
BAT_PATS = (0x4A80 >> 5, 0x4AC0 >> 5, 0x76C0 >> 5)


def satb_frames(rom, frames, keys):
    out = os.path.join(tmp, f'swb_{os.getpid()}.bin')
    subprocess.run([TGRUN, rom, str(frames), '/dev/null'] + [str(k) for k in keys],
                   env=dict(os.environ, TGRUN_SATB=out), check=True, capture_output=True)
    d = np.fromfile(out, '<u2').reshape(-1, 64, 4)
    os.remove(out)
    return d


def lost_entries(t):
    """SATB indices that lose a line to the 16-units limit while on the screen."""
    y = (t[:, 0] & 0x3FF).astype(int) - 64
    x = (t[:, 1] & 0x3FF).astype(int) - 32
    attr = t[:, 3].astype(int)
    cgy = (attr >> 12) & 3
    h = np.where(cgy == 0, 16, np.where(cgy == 1, 32, 64))
    wide = (attr >> 8) & 1
    units, width = 1 + wide, 16 << wide
    lost = set()
    for line in range(224):
        on = np.nonzero((y <= line) & (line < y + h))[0]
        used = 0
        for i in on:
            used += units[i]
            if used > 16 and x[i] + width[i] > 0 and x[i] < 256:
                lost.add(int(i))
    return lost


def on_screen(a, s16):
    """Bats swarm_draw would emit (sw_emit's test: -16 < x < 256, -16 < y < 240)."""
    sx, sy = s16(*a['scroll_x']), s16(*a['scroll_y'])
    n = 0
    for k in range(9):
        st = a['sw_st'][k]
        if not st:
            continue
        if st == 15:                                  # killed: cell $276 at (-8, -8)
            dx = dy = -8
        else:                                         # flapping
            dy = (-8, -6, 0, -6)[(a['p_frame'][0] >> 2) & 3]
            dx = -9 if a['sw_flip'][k] else -8
        x = s16(a['sw_xl'][k], a['sw_xh'][k]) - sx + dx
        y = s16(a['sw_yl'][k], a['sw_yh'][k]) - sy + dy
        n += -16 < x < 256 and -16 < y < 240
    return n


def measure(rom, cp=0, frames=3400):
    """{'want', 'got', 'shown', 'short', 'others', 'others_lost', 'full'}: bat-frames on the
    screen, with a SATB entry, whole on every line; frames short of one; the other entries
    meanwhile, those of them losing a line, pieces left out for want of entries."""
    keys = warp(cp) + sum([[f, f + 1, '80'] for f in range(frames - 400, frames, 12)], [])
    r = peek(rom, frames, keys, {'sw_st': 9, 'sw_xl': 9, 'sw_xh': 9, 'sw_yl': 9, 'sw_yh': 9, 'sw_flip': 9,
                                 'scroll_x': 2, 'scroll_y': 2, 'p_frame': 1, 'en_full': 1})
    satb = satb_frames(rom, frames, keys)
    s16 = lambda lo, hi: ((lo | hi << 8) ^ 0x8000) - 0x8000
    want = got = shown = frames_short = others = others_lost = full = 0
    for f in range(1, min(len(r), len(satb))):
        n = on_screen(r[f - 1], s16)                  # (the SATB built in frame f - 1)
        if not n:
            continue
        t = satb[f]
        bats = [i for i in range(64) if (t[i, 2] & 0x7FF) >> 1 << 1 in BAT_PATS and t[i, 0]]
        lost = lost_entries(t)
        want += n
        full += (r[f]['en_full'][0] - r[f - 1]['en_full'][0]) & 0xFF
        rest = [i for i in range(64) if t[i, 0] and i not in bats]
        others += len(rest)
        others_lost += sum(1 for i in rest if i in lost)
        got += len(bats)
        shown += sum(1 for i in bats if i not in lost)
        frames_short += len(bats) < n or any(i in lost for i in bats)
    return dict(want=want, got=got, shown=shown, short=frames_short, others=others,
                others_lost=others_lost, full=full)


def main():
    rom = sys.argv[1]
    cp = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    frames = int(sys.argv[3]) if len(sys.argv) > 3 else 3400
    m = measure(rom, cp, frames)
    pc = lambda k: f"{m[k]} ({100 * m[k] / max(m['want'], 1):.1f}%)"
    print(f"bat-frames on screen {m['want']}, with a SATB entry {pc('got')}, whole on every line {pc('shown')}, "
          f"frames short {m['short']}; meanwhile other entries {m['others']}, of them losing a line "
          f"{m['others_lost']}, pieces left out (SATB full) {m['full']}")


if __name__ == '__main__':
    main()
