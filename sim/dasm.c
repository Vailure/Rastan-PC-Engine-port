/* dasm maincpu.bin start end : linear 68000 disassembly */
#include <stdio.h>
#include <stdlib.h>
#include "musashi/m68k.h"
static unsigned char rom[0x60000];
static unsigned r8(unsigned a) { a &= 0xffffff; return a < sizeof rom ? rom[a] : 0; }
unsigned int m68k_read_disassembler_8(unsigned int a) { return r8(a); }
unsigned int m68k_read_disassembler_16(unsigned int a) { return (r8(a) << 8) | r8(a + 1); }
unsigned int m68k_read_disassembler_32(unsigned int a) { return (m68k_read_disassembler_16(a) << 16) | m68k_read_disassembler_16(a + 2); }
unsigned int m68k_read_memory_8(unsigned int a) { return r8(a); }
unsigned int m68k_read_memory_16(unsigned int a) { return m68k_read_disassembler_16(a); }
unsigned int m68k_read_memory_32(unsigned int a) { return m68k_read_disassembler_32(a); }
void m68k_write_memory_8(unsigned int a, unsigned int v) {}
void m68k_write_memory_16(unsigned int a, unsigned int v) {}
void m68k_write_memory_32(unsigned int a, unsigned int v) {}
int sim_int_ack(int l) { return 0; }
int main(int argc, char **argv)
{
    FILE *f = fopen(argv[1], "rb"); fread(rom, 1, sizeof rom, f); fclose(f);
    unsigned pc = strtoul(argv[2], 0, 16), end = strtoul(argv[3], 0, 16);
    char buf[256];
    while (pc < end) {
        unsigned n = m68k_disassemble(buf, pc, M68K_CPU_TYPE_68000);
        printf("%06x  ", pc);
        for (unsigned i = 0; i < 6; i++) printf(i * 2 < n ? "%04x " : "     ", m68k_read_disassembler_16(pc + i * 2));
        printf(" %s\n", buf);
        pc += n;
    }
    return 0;
}
