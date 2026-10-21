"""callgraph.py full.asm entry [stop...] : routines reachable from entry (bsr/jsr/branches).

Reads the linear disassembly produced by sim/dasm. Reports each routine's
address range, plus the total byte size of reachable code.
"""
import re
import sys

lines = {}
order = []
for ln in open(sys.argv[1]):
    m = re.match(r'([0-9a-f]{6})\s+((?:[0-9a-f]{4} )+)\s*(.*)', ln)
    if m:
        a = int(m.group(1), 16)
        lines[a] = (len(m.group(2).split()) * 2, m.group(3).strip())
        order.append(a)

entry = int(sys.argv[2], 16)
stops = {int(x, 16) for x in sys.argv[3:]}
seen = set()
calls = {}
work = [(entry, entry)]
while work:
    start, a = work.pop()
    while a in lines and a not in seen and a not in stops:
        seen.add(a)
        size, text = lines[a]
        op = text.split()[0] if text else ''
        tgt = re.search(r'\$([0-9a-f]+)(?:\.l)?\b', text)
        if op in ('bsr', 'jsr', 'bsr.w', 'bsr.s') and tgt and '(' not in text:
            t = int(tgt.group(1), 16)
            calls.setdefault(start, set()).add(t)
            work.append((t, t))
        elif op.startswith('b') and op not in ('bset', 'bclr', 'btst', 'bchg') and tgt:
            t = int(tgt.group(1), 16)
            work.append((start, t))
            if op in ('bra', 'bra.s', 'bra.w'):
                break
        elif op in ('jmp',) and tgt and '(' not in text:
            work.append((start, int(tgt.group(1), 16)))
            break
        elif op in ('rts', 'rte') or op == 'jmp':
            break
        a += size
total = sum(lines[a][0] for a in seen)
print(f'reachable instructions {len(seen)}, {total} bytes')
for r in sorted(calls):
    print(f'{r:06x} -> ' + ' '.join(f'{t:06x}' for t in sorted(calls[r])))
indirect = [a for a in seen if re.search(r'\bj(mp|sr)\s+\(', lines[a][1])]
print('indirect jumps at', ' '.join(f'{a:06x}' for a in sorted(indirect)))
