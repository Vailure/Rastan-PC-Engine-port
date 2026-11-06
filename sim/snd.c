/* Headless Rastan sound-CPU simulator: Z80 + the YM2151's registers and timers.
 *
 * The arcade's sound board is a Z80 at 4 MHz with a YM2151 (FM) and an MSM5205
 * (ADPCM voice). The main CPU sends one-byte commands through a Taito PC060HA:
 * it writes the low nibble, then the high nibble, and the sound CPU takes an NMI
 * and reads the byte. This program runs that driver and logs what it writes to
 * the YM2151 and the MSM5205, so tools/pce_sound.py can turn a command's music
 * or effect into something the PC Engine's PSG can play.
 *
 * No FM synthesis happens here: only the register writes matter.
 *
 * usage: snd audiocpu.bin adpcm.bin out.log cmd [frames]
 *   cmd      sound command byte (as the main CPU sends it; see sim's sndlog)
 *   frames   60 Hz frames to run after the command (default 600)
 * out.log lines:
 *   F <frame>            a 60 Hz frame boundary
 *   T                    the driver's timer IRQ (its sequencer tick)
 *   Y <reg> <val>        YM2151 register write
 *   A <addr> <start|stop> MSM5205 sample address / start / stop
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static uint8_t rom[0x10000], adpcm[0x10000], ram[0x1000];
static int bank = 1;                     /* $4000-$7fff ROM bank */
static FILE *out;

/* ---------------------------------------------------------------- YM2151 */
static uint8_t opm_reg[256], opm_addr, opm_status;
static double opm_ta_period, opm_tb_period, opm_ta_next, opm_tb_next;
static int opm_irq;
static double z80_time;                  /* seconds */
#define Z80_CLOCK 4000000.0
#define OPM_CLOCK 3579545.0

static void opm_timers(void)
{
    if (opm_reg[0x14] & 1) {             /* timer A running */
        while (z80_time >= opm_ta_next) {
            opm_ta_next += opm_ta_period;
            if (opm_reg[0x14] & 0x04) { opm_status |= 1; opm_irq = 1; }
        }
    }
    if (opm_reg[0x14] & 2) {
        while (z80_time >= opm_tb_next) {
            opm_tb_next += opm_tb_period;
            if (opm_reg[0x14] & 0x08) { opm_status |= 2; opm_irq = 1; }
        }
    }
}

static void opm_write(int port, uint8_t v)
{
    if (!port) { opm_addr = v; return; }
    opm_reg[opm_addr] = v;
    if (opm_addr != 0x1b || !getenv("SND_QUIET1B")) fprintf(out, "Y %02x %02x%s\n", opm_addr, v,
        getenv("SND_TRACE") ? "" : "");
    if (opm_addr == 0x1b) bank = (v >> 6) & 3;
    switch (opm_addr) {
    case 0x10: case 0x11: {              /* timer A period: 64 * (1024 - NA) */
        int na = (opm_reg[0x10] << 2) | (opm_reg[0x11] & 3);
        opm_ta_period = 64.0 * (1024 - na) / OPM_CLOCK;
        break;
    }
    case 0x12:                           /* timer B period: 1024 * (256 - NB) */
        opm_tb_period = 1024.0 * (256 - opm_reg[0x12]) / OPM_CLOCK;
        break;
    case 0x14:
        if (v & 0x10) { opm_status &= ~1; }
        if (v & 0x20) { opm_status &= ~2; }
        if (!(opm_status & ((opm_reg[0x14] >> 2) & 3))) opm_irq = 0;
        if (v & 1) opm_ta_next = z80_time + opm_ta_period;
        if (v & 2) opm_tb_next = z80_time + opm_tb_period;
        break;
    }
}

/* ------------------------------------------------- main CPU -> sound CPU */
/* The main CPU sends a command as two nibbles (low, then high); the sound CPU
 * takes an NMI and reads them back one per read of $A001. */
static int cmd_nib[2], cmd_pending, cmd_value, nmi_pending;
static int trace_left, trace_n;
static int cmds[8], ncmds;

static void send_command(int v)
{
    cmd_value = v;
    cmd_nib[0] = v & 0x0f;
    cmd_nib[1] = (v >> 4) & 0x0f;
    cmd_pending = 2;
    nmi_pending = 1;
}

/* ----------------------------------------------------------------- memory */
static uint16_t PC;
static uint8_t rd(uint16_t a)
{
    if (a < 0x4000) return rom[a];
    if (a < 0x8000) return rom[(bank * 0x4000 + (a - 0x4000)) & 0xffff];
    if (a < 0x9000) return ram[a & 0xfff];
    if (a < 0xa000) {                    /* YM2151: $9000 data, $9001 status */
        opm_timers();
        return (a & 1) ? opm_status : 0;
    }
    if (a < 0xb000) {                    /* PC060HA: the command byte */
        if (getenv("SND_TRACE")) fprintf(out, "; read %04x pc=%04x cmd=%02x pend=%d\n", a, PC, cmd_value, cmd_pending);
        if (a & 1) { int v = cmd_pending ? cmd_nib[2 - cmd_pending] : 0; if (cmd_pending) cmd_pending--; return v; }
        return 0;
    }
    return 0xff;
}

static int adpcm_addr;
static void wr(uint16_t a, uint8_t v)
{
    if (a < 0x8000) return;
    if (a < 0x9000) { ram[a & 0xfff] = v; return; }
    if (a < 0xa000) { opm_write(a & 1, v); return; }
    if (a < 0xb000) return;              /* PC060HA writes back to the main CPU */
    if (a < 0xc000) { adpcm_addr = v; fprintf(out, "A %02x addr\n", v); return; }
    if (a < 0xd000) { fprintf(out, "A %02x start\n", adpcm_addr); return; }
    fprintf(out, "A %02x stop\n", adpcm_addr);
}

/* -------------------------------------------------------------- Z80 core */
static uint8_t A, F, B, C, D, E, H, L, A2, F2, B2, C2, D2, E2, H2, L2, I, R;
static uint16_t IX, IY, SP;
static int IFF1, IFF2, IM, halted;
static long long cycles;

#define SF 0x80
#define ZF 0x40
#define YF 0x20
#define HF 0x10
#define XF 0x08
#define PF 0x04
#define NF 0x02
#define CF 0x01

static const uint8_t parity[256] = {
#define P2(n) n, n ^ PF, n ^ PF, n
#define P4(n) P2(n), P2(n ^ PF), P2(n ^ PF), P2(n)
#define P6(n) P4(n), P4(n ^ PF), P4(n ^ PF), P4(n)
    P6(PF), P6(0), P6(0), P6(PF)
};

static uint16_t rd16(uint16_t a) { return rd(a) | (rd(a + 1) << 8); }
static void wr16(uint16_t a, uint16_t v) { wr(a, v & 0xff); wr(a + 1, v >> 8); }
static void push(uint16_t v) { SP -= 2; wr16(SP, v); }
static uint16_t pop(void) { uint16_t v = rd16(SP); SP += 2; return v; }

static uint8_t inc8(uint8_t v)
{
    uint8_t r = v + 1;
    F = (F & CF) | (r & (SF | YF | XF)) | (r ? 0 : ZF) | ((r & 0x0f) ? 0 : HF) | (r == 0x80 ? PF : 0);
    return r;
}
static uint8_t dec8(uint8_t v)
{
    uint8_t r = v - 1;
    F = (F & CF) | NF | (r & (SF | YF | XF)) | (r ? 0 : ZF) | (((r & 0x0f) == 0x0f) ? HF : 0)
        | (r == 0x7f ? PF : 0);
    return r;
}
static void add8(uint8_t v, int carry)
{
    unsigned r = A + v + carry;
    F = (r & (SF | YF | XF)) | ((r & 0xff) ? 0 : ZF) | (r > 0xff ? CF : 0)
        | (((A ^ v ^ r) & 0x10) ? HF : 0) | ((((A ^ ~v) & (A ^ r)) & 0x80) ? PF : 0);
    A = r;
}
static void sub8(uint8_t v, int carry)
{
    unsigned r = A - v - carry;
    F = (r & (SF | YF | XF)) | ((r & 0xff) ? 0 : ZF) | NF | (r > 0xff ? CF : 0)
        | (((A ^ v ^ r) & 0x10) ? HF : 0) | ((((A ^ v) & (A ^ r)) & 0x80) ? PF : 0);
    A = r;
}
static void cp8(uint8_t v)
{
    unsigned r = A - v;
    F = (r & SF) | ((r & 0xff) ? 0 : ZF) | NF | (r > 0xff ? CF : 0) | (v & (YF | XF))
        | (((A ^ v ^ r) & 0x10) ? HF : 0) | ((((A ^ v) & (A ^ r)) & 0x80) ? PF : 0);
}
static void and8(uint8_t v) { A &= v; F = parity[A] | (A & (SF | YF | XF)) | (A ? 0 : ZF) | HF; }
static void or8(uint8_t v)  { A |= v; F = parity[A] | (A & (SF | YF | XF)) | (A ? 0 : ZF); }
static void xor8(uint8_t v) { A ^= v; F = parity[A] | (A & (SF | YF | XF)) | (A ? 0 : ZF); }
static uint16_t add16(uint16_t a, uint16_t b)
{
    unsigned r = a + b;
    F = (F & (SF | ZF | PF)) | ((r >> 8) & (YF | XF)) | (r > 0xffff ? CF : 0)
        | (((a ^ b ^ r) & 0x1000) ? HF : 0);
    return r;
}
static void adc16(uint16_t v)
{
    uint16_t hl = (H << 8) | L;
    unsigned r = hl + v + (F & CF);
    F = ((r >> 8) & (SF | YF | XF)) | ((r & 0xffff) ? 0 : ZF) | (r > 0xffff ? CF : 0)
        | (((hl ^ v ^ r) & 0x1000) ? HF : 0) | ((((hl ^ ~v) & (hl ^ r)) & 0x8000) ? PF : 0);
    H = r >> 8; L = r;
}
static void sbc16(uint16_t v)
{
    uint16_t hl = (H << 8) | L;
    unsigned r = hl - v - (F & CF);
    F = ((r >> 8) & (SF | YF | XF)) | ((r & 0xffff) ? 0 : ZF) | NF | (r > 0xffff ? CF : 0)
        | (((hl ^ v ^ r) & 0x1000) ? HF : 0) | ((((hl ^ v) & (hl ^ r)) & 0x8000) ? PF : 0);
    H = r >> 8; L = r;
}

/* CB-prefixed rotates and bit operations */
static uint8_t cb_op(int op, uint8_t v)
{
    uint8_t c;
    switch (op >> 3) {
    case 0: c = v >> 7; v = (v << 1) | c; break;                       /* RLC */
    case 1: c = v & 1; v = (v >> 1) | (c << 7); break;                 /* RRC */
    case 2: c = v >> 7; v = (v << 1) | (F & CF); break;                /* RL  */
    case 3: c = v & 1; v = (v >> 1) | ((F & CF) << 7); break;          /* RR  */
    case 4: c = v >> 7; v <<= 1; break;                                /* SLA */
    case 5: c = v & 1; v = (v >> 1) | (v & 0x80); break;               /* SRA */
    case 6: c = v >> 7; v = (v << 1) | 1; break;                       /* SLL */
    default: c = v & 1; v >>= 1; break;                                /* SRL */
    }
    F = parity[v] | (v & (SF | YF | XF)) | (v ? 0 : ZF) | c;
    return v;
}

static uint8_t *reg8(int i, uint16_t *idx, int *mem, uint16_t *ea, int disp)
{
    static uint8_t tmp;
    switch (i) {
    case 0: return &B; case 1: return &C; case 2: return &D; case 3: return &E;
    case 4: if (idx) { tmp = *idx >> 8; return &tmp; } return &H;
    case 5: if (idx) { tmp = *idx & 0xff; return &tmp; } return &L;
    case 7: return &A;
    default:
        *mem = 1;
        *ea = idx ? (uint16_t)(*idx + disp) : (uint16_t)((H << 8) | L);
        tmp = rd(*ea);
        return &tmp;
    }
}

static void put8(int i, uint16_t *idx, uint16_t ea, int mem, uint8_t v)
{
    switch (i) {
    case 0: B = v; break; case 1: C = v; break; case 2: D = v; break; case 3: E = v; break;
    case 4: if (idx) *idx = (*idx & 0x00ff) | (v << 8); else H = v; break;
    case 5: if (idx) *idx = (*idx & 0xff00) | v; else L = v; break;
    case 7: A = v; break;
    default: wr(ea, v); break;
    }
    (void)mem;
}

static void step(void)
{
    uint16_t *idx = NULL;
    int disp = 0;
    uint8_t op;

    if (halted) { cycles += 4; return; }
again:
    op = rd(PC++);
    R = (R & 0x80) | ((R + 1) & 0x7f);
    cycles += 4;

    if (op == 0xdd || op == 0xfd) {
        idx = (op == 0xdd) ? &IX : &IY;
        op = rd(PC++);
        cycles += 4;
        if (op == 0xdd || op == 0xfd) { PC--; goto again; }
    }

    if (op == 0xcb) {
        uint16_t ea = 0; int mem = 0; uint8_t v; int r;
        if (idx) { disp = (int8_t)rd(PC++); }
        op = rd(PC++);
        cycles += 8;
        r = op & 7;
        if (idx) { ea = *idx + disp; v = rd(ea); mem = 1; }
        else { uint8_t *p = reg8(r, NULL, &mem, &ea, 0); v = *p; }
        if ((op & 0xc0) == 0x40) {                       /* BIT */
            int b = (op >> 3) & 7;
            uint8_t t = v & (1 << b);
            F = (F & CF) | HF | (t ? (t & SF) : (ZF | PF)) | (mem ? ((ea >> 8) & (YF | XF)) : (v & (YF | XF)));
            return;
        }
        if ((op & 0xc0) == 0x80) v &= ~(1 << ((op >> 3) & 7));          /* RES */
        else if ((op & 0xc0) == 0xc0) v |= 1 << ((op >> 3) & 7);        /* SET */
        else v = cb_op(op, v);
        if (idx) { wr(ea, v); if (r != 6) put8(r, NULL, 0, 0, v); }
        else put8(r, NULL, ea, mem, v);
        return;
    }

    if (op == 0xed) {
        op = rd(PC++);
        cycles += 4;
        switch (op) {
        case 0x42: sbc16((B << 8) | C); cycles += 7; break;
        case 0x52: sbc16((D << 8) | E); cycles += 7; break;
        case 0x62: sbc16((H << 8) | L); cycles += 7; break;
        case 0x72: sbc16(SP); cycles += 7; break;
        case 0x4a: adc16((B << 8) | C); cycles += 7; break;
        case 0x5a: adc16((D << 8) | E); cycles += 7; break;
        case 0x6a: adc16((H << 8) | L); cycles += 7; break;
        case 0x7a: adc16(SP); cycles += 7; break;
        case 0x43: wr16(rd16(PC), (B << 8) | C); PC += 2; cycles += 12; break;
        case 0x53: wr16(rd16(PC), (D << 8) | E); PC += 2; cycles += 12; break;
        case 0x63: wr16(rd16(PC), (H << 8) | L); PC += 2; cycles += 12; break;
        case 0x73: wr16(rd16(PC), SP); PC += 2; cycles += 12; break;
        case 0x4b: { uint16_t v = rd16(rd16(PC)); B = v >> 8; C = v; PC += 2; cycles += 12; break; }
        case 0x5b: { uint16_t v = rd16(rd16(PC)); D = v >> 8; E = v; PC += 2; cycles += 12; break; }
        case 0x6b: { uint16_t v = rd16(rd16(PC)); H = v >> 8; L = v; PC += 2; cycles += 12; break; }
        case 0x7b: SP = rd16(rd16(PC)); PC += 2; cycles += 12; break;
        case 0x44: case 0x4c: case 0x54: case 0x5c:
        case 0x64: case 0x6c: case 0x74: case 0x7c: { uint8_t v = A; A = 0; sub8(v, 0); break; }
        case 0x45: case 0x4d: case 0x55: case 0x5d:    /* RETN / RETI */
        case 0x65: case 0x6d: case 0x75: case 0x7d:
            PC = pop(); IFF1 = IFF2; cycles += 6; break;
        case 0x46: case 0x4e: case 0x66: case 0x6e: IM = 0; break;
        case 0x56: case 0x76: IM = 1; break;
        case 0x5e: case 0x7e: IM = 2; break;
        case 0x47: I = A; cycles += 1; break;
        case 0x4f: R = A; cycles += 1; break;
        case 0x57: A = I; F = (F & CF) | (A & (SF | YF | XF)) | (A ? 0 : ZF) | (IFF2 ? PF : 0); cycles += 1; break;
        case 0x5f: A = R; F = (F & CF) | (A & (SF | YF | XF)) | (A ? 0 : ZF) | (IFF2 ? PF : 0); cycles += 1; break;
        case 0x67: { uint16_t hl = (H << 8) | L; uint8_t v = rd(hl);     /* RRD */
                     wr(hl, (v >> 4) | (A << 4)); A = (A & 0xf0) | (v & 0x0f);
                     F = (F & CF) | parity[A] | (A & (SF | YF | XF)) | (A ? 0 : ZF); cycles += 10; break; }
        case 0x6f: { uint16_t hl = (H << 8) | L; uint8_t v = rd(hl);     /* RLD */
                     wr(hl, (v << 4) | (A & 0x0f)); A = (A & 0xf0) | (v >> 4);
                     F = (F & CF) | parity[A] | (A & (SF | YF | XF)) | (A ? 0 : ZF); cycles += 10; break; }
        case 0xa0: case 0xa8: case 0xb0: case 0xb8: {                    /* LDI/LDD/LDIR/LDDR */
            uint16_t hl = (H << 8) | L, de = (D << 8) | E, bc = (B << 8) | C;
            uint8_t v = rd(hl); wr(de, v);
            int d = (op & 8) ? -1 : 1;
            hl += d; de += d; bc--;
            H = hl >> 8; L = hl; D = de >> 8; E = de; B = bc >> 8; C = bc;
            F = (F & (SF | ZF | CF)) | (bc ? PF : 0);
            cycles += 8;
            if ((op & 0x10) && bc) { PC -= 2; cycles += 5; }
            break;
        }
        case 0xa1: case 0xa9: case 0xb1: case 0xb9: {                    /* CPI/CPD/CPIR/CPDR */
            uint16_t hl = (H << 8) | L, bc = (B << 8) | C;
            uint8_t v = rd(hl);
            unsigned r = A - v;
            int d = (op & 8) ? -1 : 1;
            hl += d; bc--;
            H = hl >> 8; L = hl; B = bc >> 8; C = bc;
            F = (F & CF) | NF | (r & SF) | ((r & 0xff) ? 0 : ZF) | (((A ^ v ^ r) & 0x10) ? HF : 0)
                | (bc ? PF : 0);
            cycles += 8;
            if ((op & 0x10) && bc && (r & 0xff)) { PC -= 2; cycles += 5; }
            break;
        }
        default: break;                  /* the driver uses no I/O ports */
        }
        return;
    }

    if (idx && (op & 0xc0) == 0x40 && op != 0x76) {
        int d = (op >> 3) & 7, s = op & 7;
        if (d == 6 || s == 6) disp = (int8_t)rd(PC++);
    } else if (idx && ((op & 0xc7) == 0x46 || (op & 0xf8) == 0x70 || (op & 0xc7) == 0x86
                       || op == 0x34 || op == 0x35 || op == 0x36)) {
        disp = (int8_t)rd(PC++);
    }

    switch (op) {
    case 0x00: break;
    case 0x76: halted = 1; break;
    case 0x01: C = rd(PC++); B = rd(PC++); cycles += 6; break;
    case 0x11: E = rd(PC++); D = rd(PC++); cycles += 6; break;
    case 0x21: if (idx) { *idx = rd16(PC); PC += 2; } else { L = rd(PC++); H = rd(PC++); } cycles += 6; break;
    case 0x31: SP = rd16(PC); PC += 2; cycles += 6; break;
    case 0x02: wr((B << 8) | C, A); cycles += 3; break;
    case 0x12: wr((D << 8) | E, A); cycles += 3; break;
    case 0x0a: A = rd((B << 8) | C); cycles += 3; break;
    case 0x1a: A = rd((D << 8) | E); cycles += 3; break;
    case 0x22: if (idx) wr16(rd16(PC), *idx); else wr16(rd16(PC), (H << 8) | L); PC += 2; cycles += 12; break;
    case 0x2a: if (idx) *idx = rd16(rd16(PC)); else { uint16_t v = rd16(rd16(PC)); H = v >> 8; L = v; }
               PC += 2; cycles += 12; break;
    case 0x32: wr(rd16(PC), A); PC += 2; cycles += 9; break;
    case 0x3a: A = rd(rd16(PC)); PC += 2; cycles += 9; break;
    case 0x03: { uint16_t v = ((B << 8) | C) + 1; B = v >> 8; C = v; cycles += 2; break; }
    case 0x13: { uint16_t v = ((D << 8) | E) + 1; D = v >> 8; E = v; cycles += 2; break; }
    case 0x23: if (idx) (*idx)++; else { uint16_t v = ((H << 8) | L) + 1; H = v >> 8; L = v; } cycles += 2; break;
    case 0x33: SP++; cycles += 2; break;
    case 0x0b: { uint16_t v = ((B << 8) | C) - 1; B = v >> 8; C = v; cycles += 2; break; }
    case 0x1b: { uint16_t v = ((D << 8) | E) - 1; D = v >> 8; E = v; cycles += 2; break; }
    case 0x2b: if (idx) (*idx)--; else { uint16_t v = ((H << 8) | L) - 1; H = v >> 8; L = v; } cycles += 2; break;
    case 0x3b: SP--; cycles += 2; break;
    case 0x09: case 0x19: case 0x29: case 0x39: {
        uint16_t v = op == 0x09 ? ((B << 8) | C) : op == 0x19 ? ((D << 8) | E)
                   : op == 0x29 ? (idx ? *idx : ((H << 8) | L)) : SP;
        if (idx) *idx = add16(*idx, v);
        else { uint16_t r = add16((H << 8) | L, v); H = r >> 8; L = r; }
        cycles += 7; break;
    }
    case 0x04: B = inc8(B); break;
    case 0x0c: C = inc8(C); break;
    case 0x14: D = inc8(D); break;
    case 0x1c: E = inc8(E); break;
    case 0x24: if (idx) *idx = (*idx & 0xff) | (inc8(*idx >> 8) << 8); else H = inc8(H); break;
    case 0x2c: if (idx) *idx = (*idx & 0xff00) | inc8(*idx & 0xff); else L = inc8(L); break;
    case 0x3c: A = inc8(A); break;
    case 0x34: { uint16_t ea = idx ? (uint16_t)(*idx + disp) : (uint16_t)((H << 8) | L);
                 wr(ea, inc8(rd(ea))); cycles += 7; break; }
    case 0x05: B = dec8(B); break;
    case 0x0d: C = dec8(C); break;
    case 0x15: D = dec8(D); break;
    case 0x1d: E = dec8(E); break;
    case 0x25: if (idx) *idx = (*idx & 0xff) | (dec8(*idx >> 8) << 8); else H = dec8(H); break;
    case 0x2d: if (idx) *idx = (*idx & 0xff00) | dec8(*idx & 0xff); else L = dec8(L); break;
    case 0x3d: A = dec8(A); break;
    case 0x35: { uint16_t ea = idx ? (uint16_t)(*idx + disp) : (uint16_t)((H << 8) | L);
                 wr(ea, dec8(rd(ea))); cycles += 7; break; }
    case 0x06: B = rd(PC++); cycles += 3; break;
    case 0x0e: C = rd(PC++); cycles += 3; break;
    case 0x16: D = rd(PC++); cycles += 3; break;
    case 0x1e: E = rd(PC++); cycles += 3; break;
    case 0x26: if (idx) *idx = (*idx & 0xff) | (rd(PC++) << 8); else H = rd(PC++); cycles += 3; break;
    case 0x2e: if (idx) *idx = (*idx & 0xff00) | rd(PC++); else L = rd(PC++); cycles += 3; break;
    case 0x3e: A = rd(PC++); cycles += 3; break;
    case 0x36: { uint16_t ea = idx ? (uint16_t)(*idx + disp) : (uint16_t)((H << 8) | L);
                 wr(ea, rd(PC++)); cycles += 6; break; }
    case 0x07: { uint8_t c = A >> 7; A = (A << 1) | c;                 /* RLCA */
                 F = (F & (SF | ZF | PF)) | (A & (YF | XF)) | c; break; }
    case 0x0f: { uint8_t c = A & 1; A = (A >> 1) | (c << 7);           /* RRCA */
                 F = (F & (SF | ZF | PF)) | (A & (YF | XF)) | c; break; }
    case 0x17: { uint8_t c = A >> 7; A = (A << 1) | (F & CF);          /* RLA */
                 F = (F & (SF | ZF | PF)) | (A & (YF | XF)) | c; break; }
    case 0x1f: { uint8_t c = A & 1; A = (A >> 1) | ((F & CF) << 7);    /* RRA */
                 F = (F & (SF | ZF | PF)) | (A & (YF | XF)) | c; break; }
    case 0x27: {                                                        /* DAA */
        int a = A, adj = 0;
        if ((F & HF) || (a & 0x0f) > 9) adj |= 6;
        if ((F & CF) || a > 0x99) { adj |= 0x60; F |= CF; }
        if (F & NF) a -= adj; else a += adj;
        A = a;
        F = (F & (CF | NF)) | parity[A] | (A & (SF | YF | XF)) | (A ? 0 : ZF)
            | (((a ^ A) & 0x10) ? HF : 0);
        break;
    }
    case 0x2f: A = ~A; F = (F & (SF | ZF | PF | CF)) | HF | NF | (A & (YF | XF)); break;
    case 0x37: F = (F & (SF | ZF | PF)) | CF | (A & (YF | XF)); break;  /* SCF */
    case 0x3f: F = (F & (SF | ZF | PF)) | ((F & CF) ? HF : 0) | ((F & CF) ^ CF) | (A & (YF | XF)); break;
    case 0x08: { uint8_t t = A; A = A2; A2 = t; t = F; F = F2; F2 = t; break; }
    case 0xd9: { uint8_t t;
                 t = B; B = B2; B2 = t; t = C; C = C2; C2 = t;
                 t = D; D = D2; D2 = t; t = E; E = E2; E2 = t;
                 t = H; H = H2; H2 = t; t = L; L = L2; L2 = t; break; }
    case 0x10: { int8_t d = rd(PC++); cycles += 1;                     /* DJNZ */
                 if (--B) { PC += d; cycles += 5; } else cycles += 3; break; }
    case 0x18: { int8_t d = rd(PC++); PC += d; cycles += 8; break; }
    case 0x20: case 0x28: case 0x30: case 0x38: {
        int c = (op == 0x20) ? !(F & ZF) : (op == 0x28) ? !!(F & ZF)
              : (op == 0x30) ? !(F & CF) : !!(F & CF);
        int8_t d = rd(PC++); cycles += 3;
        if (c) { PC += d; cycles += 5; }
        break;
    }
    case 0xc3: PC = rd16(PC); cycles += 6; break;
    case 0xe9: PC = idx ? *idx : ((H << 8) | L); break;
    case 0xcd: { uint16_t t = rd16(PC); PC += 2; push(PC); PC = t; cycles += 13; break; }
    case 0xc9: PC = pop(); cycles += 6; break;
    case 0xeb: { uint8_t t = D; D = H; H = t; t = E; E = L; L = t; break; }
    case 0xe3: { uint16_t t = rd16(SP);
                 if (idx) { wr16(SP, *idx); *idx = t; } else { wr16(SP, (H << 8) | L); H = t >> 8; L = t; }
                 cycles += 15; break; }
    case 0xf9: SP = idx ? *idx : ((H << 8) | L); cycles += 2; break;
    case 0xf3: IFF1 = IFF2 = 0; break;
    case 0xfb: IFF1 = IFF2 = 1; break;
    case 0xc5: push((B << 8) | C); cycles += 7; break;
    case 0xd5: push((D << 8) | E); cycles += 7; break;
    case 0xe5: push(idx ? *idx : ((H << 8) | L)); cycles += 7; break;
    case 0xf5: push((A << 8) | F); cycles += 7; break;
    case 0xc1: { uint16_t v = pop(); B = v >> 8; C = v; cycles += 6; break; }
    case 0xd1: { uint16_t v = pop(); D = v >> 8; E = v; cycles += 6; break; }
    case 0xe1: { uint16_t v = pop(); if (idx) *idx = v; else { H = v >> 8; L = v; } cycles += 6; break; }
    case 0xf1: { uint16_t v = pop(); A = v >> 8; F = v; cycles += 6; break; }
    case 0xdb: PC++; cycles += 7; break;                               /* IN A,(n) */
    case 0xd3: PC++; cycles += 7; break;                               /* OUT (n),A */
    default:
        if ((op & 0xc0) == 0x40) {                                     /* LD r,r' */
            int d = (op >> 3) & 7, s = op & 7, mem = 0; uint16_t ea = 0;
            uint8_t *p = reg8(s, (s == 6) ? NULL : idx, &mem, &ea, disp);
            uint8_t v = *p;
            if (s == 6) { ea = idx ? (uint16_t)(*idx + disp) : (uint16_t)((H << 8) | L); v = rd(ea); cycles += 3; }
            if (d == 6) { uint16_t e = idx ? (uint16_t)(*idx + disp) : (uint16_t)((H << 8) | L);
                          wr(e, v); cycles += 3; }
            else put8(d, (s == 6) ? NULL : idx, 0, 0, v);
        } else if ((op & 0xc0) == 0x80) {                              /* ALU A,r */
            int s = op & 7, mem = 0; uint16_t ea = 0; uint8_t v;
            if (s == 6) { ea = idx ? (uint16_t)(*idx + disp) : (uint16_t)((H << 8) | L); v = rd(ea); cycles += 3; }
            else v = *reg8(s, idx, &mem, &ea, 0);
            switch ((op >> 3) & 7) {
            case 0: add8(v, 0); break; case 1: add8(v, F & CF); break;
            case 2: sub8(v, 0); break; case 3: sub8(v, F & CF); break;
            case 4: and8(v); break;    case 5: xor8(v); break;
            case 6: or8(v); break;     default: cp8(v); break;
            }
        } else if ((op & 0xc7) == 0xc6) {                              /* ALU A,n */
            uint8_t v = rd(PC++); cycles += 3;
            switch ((op >> 3) & 7) {
            case 0: add8(v, 0); break; case 1: add8(v, F & CF); break;
            case 2: sub8(v, 0); break; case 3: sub8(v, F & CF); break;
            case 4: and8(v); break;    case 5: xor8(v); break;
            case 6: or8(v); break;     default: cp8(v); break;
            }
        } else if ((op & 0xc7) == 0xc7) { push(PC); PC = op & 0x38; cycles += 7; }  /* RST */
        else if ((op & 0xc7) == 0xc0) {                                /* RET cc */
            static const int m[8] = { ZF, ZF, CF, CF, PF, PF, SF, SF };
            int set = op & 0x08, t = (F & m[(op >> 3) & 7]) != 0;
            cycles += 1;
            if (set ? t : !t) { PC = pop(); cycles += 6; }
        } else if ((op & 0xc7) == 0xc2) {                              /* JP cc */
            static const int m[8] = { ZF, ZF, CF, CF, PF, PF, SF, SF };
            int set = op & 0x08, t = (F & m[(op >> 3) & 7]) != 0;
            uint16_t a = rd16(PC); PC += 2; cycles += 6;
            if (set ? t : !t) PC = a;
        } else if ((op & 0xc7) == 0xc4) {                              /* CALL cc */
            static const int m[8] = { ZF, ZF, CF, CF, PF, PF, SF, SF };
            int set = op & 0x08, t = (F & m[(op >> 3) & 7]) != 0;
            uint16_t a = rd16(PC); PC += 2; cycles += 6;
            if (set ? t : !t) { push(PC); PC = a; cycles += 7; }
        }
        break;
    }
}

static void irq(void)
{
    if (nmi_pending) {                   /* a command from the main CPU */
        nmi_pending = 0;
        halted = 0;
        IFF2 = IFF1; IFF1 = 0;
        push(PC); PC = 0x66;
        cycles += 11;
        return;
    }
    if (opm_irq && IFF1) {
        halted = 0;
        IFF1 = IFF2 = 0;
        fprintf(out, "T\n");             /* the driver's own tick: its timer IRQ */
        push(PC);
        PC = (IM == 2) ? rd16((I << 8) | 0xff) : 0x38;
        cycles += 13;
    }
}

int main(int argc, char **argv)
{
    FILE *f;
    int cmd, frames = 600, frame;
    long long per_frame = (long long)(Z80_CLOCK / 60.0);

    if (argc < 5) { fprintf(stderr, "usage: snd audiocpu.bin adpcm.bin out.log cmd [frames]\n"); return 1; }
    f = fopen(argv[1], "rb"); if (!f) { perror(argv[1]); return 1; }
    fread(rom, 1, sizeof rom, f); fclose(f);
    f = fopen(argv[2], "rb"); if (f) { fread(adpcm, 1, sizeof adpcm, f); fclose(f); }
    out = fopen(argv[3], "w"); if (!out) { perror(argv[3]); return 1; }
    { char *p = argv[4]; while (*p && ncmds < 8) { cmds[ncmds++] = (int)strtol(p, &p, 0); if (*p == ',') p++; } }
    cmd = cmds[0];
    if (getenv("SND_PCTRACE")) trace_n = atoi(getenv("SND_PCTRACE"));
    if (argc > 5) frames = atoi(argv[5]);

    PC = 0; SP = 0x8fff; IFF1 = IFF2 = 0; IM = 1;
    opm_ta_period = opm_tb_period = 1.0;

    for (frame = -120; frame < frames; frame++) {   /* 2 s to boot, then the command */
        long long target = cycles + per_frame;
        if (frame >= 0 && frame % 30 == 0 && frame / 30 < ncmds) { send_command(cmds[frame / 30]); trace_left = trace_n; }
        fprintf(out, "F %d\n", frame);
        while (cycles < target) {
            z80_time = cycles / Z80_CLOCK;
            opm_timers();
            irq();
            if (trace_left > 0) { fprintf(out, "; pc=%04x a=%02x bc=%02x%02x hl=%02x%02x\n", PC, A, B, C, H, L); trace_left--; }
            step();
        }
    }
    fclose(out);
    return 0;
}
