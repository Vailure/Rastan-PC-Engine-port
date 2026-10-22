"""test_effects.py rom dyncolor.inc : waterfall and hazard checks (run on the no-enemy build).

Compared with the arcade (see README): the waterfall colors cycle every 8 frames
and nothing else changes; the sky switches once the column before segment 3 is
streamed; the waterfall's lip (collision code 8) kills, with the arcade's death
animation, and the restart costs a life.
"""
import os
import re
import subprocess
import sys
import numpy as np
from trace_player import trace, TGRUN

rom, inc = sys.argv[1], open(sys.argv[2]).read()
fails = []
tmp = os.environ.get('TMPDIR', '/tmp')


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


def slots(label):
    body = inc.split(label + ':')[1].split(':')[0]
    return {int(a, 16) for a in re.findall(r'dw\s+\$([0-9A-F]{3}),', body)}


def vce_after(frames, args=()):
    out = os.path.join(tmp, f'vce_{os.getpid()}.bin')
    subprocess.run([TGRUN, rom, str(frames), '/dev/null'] + [str(a) for a in args], check=True,
                   env=dict(os.environ, TGRUN_VCE=out), capture_output=True)
    return np.fromfile(out, '<u2')


cyc = slots('dyn_cycle0')
sky = slots('dyn_sky_a')
v = [vce_after(n) for n in (200, 208, 216)]
changed = [set(np.nonzero(a != b)[0].tolist()) for a, b in zip(v, v[1:])]
check('waterfall cycle: only its slots change, every 8 frames', all(c and c <= cyc for c in changed),
      f'{len(cyc)} slots, changed {[len(c) for c in changed]}')
seq = [vce_after(n) for n in range(200, 217)]
steps = [n for n in range(1, len(seq)) if (seq[n] != seq[n - 1]).any()]
check('waterfall cycle steps exactly every 8 frames', len(steps) == 2 and steps[1] - steps[0] == 8, f'steps at +{steps}')

# Rope route (hold RIGHT+UP, jump every second): passes the sky change, then
# meets the waterfall's lip.
args = ['60', '1700', '05']
for f in range(100, 1700, 60):
    args += [str(f), str(f + 3), '40']
start, later = vce_after(300, args), vce_after(1440, args)
diff = set(np.nonzero(start != later)[0].tolist()) - cyc
check('sky switches before segment 3', diff and diff <= sky, f'{len(diff & sky)} of {len(sky)} sky slots changed')

r = trace(rom, 1700, args)
dead = [x for x in r if x['state'] == 8]
check('the waterfall lip kills (death animation)', bool(dead) and 1824 <= dead[0]['x'] <= 1983,
      f"died at x {dead[0]['x'] if dead else None}")
poses = sorted({x['pose'] for x in dead})
check('death animation plays its poses', len(poses) >= 8, f'{len(poses)} poses, {len(dead)} frames')
check('after dying, the stage restarts', any(x['x'] == 48 for x in r[r.index(dead[-1]):]) if dead else False)

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
