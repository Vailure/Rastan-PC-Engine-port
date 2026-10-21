"""Reference interpreter for the 68000 subset used by the code we translate.

This defines the semantics the PC Engine back end must reproduce. It is checked
against the real arcade program (Musashi in sim/) with lockstep RAM snapshots.
"""
from .decode import decode

MASK = {'b': 0xff, 'w': 0xffff, 'l': 0xffffffff}
SIGN = {'b': 0x80, 'w': 0x8000, 'l': 0x80000000}
NBYTES = {'b': 1, 'w': 2, 'l': 4}


class Unsupported(Exception):
    pass


class Machine:
    def __init__(self, rom, lines, hooks=None):
        self.rom = rom
        self.lines = lines
        self.cache = {}
        self.D = [0] * 8
        self.A = [0] * 8
        self.N = self.Z = self.V = self.C = self.X = 0
        self.ram = bytearray(0x4000)
        self.hw_writes = []
        self.hooks = hooks or {}        # addr -> callable(machine): replaces a routine (acts as bsr+rts)
        self.count = 0

    # ---- memory
    def rd8(self, a):
        a &= 0xffffff
        if a < len(self.rom):
            return self.rom[a]
        if 0x10c000 <= a < 0x110000:
            return self.ram[a - 0x10c000]
        raise Unsupported(f'read {a:06x}')

    def wr8(self, a, v):
        a &= 0xffffff
        if 0x10c000 <= a < 0x110000:
            self.ram[a - 0x10c000] = v & 0xff
        else:
            self.hw_writes.append((a, v & 0xff))

    def rd(self, a, sz):
        v = 0
        for i in range(NBYTES[sz]):
            v = (v << 8) | self.rd8(a + i)
        return v

    def wr(self, a, sz, v):
        n = NBYTES[sz]
        for i in range(n):
            self.wr8(a + i, v >> (8 * (n - 1 - i)))

    # ---- operands
    def xval(self, name, xs):
        v = self.D[int(name[1])] if name[0] == 'D' else self.A[int(name[1])]
        if xs == 'w':
            v &= 0xffff
            if v & 0x8000:
                v -= 0x10000
        return v

    def ea(self, o, sz):
        """Effective address for memory operands (applies pre/post adjust)."""
        k = o.kind
        if k == 'ind': return self.A[o.reg]
        if k == 'disp': return (self.A[o.reg] + o.disp) & 0xffffffff
        if k == 'index': return (self.A[o.reg] + o.disp + self.xval(o.xreg, o.xsize)) & 0xffffffff
        if k == 'abs' or k == 'pcrel': return o.addr
        if k == 'pcindex': return (o.addr + self.xval(o.xreg, o.xsize)) & 0xffffffff
        if k == 'postinc':
            a = self.A[o.reg]
            step = NBYTES[sz] if not (o.reg == 7 and sz == 'b') else 2
            self.A[o.reg] = (a + step) & 0xffffffff
            return a
        if k == 'predec':
            step = NBYTES[sz] if not (o.reg == 7 and sz == 'b') else 2
            self.A[o.reg] = (self.A[o.reg] - step) & 0xffffffff
            return self.A[o.reg]
        raise Unsupported(f'ea {o}')

    def get(self, o, sz):
        k = o.kind
        if k == 'Dn': return self.D[o.reg] & MASK[sz]
        if k == 'An': return self.A[o.reg] & MASK[sz]
        if k == 'imm': return o.addr & MASK[sz]
        return self.rd(self.ea(o, sz), sz)

    def set(self, o, sz, v, addr=None):
        v &= MASK[sz]
        k = o.kind
        if k == 'Dn':
            self.D[o.reg] = (self.D[o.reg] & ~MASK[sz] & 0xffffffff) | v
        elif k == 'An':
            self.A[o.reg] = v
        else:
            self.wr(self.ea(o, sz) if addr is None else addr, sz, v)

    def rmw(self, o, sz, fn):
        """Read-modify-write a destination; computes the EA once."""
        if o.kind in ('Dn', 'An'):
            r = fn(self.get(o, sz))
            self.set(o, sz, r)
            return r
        a = self.ea(o, sz)
        r = fn(self.rd(a, sz))
        self.wr(a, sz, r & MASK[sz])
        return r

    # ---- flags
    def nz(self, v, sz):
        v &= MASK[sz]
        self.N = 1 if v & SIGN[sz] else 0
        self.Z = 1 if v == 0 else 0

    def logic(self, v, sz):
        self.nz(v, sz)
        self.V = self.C = 0

    def add_flags(self, s, d, r, sz):
        m, sg = MASK[sz], SIGN[sz]
        self.C = self.X = 1 if r > m else 0
        r &= m
        self.V = 1 if (~(s ^ d) & (s ^ r) & sg) else 0
        self.nz(r, sz)
        return r

    def sub_flags(self, s, d, sz, setx=True):
        m, sg = MASK[sz], SIGN[sz]
        r = (d - s) & m
        c = 1 if s > d else 0
        self.C = c
        if setx:
            self.X = c
        self.V = 1 if ((s ^ d) & (r ^ d) & sg) else 0
        self.nz(r, sz)
        return r

    def cond(self, cc):
        N, Z, V, C = self.N, self.Z, self.V, self.C
        return {
            'ra': True, 'eq': Z, 'ne': not Z, 'cs': C, 'cc': not C, 'mi': N, 'pl': not N,
            'vs': V, 'vc': not V, 'hi': not C and not Z, 'ls': C or Z,
            'ge': N == V, 'lt': N != V, 'gt': not Z and N == V, 'le': Z or N != V,
            't': True, 'f': False,
        }[cc]

    # ---- execution
    def insn(self, pc):
        i = self.cache.get(pc)
        if i is None:
            i = self.cache[pc] = decode(self.lines, pc)
        return i

    def push32(self, v):
        self.A[7] = (self.A[7] - 4) & 0xffffffff
        self.wr(self.A[7], 'l', v)

    def call(self, entry, max_steps=200000):
        """Run a subroutine entered with its return address already on the stack
        (as at a JSR target); stop when that address is popped."""
        sp0 = self.A[7]
        pc = entry
        steps = 0
        while True:
            if self.A[7] > sp0:
                return pc
            pc = self.step(pc)
            steps += 1
            if steps > max_steps:
                raise Unsupported('runaway')

    def step(self, pc):
        if pc in self.hooks:
            self.hooks[pc](self)
            ret = self.rd(self.A[7], 'l')
            self.A[7] = (self.A[7] + 4) & 0xffffffff
            return ret
        i = self.insn(pc)
        self.count += 1
        op, sz, o = i.op, i.sz, i.operands
        nxt = i.next

        if op in ('bra', 'bsr') or (op.startswith('b') and op[1:] in (
                'eq', 'ne', 'cs', 'cc', 'mi', 'pl', 'vs', 'vc', 'hi', 'ls', 'ge', 'lt', 'gt', 'le')):
            tgt = o[0].addr
            if op == 'bsr':
                self.push32(nxt)
                return tgt
            return tgt if self.cond(op[1:]) else nxt
        if op in ('dbf', 'dbra') or (op.startswith('db') and len(op) == 4):
            cc = 'f' if op in ('dbf', 'dbra') else op[2:]
            if self.cond(cc):
                return nxt
            r = (self.D[o[0].reg] - 1) & 0xffff
            self.D[o[0].reg] = (self.D[o[0].reg] & 0xffff0000) | r
            return o[1].addr if r != 0xffff else nxt
        if op == 'jsr':
            tgt = self.ea(o[0], 'l')
            self.push32(nxt)
            return tgt
        if op == 'jmp':
            return self.ea(o[0], 'l')
        if op == 'rts':
            ret = self.rd(self.A[7], 'l')
            self.A[7] = (self.A[7] + 4) & 0xffffffff
            return ret
        if op == 'nop':
            return nxt

        if op in ('move', 'movea'):
            v = self.get(o[0], sz)
            if op == 'movea' or o[1].kind == 'An':
                if sz == 'w' and v & 0x8000:
                    v |= 0xffff0000
                self.A[o[1].reg] = v & 0xffffffff
            else:
                self.set(o[1], sz, v)
                self.logic(v, sz)
            return nxt
        if op == 'moveq':
            v = o[0].addr & 0xff
            if v & 0x80:
                v |= 0xffffff00
            self.D[o[1].reg] = v
            self.logic(v, 'l')
            return nxt
        if op == 'lea':
            self.A[o[1].reg] = self.ea(o[0], 'l')
            return nxt
        if op == 'pea':
            self.push32(self.ea(o[0], 'l'))
            return nxt
        if op == 'clr':
            self.set(o[0], sz, 0)
            self.N = self.V = self.C = 0
            self.Z = 1
            return nxt
        if op == 'tst':
            self.logic(self.get(o[0], sz), sz)
            return nxt
        if op in ('cmp', 'cmpi', 'cmpa'):
            s = self.get(o[0], sz)
            if op == 'cmpa' or o[1].kind == 'An':
                if sz == 'w' and s & 0x8000:
                    s |= 0xffff0000
                self.sub_flags(s & 0xffffffff, self.A[o[1].reg], 'l', setx=False)
            else:
                self.sub_flags(s, self.get(o[1], sz), sz, setx=False)
            return nxt
        if op in ('add', 'addi', 'addq', 'adda', 'sub', 'subi', 'subq', 'suba'):
            s = self.get(o[0], sz) if o[0].kind != 'imm' else o[0].addr & MASK[sz]
            if op in ('addq', 'subq') and o[0].kind == 'imm' and s == 0:
                s = 8
            isadd = op.startswith('add')
            if op in ('adda', 'suba') or o[1].kind == 'An':
                if sz == 'w' and s & 0x8000:
                    s |= 0xffff0000
                a = o[1].reg
                self.A[a] = (self.A[a] + s if isadd else self.A[a] - s) & 0xffffffff
                return nxt
            if isadd:
                self.rmw(o[1], sz, lambda d: self.add_flags(s, d, d + s, sz))
            else:
                self.rmw(o[1], sz, lambda d: self.sub_flags(s, d, sz))
            return nxt
        if op in ('and', 'andi', 'or', 'ori', 'eor', 'eori'):
            s = self.get(o[0], sz)
            f = {'a': lambda d: d & s, 'o': lambda d: d | s, 'e': lambda d: d ^ s}[op[0]]
            r = self.rmw(o[1], sz, f)
            self.logic(r, sz)
            return nxt
        if op == 'not':
            r = self.rmw(o[0], sz, lambda d: ~d & MASK[sz])
            self.logic(r, sz)
            return nxt
        if op == 'neg':
            self.rmw(o[0], sz, lambda d: self.sub_flags(d, 0, sz))
            return nxt
        if op == 'ext':
            r = o[0].reg
            if sz == 'w':
                v = self.D[r] & 0xff
                v = v | 0xff00 if v & 0x80 else v
                self.D[r] = (self.D[r] & 0xffff0000) | v
            else:
                v = self.D[r] & 0xffff
                v = v | 0xffff0000 if v & 0x8000 else v
                self.D[r] = v
            self.logic(v, sz)
            return nxt
        if op == 'swap':
            r = o[0].reg
            v = ((self.D[r] << 16) | (self.D[r] >> 16)) & 0xffffffff
            self.D[r] = v
            self.logic(v, 'l')
            return nxt
        if op == 'mulu':
            v = (self.get(o[0], 'w') * (self.D[o[1].reg] & 0xffff)) & 0xffffffff
            self.D[o[1].reg] = v
            self.logic(v, 'l')
            return nxt
        if op in ('lsl', 'lsr', 'asl', 'asr'):
            if len(o) == 1:          # memory shift by 1
                cnt, dst, ssz = 1, o[0], 'w'
            else:
                cnt = o[0].addr if o[0].kind == 'imm' else self.D[o[0].reg] & 63
                dst, ssz = o[1], sz
            m, sg = MASK[ssz], SIGN[ssz]
            st = {}

            def shift(d):
                c = 0
                v = d
                vflag = 0
                for _ in range(cnt):
                    if op in ('lsl', 'asl'):
                        c = 1 if v & sg else 0
                        nv = (v << 1) & m
                        if (nv ^ v) & sg:
                            vflag = 1
                        v = nv
                    elif op == 'lsr':
                        c = v & 1
                        v >>= 1
                    else:
                        c = v & 1
                        v = (v >> 1) | (v & sg)
                st['c'], st['v'] = c, vflag
                return v
            r = self.rmw(dst, ssz, shift)
            self.nz(r, ssz)
            self.V = st['v'] if op == 'asl' else 0
            if cnt:
                self.C = self.X = st['c']
            else:
                self.C = 0
            return nxt
        if op in ('btst', 'bset', 'bclr', 'bchg'):
            bit = o[0].addr if o[0].kind == 'imm' else self.D[o[0].reg]
            if o[1].kind == 'Dn':
                bsz, bit = 'l', bit & 31
            else:
                bsz, bit = 'b', bit & 7
            old = self.get(o[1], bsz) if op == 'btst' else None
            if op == 'btst':
                self.Z = 0 if old & (1 << bit) else 1
                return nxt
            st = {}

            def f(d):
                st['z'] = 0 if d & (1 << bit) else 1
                if op == 'bset': return d | (1 << bit)
                if op == 'bclr': return d & ~(1 << bit)
                return d ^ (1 << bit)
            self.rmw(o[1], bsz, f)
            self.Z = st['z']
            return nxt
        if op == 'movem':
            if o[0].kind == 'reglist':          # registers -> memory
                regs, dst = o[0].regs, o[1]
                if dst.kind == 'predec':
                    for r in reversed(regs):
                        self.A[dst.reg] = (self.A[dst.reg] - NBYTES[sz]) & 0xffffffff
                        v = self.D[int(r[1])] if r[0] == 'D' else self.A[int(r[1])]
                        self.wr(self.A[dst.reg], sz, v & MASK[sz])
                else:
                    a = self.ea(dst, sz)
                    for r in regs:
                        v = self.D[int(r[1])] if r[0] == 'D' else self.A[int(r[1])]
                        self.wr(a, sz, v & MASK[sz])
                        a += NBYTES[sz]
            else:                                # memory -> registers
                src, regs = o[0], o[1].regs
                a = self.A[src.reg] if src.kind == 'postinc' else self.ea(src, sz)
                for r in regs:
                    v = self.rd(a, sz)
                    if sz == 'w' and v & 0x8000:
                        v |= 0xffff0000
                    if r[0] == 'D':
                        self.D[int(r[1])] = v
                    else:
                        self.A[int(r[1])] = v
                    a += NBYTES[sz]
                if src.kind == 'postinc':
                    self.A[src.reg] = a & 0xffffffff
            return nxt
        raise Unsupported(f'{i.addr:06x}: {i.text}')
