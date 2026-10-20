# Rastan → PC Engine (HuCard)

A port of Taito's *Rastan* (1987 arcade) to the PC Engine / TurboGrafx-16 HuCard.
The first target is one BG layer at 256 px wide in 8 Mbit, with the engine written in PCEAS assembly.

**No ROM data is in this repository.** You need your own MAME `rastan` set (World, rev 1).
Put the unzipped files in `roms/rastan/`, or point `RASTAN_ROMS` at them. Everything decoded
from the ROMs (`*.bin`, snapshots, renders, disassembly) is git-ignored.

## Layout

| Path | What it is |
|---|---|
| `tools/arcade_gfx.py` | ROM region loader (MAME layout) and 4bpp packed tile/sprite decoder |
| `tools/gfx_sheets.py` | Renders all 16,384 BG tiles and 4,096 sprites to PNG sheets |
| `tools/fgmap.py` | Static decoder for the foreground world map in the 68000 program ROM |
| `tools/render_map.py` | Renders the FG world strip with a palette captured from the simulator |
| `tools/snap.py`, `tools/contact.py` | Reads simulator snapshots and renders arcade frames like MAME |
| `tools/extract_roms.py` | Builds interleaved `maincpu.bin` / `pc080sn.bin` / `pc090oj.bin` |
| `tools/tgrun/` | Headless PC Engine runner (HuC's `tgemu` core): run N frames with pad input, dump the screen |
| `sim/` | Headless Rastan main-CPU simulator (Musashi 68000) and a linear disassembler |
| `sim/scripts/` | Input scripts for the simulator |

## Quick start

```sh
python3 tools/extract_roms.py roms/rastan sim
make -C sim
sim/sim sim/maincpu.bin sim/scripts/play1.txt out/play1.snp 10   # coin, start, walk right
cd tools && python3 contact.py ../out/play1.snp ../out/play1.png 700 900 1100
```

Simulator script commands: `in <frame> <p1> <sys>` (active-low pad bits; up 01, down 02,
left 04, right 08, b1 10, b2 20), `poke <from> <to> <addr> <b|w|l> <val>`,
`patch <addr> <byte>`, `end <frame>`, `trace`.

The headless runner is built with `tools/tgrun/build.sh`, after running `make` in a HuC checkout.

## Arcade notes (reverse engineering)

- Screen 320×240. PC080SN: two 64×64 tilemaps of 8×8 tiles. BG is at `$C00000`, FG at `$C08000`.
  Each tile entry is 2 words (`attr`, `code`): `attr & $1FF` = color, bit 14 = flip X, bit 15 = flip Y.
  Mapping from scroll registers: `tile_x = screen_x + 16 − scrollX`, `tile_y = screen_y − scrollY`.
- PC090OJ sprites: 16×16 4bpp, 8 bytes each, 256 entries. Color bank = `(ctrl & $E0) >> 1`. Sprites draw over everything.
- Palette: 2048 entries, xBGR555, at `$200000`.
- Reset `$03A000`. All game logic runs in the IRQ5 (vblank) handler at `$03A008`. Work RAM base `A5 = $10C000`.
- **FG world map**: 16 block rows, row `r` at `$1691C + r*$22C0`, 4-byte entries `[attr][block addr]`,
  2,224 block columns (32 px each) for the whole game. A block (in ROM `$0000–$FFFF`) is 4×4 tile words
  plus collision info at `+$20`. Streaming routines: `$055904`, `$0559B2`.
- The world splits into 139 segments of 16 block columns. `$13E` = current segment.
  `$5073A` = segment → continue checkpoint. `$502AC` = round boundaries (`$16 $2D $44 $5B $72 $89`).
- **BG layer**: `$10FC` = `$3951C + segment_bg_index*12`. The index comes from `$507C5`.
  Entries are 6 bytes, `[attr][long ptr]`, pointing to strips of 16×64 tile words. Streamer: `$055C7A`.

## Status

- [x] Arcade graphics decode
- [x] Headless arcade simulator, with frames verified against the real game's look
- [x] FG world map decoded statically from ROM
- [ ] Per-round palettes (needs a full playthrough with a health cheat)
- [ ] BG strip decode and flattening into one layer
- [ ] PCE asset converter (dedupe with flip expansion, 16-palette fit, metatiles, collision)
- [ ] Stage 1 scrolling ROM

## Licenses

Musashi (`sim/musashi/`) is © Karl Stenerud, MIT license (see `README-musashi.txt`).
*Rastan* is © Taito. This is a non-commercial fan project and distributes no Taito assets.
