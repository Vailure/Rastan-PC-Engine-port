"""peek.py: read named RAM variables every frame from a headless run (addresses from src/main.lst)."""
import os
import re
import subprocess
from trace_player import TGRUN, LST


def ram_symbols():
    out = {}
    for ln in open(LST):
        m = re.match(r'\s*\d+\s+F8:([0-9A-F]{4})\s+(\w+):', ln)
        if m:
            out[m.group(2)] = int(m.group(1), 16) - 0x2000
    return out


def peek(rom, frames, inputs, names):
    """[{name: bytes}] per frame; names maps a symbol to how many bytes to read."""
    sym = ram_symbols()
    lo = min(sym[n] for n in names)
    hi = max(sym[n] + k for n, k in names.items())
    r = subprocess.run([TGRUN, rom, str(frames), '/dev/null'] + [str(a) for a in inputs],
                       env=dict(os.environ, TGRUN_PEEK=f'{lo:x},{hi - lo}'), capture_output=True, text=True, check=True)
    rows = []
    for ln in r.stdout.splitlines():
        b = [int(v, 16) for v in ln.split(':')[1].split()]
        rows.append({n: b[sym[n] - lo:sym[n] - lo + k] for n, k in names.items()})
    return rows
