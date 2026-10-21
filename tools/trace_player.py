"""trace_player.py rom frames [from to pad]... : run the ROM headless and print the
player's position, state and pose plus the camera, read from RAM each frame.
Addresses come from src/main.lst, so the trace follows the code."""
import os
import re
import subprocess
import sys

TGRUN = os.path.join(os.path.dirname(__file__), 'tgrun', 'tgrun')
LST = os.path.join(os.path.dirname(__file__), '..', 'src', 'main.lst')
NAMES = ['scroll_x', 'scroll_y', 'p_x', 'p_y', 'p_face', 'p_state', 'p_pose', 'p_jidx', 'p_jfall']


def symbols():
    out = {}
    for ln in open(LST):
        m = re.match(r'\s*\d+\s+F8:(20[0-9A-F]{2})\s+(\w+):', ln)
        if m and m.group(2) in NAMES:
            out[m.group(2)] = int(m.group(1), 16) - 0x2000
    return out


def trace(rom, frames, inputs):
    sym = symbols()
    hi = max(sym.values()) + 2
    r = subprocess.run([TGRUN, rom, str(frames), '/dev/null'] + [str(a) for a in inputs],
                       env=dict(os.environ, TGRUN_PEEK=f'0,{hi}'), capture_output=True, text=True, check=True)
    rows = []
    for ln in r.stdout.splitlines():
        f, rest = ln.split(':')
        b = [int(v, 16) for v in rest.split()]
        w = lambda n: b[sym[n]] | b[sym[n] + 1] << 8
        rows.append(dict(frame=int(f), x=w('p_x'), y=w('p_y'), face=b[sym['p_face']], state=b[sym['p_state']],
                         pose=b[sym['p_pose']], sx=w('scroll_x'), sy=w('scroll_y'),
                         jidx=b[sym['p_jidx']], jfall=b[sym['p_jfall']]))
    return rows


if __name__ == '__main__':
    rows = trace(sys.argv[1], int(sys.argv[2]), sys.argv[3:])
    prev = None
    for r in rows:
        key = (r['state'], r['pose'], r['face'])
        if key != prev or r['frame'] % 30 == 0:
            print('{frame:5d}  p=({x},{y}) face {face} state {state} pose {pose:2d}  jump {jidx}/{jfall}  '
                  'scroll=({sx},{sy})'.format(**r))
            prev = key
