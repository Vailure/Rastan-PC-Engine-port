/* Headless Rastan main-CPU simulator (68000 via Musashi).
 * Runs the arcade program with scripted inputs and records per-frame
 * snapshots of video/work RAM for asset and behavior extraction.
 * No video or sound emulation: the sound CPU link always reports "consumed".
 *
 * usage: sim maincpu.bin script.txt out.snp [every_n_frames]
 * script lines:
 *   in   <frame> <p1hex> <syshex>          set inputs from frame on (active-low bits)
 *   poke <from> <to> <addr> <b|w|l> <val>  write value at start of each frame in range
 *   end  <frame>                           stop
 *   patch <addr> <bytehex>                 patch program ROM byte before reset
 *   pcprof <from> <to> <file>              per-PC execution counts for frames from..to
 *   wtrace <lo> <hi>                       log writer PCs for an address range (with trace output)
 *   calltrace <frame> <file>               log every JSR/BSR executed in one frame
 *   watch <addr> <lenhex>                  log writes (frame, PC, addr, byte) to stderr
 *   profile <from_frame>                   per-PC instruction counts + RAM access map
 *   focus <entryhex>                       restrict profile to calls of one routine
 *   callsnap <entryhex> <file>             legacy CSNP entry regs + entry/exit RAM
 *   callsnap2 <entryhex> <file>            CSN2: also SR, exit regs, return PC, hardware writes
 *   trace                                  log PCs that write tilemap RAM (stderr at end)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <zlib.h>
#include "musashi/m68k.h"

static uint8_t rom[0x60000];
static uint8_t wram[0x4000];     /* 10c000-10ffff */
static uint8_t pal[0x1000];      /* 200000-200fff */
static uint8_t vram[0x10000];    /* c00000-c0ffff PC080SN */
static uint8_t spr[0x4000];      /* d00000-d03fff PC090OJ */
static uint16_t scry[2], scrx[2], vctrl[2], sprctrl;
static uint8_t in_p1 = 0xff, in_p2 = 0xff, in_sys = 0x1f, in_special = 0x8f;
static uint8_t dswa = 0xfe, dswb = 0xff;
static int irq_pending;
static int frame;
static int trace_on;
static int profile_on;                 /* profile: per-PC instruction counts in gameplay frames */
static uint32_t *pc_count;
static uint8_t ram_touch[0x4000];      /* bit0 read, bit1 write (work RAM) */
static int profile_from = 0x7fffffff;
static uint32_t focus_entry, focus_sp; static int in_focus;
static gzFile callsnap_f;                 /* callsnap <entry> <file>: RAM + regs at entry and exit of each call */
static uint8_t callsnap_in[0x4000]; static uint32_t callsnap_regs[16];   /* focus <entry>: profile only inside that routine */
static int callsnap_version;
static uint16_t callsnap_sr;
static uint32_t callsnap_return;
static uint8_t *callsnap_hw;
static size_t callsnap_hw_count, callsnap_hw_capacity;

static void capture_write(const void *data, unsigned len)
{
    if (gzwrite(callsnap_f, data, len) != (int)len) {
        fprintf(stderr, "callsnap write failed\n"); exit(1);
    }
}

static void capture_u32(uint32_t value)
{
    uint8_t b[4] = {value >> 24, value >> 16, value >> 8, value};
    capture_write(b, sizeof b);
}

static void capture_hw_write(uint32_t addr, uint8_t value)
{
    if (!callsnap_f || callsnap_version != 2 || !in_focus) return;
    if (callsnap_hw_count == 1000000) {
        fprintf(stderr, "callsnap hardware-write limit exceeded\n"); exit(1);
    }
    if (callsnap_hw_count == callsnap_hw_capacity) {
        size_t capacity = callsnap_hw_capacity ? callsnap_hw_capacity * 2 : 64;
        uint8_t *buffer = realloc(callsnap_hw, capacity * 5);
        if (!buffer) { fprintf(stderr, "callsnap allocation failed\n"); exit(1); }
        callsnap_hw = buffer; callsnap_hw_capacity = capacity;
    }
    uint8_t *b = callsnap_hw + callsnap_hw_count++ * 5;
    b[0] = addr >> 24; b[1] = addr >> 16; b[2] = addr >> 8; b[3] = addr; b[4] = value;
}

static uint32_t watch_lo, watch_hi;   /* watch <addr> <len>: log writes in [lo,hi) */
static FILE *watch_f;
static uint32_t wtrace_lo = 1, wtrace_hi = 0;   /* wtrace <lo> <hi>: log writer PCs for an address range */
static uint32_t cur_pc_hist[0x60000 / 2];
static uint64_t unmapped_reads, unmapped_writes; static uint32_t last_unmapped_w;

/* pcprof <from> <to> <file> : count executed instructions per PC within a frame range */
static char ct_file[256];
static int prof_from = -1, prof_to = -1; static char prof_file[256];
static uint32_t *prof_hits;
static int calltrace_frame = -1; static FILE *calltrace_out; static uint32_t ct_sp0;
void sim_instr_hook(unsigned int pc)
{
    if (prof_hits && pc < 0x60000) prof_hits[pc >> 1]++;
    if (focus_entry) {
        uint32_t sp = m68k_get_reg(NULL, M68K_REG_SP);
        if (pc == focus_entry && !in_focus) {
            in_focus = 1; focus_sp = sp;
            callsnap_return = m68k_read_memory_32(sp);
            if (callsnap_f) {
                memcpy(callsnap_in, wram, sizeof wram);
                callsnap_sr = m68k_get_reg(NULL, M68K_REG_SR);
                callsnap_hw_count = 0;
                for (int r = 0; r < 16; r++) callsnap_regs[r] = m68k_get_reg(NULL, M68K_REG_D0 + r);
            }
        }
        else if (in_focus && sp == focus_sp + 4 && pc == callsnap_return) {
            in_focus = 0;
            if (callsnap_f) {
                capture_write(callsnap_version == 2 ? "CSN2" : "CSNP", 4);
                capture_u32(frame);
                if (callsnap_version == 2) {
                    capture_u32(focus_entry);
                    capture_u32(pc);
                    uint16_t sr = m68k_get_reg(NULL, M68K_REG_SR);
                    uint8_t flags[4] = {callsnap_sr >> 8, callsnap_sr, sr >> 8, sr};
                    capture_write(flags, sizeof flags);
                    capture_u32(callsnap_hw_count);
                }
                for (int r = 0; r < 16; r++) capture_u32(callsnap_regs[r]);
                if (callsnap_version == 2)
                    for (int r = 0; r < 16; r++) capture_u32(m68k_get_reg(NULL, M68K_REG_D0 + r));
                capture_write(callsnap_in, sizeof wram);
                capture_write(wram, sizeof wram);
                if (callsnap_version == 2 && callsnap_hw_count)
                    capture_write(callsnap_hw, callsnap_hw_count * 5);
            }
        }
    }
    if (profile_on && frame >= profile_from && pc < 0x60000 && (!focus_entry || in_focus)) pc_count[pc >> 1]++;
    if (calltrace_out && pc < 0x60000) {      /* log JSR/BSR with stack depth */
        uint16_t op = (rom[pc] << 8) | rom[pc + 1];
        int depth = (int)(ct_sp0 - m68k_get_reg(NULL, M68K_REG_SP)) / 4;
        if ((op & 0xff00) == 0x6100 || (op & 0xffc0) == 0x4e80) {
            char buf[128]; m68k_disassemble(buf, pc, M68K_CPU_TYPE_68000);
            fprintf(calltrace_out, "%*s%06x %s\n", depth > 0 ? depth * 2 : 0, "", pc, buf);
        }
    }
}

int sim_int_ack(int level) { (void)level; irq_pending = 0; m68k_set_irq(0); return M68K_INT_ACK_AUTOVECTOR; }

static inline uint16_t rd16(const uint8_t *p, uint32_t a) { return (p[a] << 8) | p[a + 1]; }

static uint8_t read8(uint32_t a)
{
    a &= 0xffffff;
    if (profile_on && frame >= profile_from && a >= 0x10c000 && a < 0x110000 && (!focus_entry || in_focus)) ram_touch[a - 0x10c000] |= 1;
    if (a < 0x60000) return rom[a];
    if (a >= 0x10c000 && a < 0x110000) return wram[a - 0x10c000];
    if (a >= 0x200000 && a < 0x201000) return pal[a - 0x200000];
    if (a >= 0xc00000 && a < 0xc10000) return vram[a - 0xc00000];
    if (a >= 0xd00000 && a < 0xd04000) return spr[a - 0xd00000];
    switch (a) {   /* inputs are on the low byte of each word */
    case 0x390001: return in_p1;
    case 0x390003: return in_p2;
    case 0x390005: return in_special;
    case 0x390007: return in_sys;
    case 0x390009: return dswa;
    case 0x39000b: return dswb;
    case 0x390000: case 0x390002: case 0x390004: case 0x390006: case 0x390008: case 0x39000a: return 0xff;
    case 0x3e0003: return 0;  /* sound comm: data 0 / status "all consumed" */
    }
    unmapped_reads++;
    return 0;
}

static void write8(uint32_t a, uint8_t v)
{
    a &= 0xffffff;
    if (watch_f && a >= watch_lo && a < watch_hi)
        fprintf(watch_f, "W %d %06x %06x %02x\n", frame, m68k_get_reg(NULL, M68K_REG_PPC), a, v);
    if (a >= wtrace_lo && a < wtrace_hi) { uint32_t pc = m68k_get_reg(NULL, M68K_REG_PPC); if (pc < 0x60000) cur_pc_hist[pc >> 1]++; }
    if (a >= 0x10c000 && a < 0x110000) {
        if (profile_on && frame >= profile_from && (!focus_entry || in_focus)) ram_touch[a - 0x10c000] |= 2;
        wram[a - 0x10c000] = v; return;
    }
    capture_hw_write(a, v);
    if (a >= 0x200000 && a < 0x201000) { pal[a - 0x200000] = v; return; }
    if (a >= 0xc00000 && a < 0xc10000) {
        vram[a - 0xc00000] = v;
        if (trace_on) { uint32_t pc = m68k_get_reg(NULL, M68K_REG_PPC); if (pc < 0x60000) cur_pc_hist[pc >> 1]++; }
        return;
    }
    if (a >= 0xd00000 && a < 0xd04000) { spr[a - 0xd00000] = v; return; }
    if (a >= 0xc20000 && a < 0xc20004) { uint16_t *r = &scry[(a >> 1) & 1]; if (a & 1) *r = (*r & 0xff00) | v; else *r = (*r & 0xff) | (v << 8); return; }
    if (a >= 0xc40000 && a < 0xc40004) { uint16_t *r = &scrx[(a >> 1) & 1]; if (a & 1) *r = (*r & 0xff00) | v; else *r = (*r & 0xff) | (v << 8); return; }
    if (a >= 0xc50000 && a < 0xc50004) { uint16_t *r = &vctrl[(a >> 1) & 1]; if (a & 1) *r = (*r & 0xff00) | v; else *r = (*r & 0xff) | (v << 8); return; }
    if (a == 0x380000 || a == 0x380001) { if (a & 1) sprctrl = (sprctrl & 0xff00) | v; else sprctrl = (sprctrl & 0xff) | (v << 8); return; }
    if ((a & ~1u) == 0x350008 || (a & ~1u) == 0x3c0000 || (a & ~3u) == 0x3e0000) return;
    unmapped_writes++; last_unmapped_w = a;
}

unsigned int m68k_read_memory_8(unsigned int a) { return read8(a); }
unsigned int m68k_read_memory_16(unsigned int a) { return (read8(a) << 8) | read8(a + 1); }
unsigned int m68k_read_memory_32(unsigned int a) { return (m68k_read_memory_16(a) << 16) | m68k_read_memory_16(a + 2); }
void m68k_write_memory_8(unsigned int a, unsigned int v) { write8(a, v); }
void m68k_write_memory_16(unsigned int a, unsigned int v) { write8(a, v >> 8); write8(a + 1, v); }
void m68k_write_memory_32(unsigned int a, unsigned int v) { m68k_write_memory_16(a, v >> 16); m68k_write_memory_16(a + 2, v); }
unsigned int m68k_read_disassembler_8(unsigned int a) { return read8(a); }
unsigned int m68k_read_disassembler_16(unsigned int a) { return m68k_read_memory_16(a); }
unsigned int m68k_read_disassembler_32(unsigned int a) { return m68k_read_memory_32(a); }

typedef struct { int kind, from, to; uint32_t addr; char size; uint32_t val; uint8_t p1, sys; } cmd_t;
#define MAX_CMDS 200000
static cmd_t cmds[MAX_CMDS];
static int ncmds, end_frame = 3600;

static void load_script(const char *fn)
{
    FILE *f = fopen(fn, "r");
    if (!f) { perror(fn); exit(1); }
    char line[256];
    while (fgets(line, sizeof line, f)) {
        cmd_t c = {0};
        unsigned p1, sys, addr, val; int a, b; char sz;
        if (sscanf(line, "in %d %x %x", &a, &p1, &sys) == 3) { c.kind = 1; c.from = a; c.p1 = p1; c.sys = sys; }
        else if (sscanf(line, "poke %d %d %x %c %x", &a, &b, &addr, &sz, &val) == 5) { c.kind = 2; c.from = a; c.to = b; c.addr = addr; c.size = sz; c.val = val; }
        else if (sscanf(line, "patch %x %x", &addr, &val) == 2) { rom[addr] = val; continue; }
        else if (sscanf(line, "end %d", &a) == 1) { end_frame = a; continue; }
        else if (sscanf(line, "calltrace %d %255s", &a, prof_file) == 2) { calltrace_frame = a; strcpy(ct_file, prof_file); continue; }
        else if (sscanf(line, "pcprof %d %d %255s", &a, &b, prof_file) == 3) { prof_from = a; prof_to = b; continue; }
        else if (sscanf(line, "wtrace %x %x", &addr, &val) == 2) { wtrace_lo = addr; wtrace_hi = val; trace_on = 1; continue; }
        else if (strncmp(line, "trace", 5) == 0) { trace_on = 1; continue; }
        else if (sscanf(line, "focus %x", &addr) == 1) { focus_entry = addr; continue; }
        else if (sscanf(line, "callsnap2 %x %255s", &addr, ct_file) == 2 ||
                 sscanf(line, "callsnap %x %255s", &addr, ct_file) == 2) {
            if (callsnap_f) { fprintf(stderr, "only one callsnap command is allowed\n"); exit(1); }
            focus_entry = addr;
            callsnap_version = strncmp(line, "callsnap2", 9) == 0 ? 2 : 1;
            callsnap_f = gzopen(ct_file, "wb1");
            if (!callsnap_f) { perror(ct_file); exit(1); }
            continue;
        }
        else if (sscanf(line, "profile %d", &a) == 1) { profile_on = 1; profile_from = a; continue; }
        else if (sscanf(line, "watch %x %x", &addr, &val) == 2) { watch_lo = addr; watch_hi = addr + val; if (!watch_f) watch_f = stderr; continue; }
        else continue;
        if (ncmds == MAX_CMDS) { fprintf(stderr, "too many script lines\n"); exit(1); }
        cmds[ncmds++] = c;
    }
    fclose(f);
}

static void write_snapshot(gzFile g)
{
    uint8_t hdr[32] = {'R', 'S', 'N', 'P'};
    hdr[4] = frame >> 24; hdr[5] = frame >> 16; hdr[6] = frame >> 8; hdr[7] = frame;
    hdr[8] = in_p1; hdr[9] = in_sys;
    uint16_t regs[] = {scry[0], scry[1], scrx[0], scrx[1], vctrl[0], vctrl[1], sprctrl};
    for (int i = 0; i < 7; i++) { hdr[10 + i * 2] = regs[i] >> 8; hdr[11 + i * 2] = regs[i]; }
    gzwrite(g, hdr, 32);
    gzwrite(g, vram, sizeof vram);
    gzwrite(g, pal, sizeof pal);
    gzwrite(g, spr, 0x800);
    gzwrite(g, wram, sizeof wram);
}

int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "usage: sim maincpu.bin script.txt out.snp [every]\n"); return 1; }
    FILE *f = fopen(argv[1], "rb");
    if (!f || fread(rom, 1, sizeof rom, f) != sizeof rom) { fprintf(stderr, "bad rom\n"); return 1; }
    fclose(f);
    pc_count = calloc(0x30000, sizeof *pc_count);
    load_script(argv[2]);
    int every = argc > 4 ? atoi(argv[4]) : 1;
    gzFile g = gzopen(argv[3], "wb1");

    in_sys = 0x1f;   /* coin bits active high -> idle 0 */
    m68k_init();
    m68k_set_cpu_type(M68K_CPU_TYPE_68000);
    m68k_pulse_reset();

    const int cycles_per_frame = 8000000 / 60;
    for (frame = 0; frame < end_frame; frame++) {
        for (int i = 0; i < ncmds; i++) {
            cmd_t *c = &cmds[i];
            if (c->kind == 1 && c->from == frame) { in_p1 = c->p1; in_sys = c->sys; }
            if (c->kind == 2 && frame >= c->from && frame <= c->to) {
                if (c->size == 'b') write8(c->addr, c->val);
                else if (c->size == 'w') m68k_write_memory_16(c->addr, c->val);
                else m68k_write_memory_32(c->addr, c->val);
            }
        }
        if (frame == calltrace_frame) { calltrace_out = fopen(ct_file, "w"); ct_sp0 = m68k_get_reg(NULL, M68K_REG_SP); }
        if (frame == prof_from) prof_hits = calloc(0x30000, sizeof *prof_hits);
        m68k_execute(cycles_per_frame);
        if (calltrace_out && frame == calltrace_frame) { fclose(calltrace_out); calltrace_out = NULL; }
        if (frame == prof_to && prof_hits) {
            FILE *pf = fopen(prof_file, "w");
            for (uint32_t i = 0; i < 0x30000; i++) if (prof_hits[i]) fprintf(pf, "%06x %u\n", i * 2, prof_hits[i]);
            fclose(pf); free(prof_hits); prof_hits = NULL;
        }
        if (frame % every == 0) write_snapshot(g);
        /* vblank at end of frame: IRQ5, held until acknowledged */
        irq_pending = 1;
        m68k_set_irq(5);
    }
    gzclose(g);
    if (callsnap_f && gzclose(callsnap_f) != Z_OK) {
        fprintf(stderr, "callsnap close failed\n"); return 1;
    }
    free(callsnap_hw);
    if (callsnap_version && in_focus) {
        fprintf(stderr, "incomplete callsnap call at end of run\n"); return 1;
    }
    fprintf(stderr, "frames=%d pc=%06x unmapped r=%llu w=%llu last_w=%06x\n", frame, (unsigned)m68k_get_reg(NULL, M68K_REG_PC),
            (unsigned long long)unmapped_reads, (unsigned long long)unmapped_writes, last_unmapped_w);
    if (profile_on) {
        FILE *pf = fopen("profile.out", "w");
        for (uint32_t i = 0; i < 0x30000; i++) if (pc_count[i]) fprintf(pf, "%06x %u\n", i * 2, pc_count[i]);
        fclose(pf);
        pf = fopen("ramtouch.bin", "wb"); fwrite(ram_touch, 1, sizeof ram_touch, pf); fclose(pf);
        fprintf(stderr, "wrote profile.out, ramtouch.bin (from frame %d)\n", profile_from);
    }
    if (trace_on) {
        char buf[128];
        for (uint32_t i = 0; i < 0x30000; i++) if (cur_pc_hist[i]) {
            m68k_disassemble(buf, i * 2, M68K_CPU_TYPE_68000);
            fprintf(stderr, "TRACE %06x %8u  %s\n", i * 2, cur_pc_hist[i], buf);
        }
    }
    return 0;
}

