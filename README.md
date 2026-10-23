# Rastan → PC Engine (HuCard)

A port of Taito's *Rastan* (1987 arcade) to the PC Engine / TurboGrafx-16 HuCard.
The first target is one BG layer at 256 px wide, on a Street Fighter II mapper card (2.5 MB), with the engine
written in PCEAS assembly.

**Start here:**
- `docs/REPORT.md` covers the state of the round 1 demo and how it was verified.
- `docs/HANDOFF.md` covers setup, architecture, pitfalls and next steps for whoever continues the port.

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
| `src/gargoyle.asm` | The gargoyle (replays the arcade's flight path) |
| `src/woman.asm` | The woman warrior |
| `src/jets.asm` | Fire jets over the castle's lava |
| `src/vines.asm` | Swinging vines |
| `src/traps.asm` | The castle's floor spears |
| `src/sound.asm` | Music and sound effects (PSG) |
| `src/boss.asm` | The round 1 boss and its fire; the round clear |
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
make HUC=/path/to/huc          # -> build/rastan.pce (the demo) and build/rastan_debug.pce
make HUC=/path/to/huc test     # the test scripts, headless (about 2 minutes)
make HUC=/path/to/huc audit    # a whole playthrough checked frame by frame (about 2 minutes)
python3 tools/trace_player.py build/rastan_debug.pce 600 60 300 04   # walk right, print Rastan's state
```

Two ROMs:
- **`rastan.pce`, the demo:** the arcade's title screen (PUSH RUN BUTTON), round 1, the arcade's
  round-clear screen and jingle after the boss, GAME OVER when the last life goes, and back to the
  title. No debug menu.
- **`rastan_debug.pce`:** straight into the game, with the debug menu. The tests run on this one (and
  on `god.pce`, `noenemy.pce`, `camtest.pce`, `bgcheck.pce`, test builds the Makefile also makes).

The build:
1. Extracts the ROM regions.
2. Runs the arcade program in the simulator to capture round 1's palette.
3. Converts round 1 (`tools/pce_stage.py`).
4. Assembles `src/main.asm`.

**Controls:**
- LEFT/RIGHT: walk
- DOWN: crouch
- I: jump (UP+I for the high jump; a direction for a forward jump)
- RUN: pause (sound off) and resume
- II: attack, standing or crouched; UP+II standing swings the sword over his head; in a jump,
  DOWN+II is the down thrust and UP+II the up thrust
- UP: grab a rope; UP and DOWN climb it, and I jumps off

The camera only scrolls forward. A death restarts at the last checkpoint reached, as in the arcade.

**Debug menu** (`rastan_debug.pce`): hold UP + SELECT together for about ¾ s to open it (a press, or a stray SELECT bit
from a pad or emulator mapping, is not enough); it freezes the game (RUN held + SELECT is still the
core's soft reset).
UP/DOWN pick a line, LEFT/RIGHT change a value, I applies, SELECT or II closes.

| Line | What it does |
|---|---|
| Warp to checkpoint 0-6 | Restart at one of the arcade's round 1 checkpoints (segments 0, 4, 8, 12, 16, 19), or 6: the boss room |
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
- **Colors:** quantized to 9-bit RGB. Tiles are greedily packed into 16 palettes of 15 colors, each
  set with one shared color 0 (its most common color). There are two sets: outdoors and the castle.
  The arcade loads the castle's stone colors (palette line `$2x`) at the gate and the lava hall's fire
  (line `$14x`) in the hall; converted with the round-start colors and one set of 16 palettes, the
  castle came out 22-63% exact (pink squares in the lava). Now the castle (and the hall's fire) is
  converted with its own colors (`build/hall.snp`) into a set of its own, which the game loads at the
  gate and on restarts there; every segment but the waterfall's colour-cycling ones matches the arcade
  exactly. Outside, the camera stops at the castle wall (the arcade's stops at the gate) and inside it
  keeps inside it, so neither set ever shows the other's rooms.
- **The lava hall's fire** (markers `$4C`, `$52-$55`): the arcade draws a row of 32x32 flame sprites
  along the lava (cells `$224-$233`, four phases, a phase every 4 frames, neighbouring blocks a phase
  apart). The VDC could not show that many sprites on a line, and the wall behind repeats every 32 px,
  so the converter bakes the flames into the tile map: the strip's cells show 32 fixed tiles (VRAM
  `$4C00`, the cave block's cells, never needed in the castle), and `src/fire.asm` rewrites them each
  phase. The sparks that drift off the fire in the arcade are not done.
- **The lava hall's camera:** the arcade holds its camera low there, the fire filling the bottom of the
  screen; the port sinks toward that height as far as Rastan's head (8 px below the top) allows.
- **A 2-D world** (`tools/world.py`): the arcade streams its map one 512 px segment at a time. A byte per
  segment (`$50F6C` + segment, read at `$0558E0` into `$10D0A8`) picks how: 0 streams block columns to the
  right, 1 streams block *rows* upwards (map column k of the segment becomes the k-th row above, map row r
  becomes block column r), 4 and 6 are transitions (the castle gate, the boss room door: the next room is
  loaded whole). So the castle climbs: segment `$11` is a shaft above the first castle room, `$12-$14` run
  right from its top (the lava hall, the jets' room), `$15` is a second shaft, and its door leads to the
  boss room (`$16`). The port lays these out as 512 px squares of one world (y negative above row 0) and
  streams it as lines of 64 tiles, columns and rows, in play order, into its 64x64 BAT. A column at x streams
  once `scroll_x + 264 >= x`, a row at y once `scroll_y - 32 <= y`. The camera stays in a box chosen by the
  next line to stream: it only scrolls forward in a horizontal stretch, moves freely in a shaft and in the
  boss room, and never shows the rows a shaft took over from the room below it. Passages a shaft climbs
  through (collision `$80`) seal behind the camera, as in the arcade (`$05A2B0`).
- **VRAM streaming:** round 1 has about 4,000 unique 8x8 patterns, but VRAM holds 960 for the stage.
  The converter models the BAT offline: a pattern stays resident while a BAT cell that can still be seen
  shows it (the camera rules above say which can), and each line record carries the patterns it needs
  uploaded, plus its 64 BAT words. Peak use is 929 of 960 slots.
- **Compression:** the stream was 513 KB: 9,149 pattern uploads of 32 bytes (only 3,645 distinct
  patterns, re-uploaded as they come back into view) and 128 bytes of BAT words per line. Now
  (206 KB, 2.5x smaller):
  - every pattern is stored once (`stage_pats.bin`, numbered by first use) and an upload is 3 bytes:
    the VRAM slot and the pattern number;
  - a line's 64 BAT words are 16 *quads*, 4-tile slices of the arcade's 32 px blocks; each distinct quad
    (2,944) is stored once (`stage_quads.bin`, most used first), and a line is a short code stream: one
    byte for the 224 most used quads, two for the rest, one to repeat the last quad (sky, walls).
  The converter decodes every line back and checks it before writing. `stream_line` reads the
  dictionaries through MPR5 and copies with `tia` (patterns 32 bytes, quads 8), which is faster than
  the old byte loop. Patterns themselves are not compressed: a cheap codec would save about 15% of
  them for a decoder in the frame.

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
- **Items and bats** (`src/items.asm`; `sim/scripts/item.txt`, `item_fire.txt`, `item_star.txt`): five items hang
  in round 1: axes at x 1004 (in the cave) and 3854, the fire sword at 2893, morning stars at 6829 and in the
  castle's first shaft at (8384, -178) (found by the shaft capture of `sim/scripts/hall.txt`, frame 3432). Each
  appears when Rastan is 164 px left of it (and on the same side of world y 0), with a bat 20 px below. Touching an item, or hitting it with the weapon, takes it.
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
- **Gargoyle** (`src/gargoyle.asm`; `sim/scripts/gargoyle.txt`): at x 4608 and 6841, 176 px ahead of Rastan. In the
  arcade it flies the same path every time whatever Rastan does (glide in, hover, dive past him, turn, swoop back;
  about 410 frames), and swings and thrusts did nothing to it. The converter records that path from the capture as
  runs of per-frame steps (`PATHS` in `tools/object_specs.py`), and the port replays it with two objects, body and
  wings (arcade slots 9 and 10). Touching the body hurts.
- **Woman warrior** (`src/woman.asm`; `sim/scripts/woman.txt`): at x 4523, appearing when Rastan reaches 4355. In the
  arcade she doesn't stop to fight: she runs left at 1 px/frame hopping down the 32 px steps, turns about 50 px past
  Rastan, runs back right at 1.5 px/frame hopping up, and leaves. Touching her hurts; one hit kills her (300).
- **Swinging vines** (`src/vines.asm`, marker `$4F`; measured on the bot's swing over the chasm at x 2750,
  `build/vine.snp`): a vine swings through 45 poses, a step every 2 frames, 180 frames a swing. Rastan caught
  in the air near its end hangs there (about 2 px per step right of the anchor, 93-107 px below it); jump lets
  go, only on the side he faces (the arcade ignored a jump on the far side). The lava hall's three vines
  (`$4F`, `$50`, `$51`) are not measured: here they swing together, and the grab distance (40 x 24 px) is a guess.
  Its markers `$4C`, `$52-$55` just above the lava are the fire (see How stage 1 is converted).
- **Doors** (collision `$7E`): the door at the top of the second shaft drops Rastan into the boss room at
  (11728, 98), as in the arcade. The castle gate (also `$7E`) puts him inside the castle where the arcade does.
- **Ceilings**: a jump that meets a ceiling stops rising but goes on (the arcade glides along under it).
- **Castle soldiers** (`sim/scripts/castle.txt`): from x 8200 sword and mace soldiers come in turn on the lanes.
  The arcade's two share a body and differ by weapon; both walk in, stand about 60 px away and swing (3-frame steps),
  then walk on. They use the lizardmen's loop (walk in, two swings, back off, come again) with their own hit pose
  and reach; a swing that reaches costs 12 units. The arcade gave 900 for a sword and a mace soldier dying together;
  the port splits it 300 / 600.
- **Fire jets** (`src/jets.asm`): over the lava pits at world x 9870, 9966 and 10062 (the arcade's census:
  10382-10574 in segment `$14`, now the jets' room at square ($13, -1)). Each erupts when Rastan is 172 px
  left of it (the flame rises for 17 frames, dies down for 18, then a column flickers for 57) and again about 220
  frames later while he is near; touching the flame hurts. Not done: the castle's ceiling spikes
  (x 8328, 8488), whose bot captures show too little to model.
- **The boss** (`src/boss.asm`; `sim/scripts/boss.txt`): drops in when Rastan enters the last room and lands
  (anchor y 446). It walks at him, leaps when he is far, and alternates fire (five fragments form at the top of the
  screen in front of it, then rain down at him in a fan) and a staff swing reaching about 80 px. Ten sword hits kill it
  (it is untouchable for 20 frames after each), for 5000. The arcade draws it with up to 18 sprites: the converter
  splits every pose by piece order (13 + the rest) and two objects draw it. Then the round is clear: with only round 1
  ported, it starts again with the score and lives kept. The debug menu's warp has a 7th target, the boss room.
- The later object code (gargoyle, woman, jets, boss) lives in bank 5 with the debug menu, which is always mapped.
- **No torn frames:** the SATB is DMA'd at the start of VBLANK, before the object cell uploads, so `enemies_draw`
  plans which slots will get new cells at the next VBLANK (same order and budget) and draws each slot with the pose
  its buffer will hold. A frame never shows an old layout over new cells.
- The converter drops sprite pieces the arcade parks off-screen (y 272-479), which some objects keep in their lists.
- **Object slots:** 0-3 walkers (11 cells each), 4 item and 5 its bat (4 cells), 6-8 specials such as boulders and
  the gargoyle's body and wings (13 cells), 9-16 projectiles (2 cells): 107 cells at `$5C00-$76BF`.
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
were measured by starting the arcade there (checkpoint 5 is in the castle's lava hall row, y -57). A restart
fast-forwards the line stream from line 0 with the display off (every line before the checkpoint's segment, then those
the camera has reached), so the VRAM tile cache ends up exactly as if the stage had been played that far, with no extra
data. The menu draws into the tile map under the screen, with a font in the enemy sprite cells; the tile map under its
box is saved on opening and put back on closing. `tools/test_debug.py` checks that the screen comes back pixel for pixel, the warps, invincibility,
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

The ROM is built for the Street Fighter II mapper (`pceas --sf2`), as a 2.5 MB image, the real card's
size (`tools/pad_sf2.py`; emulators recognise the mapper by size, MAME only by exactly that size).
Banks `$00-$3F` are fixed; banks `$40-$7F` show one of four 512 KB pages, chosen by a write to
physical `$001FF0-$001FF3` (`stz $FFF0 + overlay(label)`, with bank 0 in MPR7).

- **Fixed half:** everything the game needs whatever the round: the code (banks 0, 4, 5), palettes,
  Rastan, weapons, HUD, props, the objects (`$13-$25`), music and effects (`$26-$2B`), voices
  (`$2C-$2E`), the screens. `$01` and `$30-$3F` are free (136 KB).
- **Pages:** a round's own data: its stage stream, the pattern and quad dictionaries, its collision
  map. Round 1 is in page 1 (file banks `$80-$9B`, 224 KB), not page 0, so that the page switch is
  exercised (and tested) from the first round; `sf2_round` maps it at boot and at every stage start. Page 0 and pages 2-3 are free: at round 1's size, the other five rounds fit two to a
  page.

`tools/tgemu/` is HuC's `tgemu` (GPLv2) with the mapper added, used by `tools/tgrun`. Like the card,
it answers the page writes only at offsets `$1FF0-$1FF3` of bank `$00`.

Simulator script commands: `in <frame> <p1> <sys>` (active-low pad bits; up 01, down 02,
left 04, right 08, b1 10, b2 20), `poke <from> <to> <addr> <b|w|l> <val>`,
`patch <addr> <byte>`, `end <frame>`, `trace`.

The headless runner is built with `tools/tgrun/build.sh`, after running `make` in a HuC checkout.

## Sound (`sim/snd.c`, `tools/pce_sound.py`, `src/sound.asm`)

The arcade's sound board is a Z80 at 4 MHz with a YM2151 (FM) and an MSM5205 (ADPCM voice).
`sim/snd` is a Z80 interpreter with the YM2151's registers and timers: it runs the real sound
driver, so there is no need to understand the music data itself. The main CPU sends a command
as two nibbles through a Taito PC060HA (`sim/sim`'s `sndlog` records them); `$EF` sets the driver
up, then `$1A` is round 1's music, `$1B` the castle's, `$1C` the boss room's, and the effects
include `$09` sword swing, `$10` an enemy dying, `$15` a weapon item, `$17` the cave block.
The driver keeps music on FM channels 0-5 and effects on 6-7.

`tools/ym2151.py` reads the log back as, per channel: is a note sounding, at what pitch (KC/KF)
and how loud (the loudest carrier's TL, which is how the driver shapes a voice). `tools/pce_sound.py`
samples that at the driver's own sequencer rate - its timer A, about 54.6 Hz, not 60 - so a loop
repeats tick for tick, and finds each tune's loop by looking for the part that repeats exactly.
Each tune and effect becomes a stream of per-channel PSG periods and volumes; `src/sound.asm`
plays it on the PSG's 6 channels, pacing itself with an 8.8 fixed-point tick counter, with an
effect borrowing channels 4 and 5 and handing them back when it ends.

What is lost: each FM voice becomes one PSG waveform (one shared 32-step wave), and notes below the
PSG's range move up an octave.

**Voices** (`tools/pce_voice.py`, `src/voice.asm`). Rastan's jump grunt and death cry (commands `$0A`
and `$0D`) are MSM5205 ADPCM samples, not FM. The ADPCM ROM holds the samples back to back, so each
runs from its start page to the next one's; `sim/snd` shows the driver starting and stopping them,
and the two long samples ($28→$63: 30208 nibbles in 253 frames, $63→$B1: 39936 in 335) put the
MSM5205 at about 7158 Hz. `pce_voice.py` decodes them (high nibble first), cuts each where the
driver stops it, resamples to the H6280 timer's 6991 Hz (7.16 MHz / 1024, `TIMER_DR` 0) and
quantises to the PSG's 5-bit levels: 2330 bytes for the jump, 16080 for the death cry, banks
$7A-$7C. The timer interrupt writes one level a tick to PSG channel 5 in direct D/A mode, which the
music gets back the frame after the voice ends. The PSG's channel-select port cannot be read back,
so every other PSG write runs with interrupts held off and keeps a shadow (`psg_ar`) the interrupt
restores. The interrupt costs about 90 cycles a tick (about 9% of the CPU while a voice plays);
the frame budget checks (`test_player`, `test_castle`) still pass on routes full of jumps.

`tools/tgemu` needed two fixes for this: its H6280 timer fired once and stopped (an old workaround
for one game; the real counter reloads itself and keeps running), and its PSG ignored direct D/A
mode, so writes went into the channel's waveform instead. It now keeps the levels written each frame
and spreads them evenly over that frame's samples.

`tools/test_sound.py` checks it without listening: `tools/tgrun` can write a WAV of the emulated
PSG and a log of every PSG register write, so the test compares what the ROM writes against the
stream, and checks the notes in the audio's spectrum are the ones the stream asks for. For the
voices it checks a jump writes the jump sample's levels to channel 5, every one in order, that the
music gets the channel back, and that the voice shows in the audio.

## Screens, sprites and the playthrough audit

- **Still screens** (`tools/pce_still.py`, `src/still.asm`): one arcade screen, rendered from a
  simulator snapshot, cropped to 256x224 and converted whole into tiles, a 32x28 map and palettes.
  The title (frame 160 after power-on, with PUSH RUN BUTTON written in the arcade's own font on a
  palette of its own, so it can blink), GAME OVER (the lettering of the attract demo's) and the
  round-clear screen ("YOU ARE A BRAVE FIGHTER TO HAVE CLEARED SUCH A DIFFICULT STAGE.", from the boss
  script run on: `sim/scripts/ending.txt`). After the boss the arcade stops the music (`$29`) and plays
  `$27`, a tune that plays once (stream end `$FE`); the port shows the screen with it for 7 s (RUN skips
  it after 2), as long as the arcade's before ROUND 2 READY, then the title.
- **Clean cuts:** restarts, warps, the gate and the boss door turn the display off at a VBLANK before
  rewriting the tile map, with colour 0 black meanwhile (the VCE shows BG colour 0 with the display off).
- **Sprites:** the SATB is packed (the HUD's 12 entries, then Rastan's, the props', the objects'), so
  three castle soldiers no longer run out of entries. The VDC fetches only 16 sprite cells (16 px wide)
  a line; where walkers crowd onto one line, `enemies_draw` turns the order they are drawn in every
  frame, so the one that loses its cells there takes turns (flicker) instead of always the same.
- **`make audit`** (`tools/audit.py`): every checkpoint played through in god mode (the castle on the
  test routes, elsewhere running right holding UP, jumping and swinging), with contact sheets
  (`build/audit/cpN.png`) and per-frame checks: object poses that their kind doesn't have, slowdown,
  objects left undrawn for want of SATB entries, and frames where the 16-cells-a-line limit drops a
  sprite (reported, not failed). Then the `bgcheck` build (god mode, the tile map alone, colours as
  converted) is compared with the converter's preview at every tenth frame. It found the bugs fixed in
  this round: lizardmen reading their walk animation from whatever bank was mapped (invisible, or stray
  blocks by the HUD), the castle gate dropping Rastan 256 px too high without the castle tune, a torn
  frame at the boss door, castle soldiers losing pieces.
- **`tools/tgemu`** (the test emulator) now emulates the 16-cells-a-line limit (`TGRUN_NOSPRLIMIT=1` turns
  it off) and the PSG's direct D/A, and its H6280 timer keeps running after it fires; `tgrun` can dump the
  SATB every frame (`TGRUN_SATB`).

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
- [x] Stage compression: pattern and quad dictionaries (513 KB → 206 KB)
- [x] Street Fighter II mapper: fixed half for the game, a page per round's data
- [x] Rastan (approximate): walk, crouch, attacks, jumps, ropes, collision, camera
- [ ] Rastan (exact): translate the arcade player code (interpreter done and verified)
- [x] Down thrust and up thrust (DOWN+II / UP+II in a jump)
- [x] Stage 1 lizardmen (approximate): walk in, club attacks, knockback, death bursts; health and stage restart
- [x] HUD: lives, icon, health bar (drains like the arcade's), ROUND 1, score and high score
- [x] Enemy spawns on the arcade's lanes, with its timing; blue club throwers
- [x] The cave block (solid, broken by a down thrust)
- [x] Weapons (axe, morning star, fire sword) and round 1's weapon items, with their bats
- [x] The rest of stage 1's enemies (approximate): chimeras, boulders, gargoyles, the woman warrior, castle soldiers, fire jets
- [x] The round 1 boss; round clear
- [x] The castle as the arcade lays it out: two shafts that scroll up, the lava hall, the boss room door
- [x] Swinging vines (the chasm at x 2750, the lava hall)
- [x] The castle's floor spears (markers `$46`)
- [x] Music and sound effects on the PSG (`$1A`/`$1B`/`$1C` and the FM effects)
- [x] The MSM5205 voice samples (jump, death), through the PSG's direct D/A
- [x] Standing UP+II: the sword over his head (arcade bodies 12-14, `sim/scripts/upatk.txt`); its hit
      box is the up thrust's, which has not been measured against the arcade for this attack
- [x] The lava hall's fire (markers `$4C`, `$52-$55`), baked into the tile map and animated
- [ ] The castle's swarm: nine small bats (cells `$268-$26A`, arcade slots 20-28) that flutter about shaft 1
      and the lava hall from the moment Rastan climbs into the shaft (`sim/scripts/hall.txt`, frame 2892 on;
      the "sparks" of earlier notes)
- [x] The castle in its own colours (a second set of 16 BG palettes)
- [x] Title screen, GAME OVER, the round-clear screen and jingle (`tools/pce_still.py`, `src/still.asm`)
- [x] RUN pauses
- [ ] The castle's ceiling spikes (x 8328, 8488)
- [ ] Castle soldiers' colours: the arcade switches its sprite colour bank in the castle (gold soldiers
      in the first rooms, green ones past the lava hall); the port shows them green throughout

(Checked and not needed: Rastan shows no score popups when anything dies, and the "small castle
flyers" seen in an early census are the blue throwers' clubs, which the port already has.)
- [x] Restart at the arcade's checkpoints after a death (stream fast-forward, no preload data)
- [x] Debug menu (UP + SELECT, held): checkpoint warp, invincible, enemies on/off, health, lives, slow motion, weapon

## Licenses

Musashi (`sim/musashi/`) is © Karl Stenerud, MIT license (see `README-musashi.txt`).
*Rastan* is © Taito. This is a non-commercial fan project and distributes no Taito assets.
