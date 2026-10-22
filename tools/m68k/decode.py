"""Parse Musashi disassembly text (sim/dasm output) into instruction records.

Each Insn has: addr, size (bytes), op (mnemonic without size), sz ('b','w','l' or None),
operands (list of Operand). Only the subset of 68000 used by the code we translate
is supported; anything else raises ValueError so it can't slip through silently.
"""
import re
from dataclasses import dataclass, field


@dataclass
class Operand:
    kind: str            # Dn An imm ind postinc predec disp index abs pcrel pcindex reglist
    reg: int = 0         # register number (An for memory modes)
    disp: int = 0
    xreg: str = ''       # index register name, e.g. 'D7'
    xsize: str = 'w'
    addr: int = 0        # abs / pcrel resolved address, or imm value
    regs: tuple = ()     # reglist for movem: names like 'D1','A6'

    def __str__(self):
        k = self.kind
        if k == 'Dn': return f'D{self.reg}'
        if k == 'An': return f'A{self.reg}'
        if k == 'imm': return f'#${self.addr:x}'
        if k == 'ind': return f'(A{self.reg})'
        if k == 'postinc': return f'(A{self.reg})+'
        if k == 'predec': return f'-(A{self.reg})'
        if k == 'disp': return f'({self.disp},A{self.reg})'
        if k == 'index': return f'({self.disp},A{self.reg},{self.xreg}.{self.xsize})'
        if k == 'abs': return f'${self.addr:x}'
        if k == 'pcrel': return f'(${self.addr:x},PC)'
        if k == 'pcindex': return f'(${self.addr:x},PC,{self.xreg}.{self.xsize})'
        if k == 'reglist': return '/'.join(self.regs)
        return k


@dataclass
class Insn:
    addr: int
    size: int
    op: str
    sz: str
    operands: list = field(default_factory=list)
    text: str = ''

    @property
    def next(self):
        return self.addr + self.size


def num(s):
    s = s.strip()
    neg = s.startswith('-')
    if neg:
        s = s[1:]
    v = int(s[1:], 16) if s.startswith('$') else int(s, 10)
    return -v if neg else v


def parse_operand(s, insn_addr):
    s = s.strip()
    m = re.fullmatch(r'D([0-7])', s)
    if m: return Operand('Dn', int(m.group(1)))
    m = re.fullmatch(r'A([0-7])', s)
    if m: return Operand('An', int(m.group(1)))
    if s == 'SP': return Operand('An', 7)
    m = re.fullmatch(r'#(-?\$?[0-9a-f]+)', s)
    if m: return Operand('imm', addr=num(m.group(1)))
    m = re.fullmatch(r'\(A([0-7])\)', s)
    if m: return Operand('ind', int(m.group(1)))
    m = re.fullmatch(r'\(A([0-7])\)\+', s)
    if m: return Operand('postinc', int(m.group(1)))
    m = re.fullmatch(r'-\(A([0-7])\)', s)
    if m: return Operand('predec', int(m.group(1)))
    m = re.fullmatch(r'\((-?\$?[0-9a-f]+),A([0-7])\)', s)
    if m: return Operand('disp', int(m.group(2)), disp=num(m.group(1)))
    m = re.fullmatch(r'\((?:(-?\$?[0-9a-f]+),)?A([0-7]),([DA][0-7])\.([wl])\)', s)
    if m: return Operand('index', int(m.group(2)), disp=num(m.group(1)) if m.group(1) else 0,
                         xreg=m.group(3), xsize=m.group(4))
    m = re.fullmatch(r'\$([0-9a-f]+)(?:\.([wl]))?', s)
    if m:
        a = int(m.group(1), 16)
        if m.group(2) == 'w' and a & 0x8000:
            a |= 0xffff0000
        return Operand('abs', addr=a & 0xffffffff)
    # PC-relative: Musashi prints "($e,PC); ($3a06c)" - resolved address after ';'
    m = re.fullmatch(r'\((-?\$?[0-9a-f]+),PC\)', s)
    if m: return Operand('pcrel', addr=insn_addr + 2 + num(m.group(1)))
    m = re.fullmatch(r'\((-?\$?[0-9a-f]+),PC,([DA][0-7])\.([wl])\)', s)
    if m: return Operand('pcindex', addr=insn_addr + 2 + num(m.group(1)), xreg=m.group(2), xsize=m.group(3))
    m = re.fullmatch(r'[DA][0-7](?:[-/][DA][0-7])*', s)
    if m:
        regs = []
        for part in s.split('/'):
            if '-' in part:
                a, b = part.split('-')
                for r in range(int(a[1]), int(b[1]) + 1):
                    regs.append(a[0] + str(r))
            else:
                regs.append(part)
        return Operand('reglist', regs=tuple(regs))
    raise ValueError(f'unsupported operand {s!r} at {insn_addr:06x}')


def split_operands(args):
    out, depth, cur = [], 0, ''
    for ch in args:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [o.strip() for o in out]


LINE_RE = re.compile(r'([0-9a-f]{6})\s+((?:[0-9a-f]{4} )+)\s*(.*)')


class Listing(dict):
    """addr -> (size, text). Starts from a linear listing; addresses the linear pass
    decoded out of alignment (code right after data) are disassembled on demand."""
    def __init__(self, path, dasm=None, rom=None):
        super().__init__()
        with open(path) as stream:
            for ln in stream:
                m = LINE_RE.match(ln)
                if m:
                    self[int(m.group(1), 16)] = (len(m.group(2).split()) * 2, m.group(3).strip())
        self.dasm, self.rom = dasm, rom

    def __missing__(self, addr):
        import subprocess
        if not self.dasm:
            raise KeyError(addr)
        out = subprocess.run([self.dasm, self.rom, f'{addr:x}', f'{addr + 1:x}'],
                             capture_output=True, text=True, check=True).stdout
        m = LINE_RE.match(out)
        v = (len(m.group(2).split()) * 2, m.group(3).strip())
        self[addr] = v
        return v


def load_listing(path, dasm=None, rom=None):
    return Listing(path, dasm, rom)


def decode(lines, addr):
    size, text = lines[addr]
    body = text.split(';')[0].strip()
    parts = body.split(None, 1)
    mn = parts[0]
    args = parts[1] if len(parts) > 1 else ''
    if '.' in mn:
        op, sz = mn.split('.', 1)
    else:
        op, sz = mn, None
    ops = [parse_operand(o, addr) for o in split_operands(args)] if args else []
    return Insn(addr, size, op, sz, ops, text)

