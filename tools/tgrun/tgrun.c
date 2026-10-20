/* tgrun rom.pce frames out.ppm [hold_from hold_to padhex]...
 * Headless: run N frames with optional pad input ranges, write final screen (RGB565 -> PPM). */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "shared.h"

#define SCR_W 352
#define SCR_H 240
void dump_screen(void) {}  /* illegal-opcode hook used by HuC tests; ignore */

int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "usage: tgrun rom frames out.ppm [from to padhex]...\n"); return 1; }
    if (load_rom(argv[1], 0, 0) != 1) { fprintf(stderr, "load failed\n"); return 1; }
    int frames = atoi(argv[2]);
    static uint16_t pixels[SCR_W * SCR_H];
    bitmap.width = SCR_W; bitmap.height = SCR_H; bitmap.depth = 16; bitmap.granularity = 2;
    bitmap.data = (uint8 *)pixels; bitmap.pitch = SCR_W * 2;
    bitmap.viewport.w = 256; bitmap.viewport.h = 240; bitmap.viewport.x = 0x20; bitmap.viewport.y = 0;
    system_init(44100);
    system_reset();
    for (int f = 0; f < frames; f++) {
        input.pad[0] = 0;
        for (int i = 4; i + 2 < argc; i += 3)
            if (f >= atoi(argv[i]) && f <= atoi(argv[i + 1])) input.pad[0] |= strtoul(argv[i + 2], 0, 16);
        bitmap.data = (uint8 *)pixels;
        system_frame(0);
    }
    FILE *o = fopen(argv[3], "wb");
    fprintf(o, "P6 %d %d 255\n", SCR_W, SCR_H);
    for (int i = 0; i < SCR_W * SCR_H; i++) {
        uint16_t p = pixels[i];
        unsigned char rgb[3] = {(p >> 11) << 3, ((p >> 5) & 63) << 2, (p & 31) << 3};
        fwrite(rgb, 3, 1, o);
    }
    fclose(o);
    return 0;
}
