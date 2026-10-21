"""lockstep.py maincpu.bin full.asm calls.csnp entry : run the reference interpreter on
every recorded call and compare its exit RAM with the arcade's (Musashi) exit RAM.
"""
import gzip
import struct
import sys
from m68k.decode import load_listing
from m68k.interp import Machine, Unsupported

rom = open(sys.argv[1], 'rb').read()
lines = load_listing(sys.argv[2], dasm=sys.argv[2].replace('full.asm', 'dasm'), rom=sys.argv[1])
entry = int(sys.argv[4], 16)
stub = lambda m: None
# Calls that leave the player code: sound commands only touch the sound latch.
hooks = {}


def records(path):
    with gzip.open(path, 'rb') as f:
        while True:
            h = f.read(8)
            if len(h) < 8:
                return
            assert h[:4] == b'CSNP'
            frame = struct.unpack('>I', h[4:])[0]
            regs = struct.unpack('>16I', f.read(64))
            yield frame, regs, f.read(0x4000), f.read(0x4000)


ok = bad = 0
total = 0
for frame, regs, ram_in, ram_out in records(sys.argv[3]):
    m = Machine(rom, lines, hooks)
    m.D = list(regs[:8])
    m.A = list(regs[8:])
    m.ram[:] = ram_in
    try:
        m.call(entry)
    except Unsupported as e:
        print(f'frame {frame}: unsupported: {e}')
        bad += 1
        break
    total += m.count
    diff = [i for i in range(0x4000) if m.ram[i] != ram_out[i]]
    if diff:
        bad += 1
        if bad <= 5:
            print(f'frame {frame}: {len(diff)} bytes differ: ' +
                  ' '.join(f'{0x10c000 + i:06x}:{ram_out[i]:02x}/{m.ram[i]:02x}' for i in diff[:12]))
    else:
        ok += 1
print(f'{ok} calls match, {bad} differ; {total / max(1, ok + bad):.0f} instructions/call')
sys.exit(1 if bad else 0)
