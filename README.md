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
| `tools/bgmap.py` | Static decoder for the background strips |
| `tools/pce_stage.py` | Arcade stage → PCE data: composite, palettes, VRAM streaming schedule |
| `tools/test_scroll.py` | Scrolls the ROM headless and checks every frame pixel-for-pixel |
| `src/main.asm` | PC Engine engine (PCEAS, using HuC's core library) |
| `tools/render_map.py` | Renders the FG world strip with a palette captured from the simulator |
| `tools/snap.py`, `tools/contact.py` | Reads simulator snapshots and renders arcade frames like MAME |
| `tools/extract_roms.py` | Builds interleaved `maincpu.bin` / `pc080sn.bin` / `pc090oj.bin` |
| `tools/tgrun/` | Headless PC Engine runner: run N frames with pad input, dump screens (`TGRUN_DUMP`) or RAM (`TGRUN_PEEK`) |
| `tools/tgemu/` | HuC's `tgemu` emulator core (GPLv2), patched for 2.5 MB ROMs and the SF2 mapper |
| `tools/pce_player.py` | Rastan's poses → PCE sprites, animation and jump tables, stage collision |
| `tools/trace_player.py` | Runs the ROM headless and prints Rastan's state per frame |
| `tools/m68k/`, `tools/lockstep.py` | 68000 decoder and reference interpreter, checked call-by-call against the arcade |
| `tools/callgraph.py` | Code reachable from a routine |
| `src/player.asm` | Rastan: states, movement, collision, ropes, camera, sprite streaming |
| `sim/` | Headless Rastan main-CPU simulator (Musashi 68000) and a linear disassembler |
| `sim/scripts/` | Input scripts for the simulator |

## Building the ROM

Requirements: Python 3 with numpy and Pillow, gcc and zlib, and a built checkout of
[HuC](https://github.com/pce-devel/huc), which provides `pceas` and the `tgemu` core used by the tests.

```sh
make HUC=/path/to/huc          # -> build/rastan.pce
make HUC=/path/to/huc test     # scroll the ROM headless and compare with the converter preview
python3 tools/trace_player.py build/rastan.pce 600 60 300 04   # walk right, print Rastan's state
```

The build:
1. Extracts the ROM regions.
2. Runs the arcade program in the simulator to capture round 1's palette.
3. Converts round 1 (`tools/pce_stage.py`).
4. Assembles `src/main.asm`.

**Controls:**
- LEFT/RIGHT: walk
- DOWN: crouch
- I: jump (UP+I for the high jump; a direction for a forward jump)
- II: attack, standing or crouched; also works in the air
- UP: grab a rope; UP and DOWN climb it, and I jumps off

The camera only scrolls forward. Falling off the bottom of the map restarts the stage.

## Simulator quick start

```sh
python3 tools/extract_roms.py roms/rastan sim
make -C sim
sim/sim sim/maincpu.bin sim/scripts/play1.txt out/play1.snp 10   # coin, start, walk right
cd tools && python3 contact.py ../out/play1.snp ../out/play1.png 700 900 1100
```

## How stage 1 is converted (`tools/pce_stage.py`)

- **One layer:** the arcade FG layer is composited over the BG layer locked to the same scroll
  speed (1:1). Round 1's BG uses only 5 distinct strips, so they are repeated to cover the FG.
  Parallax is lost for now and can come back later with raster splits.
- **Colors:** quantized to 9-bit RGB, with one shared color 0 (the most common color).
  Tiles are greedily packed into 16 palettes of 15 colors. Round 1 has 71 distinct colors after quantization.
- **VRAM streaming:** round 1 has 3,343 unique 8x8 patterns, but VRAM holds 1,024.
  Since the stage scrolls forward only, the converter simulates a cache offline.
  The resident window is 35 columns (33 visible, 1 preloaded, 1 lagging so that tiles still on screen
  are never overwritten). Peak use is 928 of 1,024 slots.
  Each column record carries the patterns it needs uploaded, plus its 64 BAT words.
- **Size:** round 1 is 488 KB. Compressing the BAT columns and patterns is a later task,
  because six rounds at this rate would not fit in 8 Mbit.

VRAM layout: BAT `$0000`, streamed tiles `$1000-$4FFF` (#`$100-$4FF`), Rastan's two sprite pattern
buffers `$5000`/`$5600`, SATB `$7F00`.

## Rastan (milestone 2, approximate)

`src/player.asm` is hand-written and approximate, built from values measured in the arcade program:

| What | Arcade source |
|---|---|
| Position | `$10BE` x, `$10C0` y, screen-relative; feet at y+24 |
| State | `$10E8`: 0 idle, 1 walk, 2 rising, 3 falling, 4 rope, 5 crouch, 8 dead |
| Walk | 1 px/frame for 15 frames, then 2 px/frame (`$05263A`) |
| Jump | per-frame (dx, up) tables: `$5B548` low, `$5B516` high, `$5B5A2`/`$5B570` forward. Falling replays the table backwards |
| Input edges | `$136E` jump, `$13CA` attack: 1 pressed, `$11` held, `$FE` released, `$FF` idle |
| Collision | 8x8 code map at `$10DE00`, filled from each block's `+$20` data. Low 7 bits: 1 solid, 2 rope, 3/4/7 floors with special effects, 6/8 waterfall/hazard. High byte: spawn markers |
| Camera | scrolls when x passes 160 (right) or 80 (left); y dead zone 64..112 |

`tools/pce_player.py` captures Rastan's 27 poses from the arcade's own sprite list while
`sim/scripts/actions.txt` makes him walk, crouch, attack and jump. The rope poses come from the attract demo.
Animation timings are measured from the same runs.

Not done yet: enemies and damage, slopes, waterfall currents, the other collision codes, rope attacks,
weapon pickups, and leftward scrolling.

### Exact port (in progress, tooling only)

The plan for arcade-exact behavior is to translate the player code itself: 2,577 instructions reachable from `$05132A`,
about 1,100 executed per frame. `tools/m68k/` holds a decoder and a reference interpreter for the 68000 subset it uses.
`sim` records RAM at each call's entry and exit (`callsnap`). `tools/lockstep.py` replays every call through the
interpreter and compares all 16 KB of work RAM. It currently matches the arcade on 9,215 of 9,215 recorded calls,
including randomized input. A HuC6280 back end is the next step there.

## Street Fighter II mapper

Later rounds will need more than 8 Mbit, so the ROM will use the SF2 mapper (up to 2.5 MB). PCEAS supports it: data in
file banks `$80+` is selected by writing to `$1FF0-$1FF3`. `tools/tgemu/` is HuC's `tgemu` (GPLv2) with the mapper
added, used by `tools/tgrun`.

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
- [x] BG strip decode (`tools/bgmap.py`) and flattening into one layer
- [x] PCE stage converter: 16-palette fit and offline VRAM streaming schedule
- [x] Stage 1 scrolling ROM, verified pixel-exact against the converter in the headless emulator
- [ ] Per-round palettes for rounds 2-6. Needs a full playthrough; the bot still dies in pits, and
      `$10D2A6` is only a *candidate* health counter.
- [ ] Palette cycling (arcade BG palette 2 animates)
- [ ] Data compression (metatiles, LZ)
- [x] Rastan (approximate): walk, crouch, attacks, jumps, ropes, collision, camera
- [ ] Rastan (exact): translate the arcade player code (interpreter done and verified)
- [ ] Enemies

## Licenses

Musashi (`sim/musashi/`) is © Karl Stenerud, MIT license (see `README-musashi.txt`).
*Rastan* is © Taito. This is a non-commercial fan project and distributes no Taito assets.
