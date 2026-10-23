/* tgrun rom.pce frames out.ppm [hold_from hold_to padhex]...
 * Headless: run N frames with optional pad input ranges, write final screen (RGB565 -> PPM). */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "shared.h"
#include "pce.h"
#include "vce.h"
#include "vdc.h"

#define SCR_W 352
#define SCR_H 240
void dump_screen(void) {}  /* illegal-opcode hook used by HuC tests; ignore */

static void write_ppm(const char *fn, const uint16_t *pixels)
{
    FILE *o = fopen(fn, "wb");
    if (!o) { perror(fn); exit(1); }
    fprintf(o, "P6 %d %d 255\n", SCR_W, SCR_H);
    for (int i = 0; i < SCR_W * SCR_H; i++) {
        uint16_t p = pixels[i];
        unsigned char rgb[3] = {(p >> 11) << 3, ((p >> 5) & 63) << 2, (p & 31) << 3};
        fwrite(rgb, 3, 1, o);
    }
    fclose(o);
}

int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "usage: tgrun rom frames out.ppm [from to padhex]...\n"); return 1; }
    if (load_rom(argv[1], 0, 0) != 1) { fprintf(stderr, "load failed\n"); return 1; }
    int frames = atoi(argv[2]);
    int peek_off = 0, peek_len = 0;
    char dump_dir[256] = ""; int dump_every = 0;
    if (getenv("TGRUN_DUMP")) sscanf(getenv("TGRUN_DUMP"), "%255[^,],%d", dump_dir, &dump_every);
    if (getenv("TGRUN_PEEK")) sscanf(getenv("TGRUN_PEEK"), "%x,%d", &peek_off, &peek_len);
    static uint16_t pixels[SCR_W * SCR_H];
    bitmap.width = SCR_W; bitmap.height = SCR_H; bitmap.depth = 16; bitmap.granularity = 2;
    bitmap.data = (uint8 *)pixels; bitmap.pitch = SCR_W * 2;
    bitmap.viewport.w = 256; bitmap.viewport.h = 240; bitmap.viewport.x = 0x20; bitmap.viewport.y = 0;
    system_init(44100);
    system_reset();
    FILE *wav = NULL;                    /* TGRUN_WAV=file : 44.1 kHz stereo of the PSG */
    long wav_samples = 0;
    if (getenv("TGRUN_WAV")) {
        wav = fopen(getenv("TGRUN_WAV"), "wb");
        if (wav) { char hdr[44] = {0}; fwrite(hdr, 1, 44, wav); snd.enabled = 1; }
    }
    FILE *satb = getenv("TGRUN_SATB") ? fopen(getenv("TGRUN_SATB"), "wb") : NULL;
    for (int f = 0; f < frames; f++) {
        input.pad[0] = 0;
        for (int i = 4; i + 2 < argc; i += 3)
            if (f >= atoi(argv[i]) && f <= atoi(argv[i + 1])) input.pad[0] |= strtoul(argv[i + 2], 0, 16);
        bitmap.data = (uint8 *)pixels;
        system_frame(0);
        if (dump_every && f % dump_every == 0) {   /* TGRUN_DUMP=dir,every : write frames as PPM */
            char fn[512];
            snprintf(fn, sizeof fn, "%s/%05d.ppm", dump_dir, f);
            write_ppm(fn, pixels);
        }
        if (wav) {
            for (int i = 0; i < snd.buffer_size; i++) {
                int16_t lr[2] = { snd.buffer[0][i], snd.buffer[1][i] };
                fwrite(lr, 2, 2, wav);
            }
            wav_samples += snd.buffer_size;
        }
        if (satb) fwrite(objram, 1, 0x200, satb);  /* TGRUN_SATB=file : the sprite table shown, each frame */
        if (peek_len) {           /* TGRUN_PEEK=offset,len : dump RAM ($2000+offset) each frame */
            printf("%5d:", f);
            for (int i = 0; i < peek_len; i++) printf(" %02x", ram[peek_off + i]);
            printf("\n");
        }
    }
    if (wav) {                           /* fill in the RIFF header now the length is known */
        long data = wav_samples * 4, riff = 36 + data;
        unsigned char h[44] = "RIFF....WAVEfmt ";
        int rate = 44100, bps = rate * 4;
        memcpy(h + 4, &riff, 4);
        unsigned fmt = 16, pcm = 1, ch = 2, blk = 4, bits = 16;
        memcpy(h + 16, &fmt, 4); memcpy(h + 20, &pcm, 2); memcpy(h + 22, &ch, 2);
        memcpy(h + 24, &rate, 4); memcpy(h + 28, &bps, 4); memcpy(h + 32, &blk, 2);
        memcpy(h + 34, &bits, 2); memcpy(h + 36, "data", 4); memcpy(h + 40, &data, 4);
        fseek(wav, 0, SEEK_SET); fwrite(h, 1, 44, wav); fclose(wav);
    }
    if (satb) fclose(satb);
    write_ppm(argv[3], pixels);
    if (getenv("TGRUN_VCE")) {         /* TGRUN_VCE=file : dump the 512 VCE colors (words) at the end */
        FILE *v = fopen(getenv("TGRUN_VCE"), "wb");
        fwrite(vce.data, 1, 0x400, v);
        fclose(v);
    }
    if (getenv("TGRUN_VRAM")) {        /* TGRUN_VRAM=file : dump the 64KB of VRAM at the end */
        FILE *v = fopen(getenv("TGRUN_VRAM"), "wb");
        fwrite(vram, 1, 0x10000, v);
        fclose(v);
    }
    return 0;
}
