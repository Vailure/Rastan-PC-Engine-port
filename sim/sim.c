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
static uint32_t cur_pc_hist[0x60000 / 2];
static uint64_t unmapped_reads, unmapped_writes;

int sim_int_ack(int level) { (void)level; irq_pending = 0; m68k_set_irq(0); return M68K_INT_ACK_AUTOVECTOR; }

static inline uint16_t rd16(const uint8_t *p, uint32_t a) { return (p[a] << 8) | p[a + 1]; }

static uint8_t read8(uint32_t a)
{
    a &= 0xffffff;
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
    if (a >= 0x10c000 && a < 0x110000) { wram[a - 0x10c000] = v; return; }
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
    unmapped_writes++;
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
static cmd_t cmds[4096];
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
        else if (strncmp(line, "trace", 5) == 0) { trace_on = 1; continue; }
        else continue;
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
        m68k_execute(cycles_per_frame);
        if (frame % every == 0) write_snapshot(g);
        /* vblank at end of frame: IRQ5, held until acknowledged */
        irq_pending = 1;
        m68k_set_irq(5);
    }
    gzclose(g);
    fprintf(stderr, "frames=%d pc=%06x unmapped r=%llu w=%llu\n", frame, m68k_get_reg(NULL, M68K_REG_PC),
            (unsigned long long)unmapped_reads, (unsigned long long)unmapped_writes);
    if (trace_on) {
        char buf[128];
        for (uint32_t i = 0; i < 0x30000; i++) if (cur_pc_hist[i]) {
            m68k_disassemble(buf, i * 2, M68K_CPU_TYPE_68000);
            fprintf(stderr, "TRACE %06x %8u  %s\n", i * 2, cur_pc_hist[i], buf);
        }
    }
    return 0;
}
