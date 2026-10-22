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
| `src/player.asm` | Rastan: states, movement, collision, ropes, damage, camera, sprite streaming |
| `src/enemies.asm` | Stage 1 enemies and the object system (per-slot sprite buffers, uploads in VBLANK) |
| `src/items.asm` | Weapon items and their bats |
| `src/chimera.asm` | Chimeras and their fireballs |
| `src/boulder.asm` | Boulders (rockfall, rolling) |
| `src/hud.asm`, `tools/pce_hud.py` | HUD from the arcade's HUD sprites |
| `src/debug.asm` | Checkpoints (death restarts, warps) and the debug menu |
| `tools/test_debug.py` | Checks the menu, warps, invincibility and checkpoint restarts |
| `src/dyncolor.asm` | Waterfall color cycle and the sky change (VCE lists from `pce_stage.py`) |
| `tools/test_effects.py` | Checks the waterfall cycle, sky switch, hazards and death |
| `tools/pce_objects.py`, `tools/object_specs.py` | Object poses (enemies, projectiles, items) from the arcade's object slots → PCE sprites |
| `tools/census_all.py`, `tools/track.py` | Every arcade object of a run with its sprite pieces; one slot over time |
| `tools/test_enemies.py` | Headless checks for hits, kills and frame budget |
| `tools/test_monsters.py` | Checks round 1's later enemies (chimeras, ...) |
| `tools/test_items.py`, `tools/peek.py` | Checks weapons, items and bats; reads named RAM variables from a headless run |
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
- II: attack, standing or crouched; in a jump, DOWN+II is the down thrust and UP+II the up thrust
- UP: grab a rope; UP and DOWN climb it, and I jumps off

The camera only scrolls forward. A death restarts at the last checkpoint reached, as in the arcade.

**Debug menu:** SELECT opens it and freezes the game (RUN held + SELECT is still the core's soft reset).
UP/DOWN pick a line, LEFT/RIGHT change a value, I applies, SELECT or II closes.

| Line | What it does |
|---|---|
| Warp to checkpoint 0-5 | Restart at one of the arcade's round 1 checkpoints (segments 0, 4, 8, 12, 16, 19) |
| Invincible | Enemies, water and deadly tiles do no harm (falling off the map still kills) |
| Enemies | Walkers on/off (items and their bats still come) |
| Refill health | Full health bar |
| Lives | 1-9 |
| Slow motion | Game logic at 1/2, 1/4 or 1/8 speed |
| Weapon | 1 sword, 2 axe, 3 morning star, 4 fire sword (for 3000 frames) |
| Resume | Close the menu |

The header shows Rastan's world position and the current checkpoint.

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

VRAM layout: BAT `$0000`, streamed tiles `$1000-$4BFF`, props `$4C00`, Rastan's two sprite pattern
buffers `$5000`/`$5600` (20 body cells + 4 weapon cells each), object buffers `$5C00-$767F`, HUD `$7700`, SATB `$7F00`.

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

Not done yet: slopes, waterfall currents, the other collision codes, rope attacks, and leftward scrolling.

### Damage and enemies (milestone 3, approximate)

- **Health:** Rastan has 12 units of health (the arcade's 12288 at `$10C13A`, 3072 per lizardman hit).
  Each hit knocks him back with the hurt animation and gives 90 frames of invulnerability.
  When health runs out, the stage restarts.
- **Sword hitboxes:** standing, crouched and jump swings reach 56 px in front of him; the down
  and up thrusts hit below and above him.
- **Weapons** (arcade `$10D2FA`; timer `$10D326`): the sword, or an item's axe, morning star or fire sword for
  3000 frames, back to the sword at the end or on a death. Rastan's sprite in the arcade is three parts, each from
  its own ROM table: body, legs and weapon, with the weapon frame chosen by `$10D244`. The port keeps the body and
  legs as its composited poses and draws the weapon as up to 4 extra sprites behind them, taken straight from the
  weapon's ROM table for the pose's weapon frame (`tools/pce_player.py` checks every captured pose's weapon pieces
  against that table). Only the morning star reaches further: 88 px, and 16 px more for the thrusts. The fire sword's
  flame cycles its cells (+0/+2/+4/+6, 2 frames each); only its 2 cells are re-uploaded.
- **Items and bats** (`src/items.asm`; `sim/scripts/item.txt`, `item_fire.txt`, `item_star.txt`): four items hang
  in round 1: axes at x 1004 (in the cave) and 3854, the fire sword at 2893, the morning star at 6829. Each appears
  when Rastan is 164 px left of it, with a bat 20 px below. Touching an item, or hitting it with the weapon, takes it.
  The bat flies off away from Rastan (about 75 frames), hovers over him, dives onto him and clings: 1024 health
  (4 bar units) when it brushes him in flight, 2048 (8 units) every 45 frames while clinging, no knockback.
  One hit kills it. A death brings the items back.
- **Lizardmen** (`src/enemies.asm`): measured in the arcade from `sim/scripts/lizard.txt`. They enter at
  the right edge, walk at 7/8 px/frame, swing twice when about 52 px away, back off, and come again.
  One sword hit kills them. Up to 4 at once (the arcade's limit); their 83 sprite cells stay resident in VRAM at `$5C00`.
- **Spawns:** the arcade marks enemy lanes in the map: spawn marker `$3A` in the high byte of a cell's collision
  code, at an enemy's anchor height (16 px above its floor). A lizardman enters at the right edge on the lane nearest
  Rastan's height, 65 frames into the round and then at gaps of 49, 81 and 65 frames in turn (measured with a
  passive Rastan, `tools/object_census.py`). No lane at the edge, no lizardman. The port's collision map keeps the
  code's low nibble (all the engine tests) and the lane flag in bit 4.
- **Blue club throwers** (four-armed, sprite cells `$2E8`..; `sim/scripts/blue.txt` at checkpoint 2): from world
  x 1500 they take turns with lizardmen. They walk up the same way, stop 88-143 px from Rastan and throw two clubs
  (8 and 27 frames into a 36-frame throw), back off and come again. Clubs are projectile objects (arcade slots at
  `$10C740`): 1.5 px/frame, spinning through 8 cells; a high pair (20 px above the thrower's anchor) then a low pair
  (13 px above, sinking to 6). A club costs 3072 like a lizardman's hit; the sword knocks clubs away; one hit kills
  the thrower, with the shared explosion.
- **Chimeras** (`src/chimera.asm`; `sim/scripts/chimera.txt`): from x 2400 throwers, chimeras and lizardmen come
  in turn. A chimera walks left at 1/2 px/frame whatever Rastan does, stops once to breathe fire (about 113 frames;
  fireballs leave 24 px ahead and 6 px up, 33 and 81 frames in), then walks on. Fireballs fly left at 1.75 px/frame.
  Touching either hurts like a club; one hit kills a chimera (300) and knocks a fireball away. Poses that only shake
  (same cells a few px apart) are merged by the converter, so they need no new uploads.
- **Boulders** (`src/boulder.asm`): appear when Rastan is 169 px left of their spot, hop, and fall at 2 px/frame. The
  two at x 2898 fall through everything and wrap from the bottom of the world to the top (a rockfall); the ones at
  4601 and 6674 land (9 px above the floor), roll left at 7/6 px/frame and drop off ledges. Touching one hurts.
- **Object slots:** 0-3 walkers (12 cells each), 4 item and 5 its bat (4 cells), 6-8 specials such as boulders
  (12 cells), 9-16 projectiles (2 cells): 108 cells at `$5C00-$76FF`.
- **Object sprites:** each object slot has its own VRAM buffer (see Object slots).
  When an object's pose changes, its cells are copied there during VBLANK (14 cells a frame at most), so any number of
  kinds can appear in the round. `tools/pce_objects.py` builds the data from captures listed in
  `tools/object_specs.py`: the pieces each arcade slot drew (the simulator records which slot wrote each sprite
  entry), deduplicated into poses and animations per group, with cells stored once up to flips.
- **Cave block** (`src/props.asm`, `tools/pce_props.py`, `sim/scripts/block.txt`): the brown block over the cave
  entrance (arcade object slot 0, cells `$179`.., spawned by map marker `$48`) fills the 32 px gap in the ground.
  It is solid (`coll_at` asks the active prop first); a down thrust that reaches it crumbles it in three steps of
  6 frames and the gap opens. Standing swings don't break it (checked in the arcade). Props' cells are loaded on
  demand into `$4C00-$4FFF`, so the BG tile pool is now 960 slots (peak use 932).
- `tools/test_enemies.py` checks hits, deaths, spawns, the throwers' clubs and the frame budget
  (the `god.pce` test build keeps Rastan unhurt so the bot reaches later sections).
- `tools/player_frames.py` decodes Rastan's metasprite tables statically from the ROM (used for the weapons).

**HUD** (`src/hud.asm`, `tools/pce_hud.py`): the arcade draws it with sprites, and so does the port, using
the arcade's own cells. The bar is 6 cells x 8 levels (code 981 - level), 48 units for 12288 health, so a lizardman
hit costs 12. It drains a unit every 2 frames, as in the arcade, and the icon flashes while Rastan is invulnerable.
The lives digit shows spares, as in the arcade (3 lives shows "2").
The top line is the arcade's too: "1UP" and "HIGH SCORE" with the numbers below (score `$10C11C`, high score
`$10C140`: 3 BCD bytes in hundreds, low byte first; the high score starts at 273,100). The labels are static cells;
when a number changes, only the digit rows of those cells are rewritten from an 8x8 font taken from the arcade's digit
cells. Lizardmen are worth 300, blue throwers and bats 200 (measured from score changes in the bot runs). The HUD
takes SATB entries 0-11, so it draws in front of everything (12 sprites, most of them 32x16).

**Waterfall and run-time colors** (`src/dyncolor.asm`; `tools/pce_stage.py` with `build/waterfall.snp`):
the arcade cycles entries 14/15 of FG palettes 26-29 through three teal shades, 8 frames a step,
with 4 phase patterns, so the water flows. It also changes 5 sky colors once, while streaming the column before
segment 3 (the dusk sky). The converter finds both automatically from a bot run that reaches the waterfall. The
changing colors get palette slots of their own: 6 slots for the cycle, 35 for the sky. It emits VCE update lists,
and the engine applies them in vblank.

**Hazards** (arcade `$054D84`): collision code 7 and 8 tiles kill Rastan (the waterfall's lip and its pool), and
code 6 (water) drains 32/12288 health a frame. Health is now kept in bar units, 48 for 12288, so a lizardman hit is
12 units and water drains one unit every 8 frames. Deaths play the arcade's death animation (9 poses, 57 frames,
captured from the bot's death on the waterfall), then cost a life.

**Checkpoints and the debug menu** (`src/debug.asm`, bank 5 mapped in MPR2): the arcade's continue table
(`$5073A`) restarts round 1 at segments 0, 4, 8, 12, 16 and 19. The arcade's camera and Rastan's position at each
were measured by starting the arcade there. A restart fast-forwards the column stream from column 0 with the display
off (about 1.6 s for the last checkpoint), so the VRAM tile cache ends up exactly as if the stage had been played that
far, with no extra data. The menu draws into the tile map under the screen, with a font in the enemy sprite cells.
Closing it re-streams the 35 resident columns: every pattern a resident column uses is still in VRAM, so this rewrites
the tile map exactly. `tools/test_debug.py` checks that the screen comes back pixel for pixel, the warps, invincibility,
and that a death at the second waterfall restarts at checkpoint 2.

All VDC register sequences now run with interrupts held off. The core library's vblank handler
restores the VDC register select from its `vdc_reg` shadow, which direct `st0` selects don't update.
An interrupt in the middle of an upload sent the rest of it to the wrong register.

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
- [x] Run-time colors: waterfall cycle and the segment 3 sky change
- [x] Hazards: waterfall lip / deadly tiles (codes 7, 8), water drain (code 6), death animation
- [ ] Data compression (metatiles, LZ)
- [x] Rastan (approximate): walk, crouch, attacks, jumps, ropes, collision, camera
- [ ] Rastan (exact): translate the arcade player code (interpreter done and verified)
- [x] Down thrust and up thrust (DOWN+II / UP+II in a jump)
- [x] Stage 1 lizardmen (approximate): walk in, club attacks, knockback, death bursts; health and stage restart
- [x] HUD: lives, icon, health bar (drains like the arcade's), ROUND 1, score and high score
- [x] Enemy spawns on the arcade's lanes, with its timing; blue club throwers
- [x] The cave block (solid, broken by a down thrust)
- [x] Weapons (axe, morning star, fire sword) and round 1's weapon items, with their bats
- [ ] The rest of stage 1's enemies and the boss
- [x] Restart at the arcade's checkpoints after a death (stream fast-forward, no preload data)
- [x] Debug menu (SELECT): checkpoint warp, invincible, enemies on/off, health, lives, slow motion, weapon

## Licenses

Musashi (`sim/musashi/`) is © Karl Stenerud, MIT license (see `README-musashi.txt`).
*Rastan* is © Taito. This is a non-commercial fan project and distributes no Taito assets.
