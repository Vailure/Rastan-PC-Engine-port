# Handoff: Rastan → PC Engine, round 1

This document is for whoever picks the port up next, whether a person or an agent.

- `docs/REPORT.md` describes the state of the demo and how it was verified.
- `README.md` holds the per-feature notes and the measured arcade values.
- This file covers how to work on the port: setup, architecture, conventions, traps and what to do next.

Branch: `section1-parity` on `github.com/Vailure/Rastan-PC-Engine-port`. Last update: 2026-10-23.

---

## 1. Ground rules

- **No ROM data in git.**
  - Everything decoded from the arcade ROMs is git-ignored (see `.gitignore`), and must stay out of the repository: `*.bin`, `*.snp`, `*.pce`, `build/`, `sim/*.asm`, renders and disassembly.
  - Before committing, check `git status`. Any new output format a tool writes must be covered by `.gitignore`.
  - Only source code, scripts, simulator input scripts (`sim/scripts/*.txt`) and docs are committed.
- **Leave other people's branches alone.** PR #5 (`codex/exact-player-lockstep`) belongs to the repository owner. Do not push to it or rebase it.
- **GitHub access.** Use REST (`gh api ...`), because GraphQL calls are blocked in the environment this was built in.
- **Commit messages.** Write them in plain language, saying what the change does for the game. Use the attribution trailer your environment asks for.
- **Measure the arcade, don't guess.**
  - Every number in the engine should come from a simulator capture (`sim/scripts/*.txt` → `.snp`) or from the 68000 program.
  - When a value is a guess, say so in a comment and in the README, as is done for the lava hall's vines.

---

## 2. Setting up from nothing

1. **Install the requirements:**
   - Python 3 with `numpy` and `Pillow`;
   - `gcc` and `zlib`;
   - `make`.
2. **Build HuC.**

   ```sh
   git clone https://github.com/pce-devel/huc && make -C huc
   ```

   This gives `pceas`, plus the include files the engine uses (`include/hucc`).
3. **Add the arcade set.** Unzip MAME's `rastan` (World, rev 1) into `roms/rastan/`, or point `RASTAN_ROMS` at it.
4. **Build:**

   ```sh
   make HUC=/path/to/huc
   ```

   The first build:
   - extracts the ROMs;
   - builds the simulator (`sim/sim`, `sim/snd`);
   - runs the capture scripts;
   - converts everything;
   - assembles the ROMs.

   It takes several minutes, mostly in simulator runs.
5. **Run the checks:**

   ```sh
   make HUC=/path/to/huc test    # about 3 min
   make HUC=/path/to/huc audit   # about 2 min once the ROMs are built
   ```

   `tools/tgrun/tgrun` is built automatically against the patched core in `tools/tgemu/`.

**Known oddity:** once, `pce_stage.py` was killed (exit 137) under `make` but ran fine directly. If that happens, run the converter command from the Makefile by hand and re-run `make`.

### Build outputs

| ROM | Options (`build/opt*/options.inc`) | Use |
|---|---|---|
| `rastan.pce` | `TITLE=1 DEBUG_MENU=0` | **The demo.** Title → round 1 → round-clear → title; GAME OVER → title. The debug menu is a screen of its own from the title (UP+SELECT held), never in play. |
| `rastan_debug.pce` | `TITLE=1 DEBUG_MENU=1` | The same; SELECT alone on the title opens the menu. |
| `testdbg.pce` | `TITLE=0 DEBUG_MENU=1` | Test build: straight into play, with the old in-play debug menu (hold UP+SELECT) for checkpoint warps. Most tests run on it. Not for playing. |
| `god.pce` | `GOD_MODE=1` | Rastan takes no damage; for bots that must reach the end of a section. |
| `noenemy.pce` | `NO_ENEMIES=1` | Rastan alone (player and effects tests). |
| `camtest.pce` | `CAMERA_TEST=1` | The pad moves the camera; BG only. Used by `test_scroll.py`. |
| `bgcheck.pce` | `GOD_MODE=1 BG_CHECK=1` | God mode with the tile map alone: no sprites, no colour cycling, the fire frozen. Compared with `preview.png` by the audit. |

All builds are 2.5 MB images for the Street Fighter II mapper card (§4.2). `tools/pad_sf2.py` pads them to that size after `pceas`.

---

## 3. How data flows

```
roms/rastan/*  ──extract_roms.py──▶ sim/maincpu.bin, pc080sn.bin, pc090oj.bin, audiocpu.bin, adpcm.bin
                                          │
     sim/scripts/*.txt (pad input, pokes) ┤ sim/sim  (Musashi 68000 running the real arcade program)
                                          ▼
                                build/*.snp  (snapshots: RAM, VRAM, palette, sprite list, sound log per frame)
                                          │
   ┌──────────────┬──────────────┬────────┴──────┬──────────────┬──────────────┬──────────────┐
pce_stage.py  pce_player.py  pce_objects.py  pce_hud.py   pce_sound.py   pce_voice.py   pce_still.py
 (world, BG,   (Rastan poses,  (enemy/item     (HUD cells)  (sim/snd: Z80   (MSM5205       (title,
 palettes,     anims, jumps,   poses, paths,                + YM2151 →     ADPCM → PSG    GAME OVER,
 VRAM stream   collision)      object_specs.py)             PSG streams)   D/A levels)    round clear)
 schedule)
   │              │              │              │              │              │              │
   └──────────────┴──────────────┴──────┬───────┴──────────────┴──────────────┴──────────────┘
                                        ▼
                     build/<area>/*.bin + *.inc  ──incbin/include──▶  src/main.asm  ──pceas──▶  build/*.pce
                                                                                                   │
                                                                         tools/tgrun (patched tgemu)
                                                                         tests, audit, trace_player
```

### Snapshots

`tools/snap.py` reads them, and `tools/contact.py` renders frames as MAME would draw them.

The captures that matter most:

| Snapshot | Script | Used for |
|---|---|---|
| `play1.snp` | `play1.txt` | Round start palette |
| `waterfall.snp`, `sky04.snp`, `sky0c.snp` | (bot runs; `make_bot.py`'s 3rd argument picks the restart segment) | Colour cycle, the sky's 8 steps |
| `hall.snp` | `hall.txt` | The castle's colours at frame 4400 |
| `actions.snp`, `upatk.snp` | `actions.txt`, `upatk.txt` | Rastan's poses |
| `ending.snp` | `ending.txt` | Round-clear screen |
| `title.snp` | `attract_stills.txt` | Title and GAME OVER |
| per-enemy captures | `lizard.txt`, `blue.txt`, `chimera.txt`, `gargoyle.txt`, `woman.txt`, `castle.txt`, `boss.txt` | Enemy poses, paths and timing |
| (run by hand) | `weights.txt` | Shaft 2's spiked weights: the only bot that climbs shaft 2 (the jets' room's pool jumps, three ropes, the corridor) |

### Capture scripts

Script syntax:

- `in <frame> <p1> <sys>`: active-low pad bits (up 01, down 02, left 04, right 08, b1 10, b2 20);
- `poke`, `patch`, `end`, `trace`, `callsnap`, `watch <addr> <len>` (every write to that range, with the frame and the PC, on stderr: the quickest way to the code behind a value).

Clearing a crowd: `poke <from> <to> <slot + 8> b 0` for each object slot (`$10C2C0` + 64 × slot) switches it off every frame, so that one object can be measured alone (`weights.txt` clears slots 3-29).

---

## 4. Engine architecture (`src/`)

The engine is about 11,100 lines of PCEAS assembly on top of HuC's core library (`--newproc`, using the core's vblank handler, `wait_vsync`, `joytrg` and `timer_hook`).

### 4.1 Memory map (MPRs)

| MPR | Address | Holds |
|---|---|---|
| 0 | `$0000` | I/O |
| 1 | `$2000` | RAM (zero page, stack, `.bss`) |
| 2 | `$4000` | `DEBUG_BANK` ($05): checkpoints, debug menu, later object code (gargoyle, woman, jets, boss), screens. Always mapped. |
| 3 | `$6000` | **Data window.** Mapped freely by everyone. The timer IRQ (`voice_irq`) saves and restores it. |
| 4 | `$8000` | Second data window. Stage records span `$6000-$9FFF` using MPR3 and MPR4. |
| 5 | `$A000` | Collision map (`COLL_BANK`), mapped by `player_update`. `stream_line` borrows MPR5 for the pattern and quad dictionaries, and puts the collision map back. |
| 6 | `$C000` | `GAME_BANK` ($04): most game code. |
| 7 | `$E000` | Core library, bank 0. |

### 4.2 ROM bank map (Street Fighter II mapper)

The build uses `pceas --sf2`.
- **CPU banks `$00-$3F`** are fixed.
- **CPU banks `$40-$7F`** show one of four 512 KB *pages*.
- **The page is chosen** by a write to physical `$001FF0+n`, which is bank `$00` at offset `$1FF0`. The engine does `stz $FFF0 + overlay(label)` with bank 0 in MPR7.
- **In PCEAS file-bank numbers,** page *n* is file banks `$40+$40n…`: page 0 is `$40-$7F`, page 1 is `$80-$BF`, and so on.
  - `^label` gives the CPU bank (`$40-$7F`).
  - `overlay(label)` gives the page.

**Fixed half.** Code and data the game needs in every round:

| Banks | Contents |
|---|---|
| $00 | Core + main code |
| $02 | GAME OVER still |
| $03 | Fire tiles |
| $04 | Game code |
| $05 | Debug/late object code |
| $06–$07 | Title still |
| $08 | Palettes, debug font, trap cells |
| $09–$0E | Rastan (`player.bin`) |
| $0F | Weapon piece lists per pose |
| $10 | Weapon cells |
| $11 | HUD cells |
| $12 | Prop cells |
| $13–$25 | Objects: cells `$13-$1B`, then one bank per pose group. Placed by `pce_objects.py … 0x13`. |
| $26–$2B | Music and effects |
| $2C–$2E | Voices |
| $2F | Round-clear still |
| **$01, $30–$3F** | **Free (136 KB)** |

**Page 1 (file banks `$80-$9B`).** Round 1's own data, 224 KB:

| Banks | Contents |
|---|---|
| `$80`+ | `stage.bin`: line table and records, 9 banks |
| next | `stage_quads.bin`, 3 banks |
| next | `stage_pats.bin`, 15 banks |
| last | `collision.bin`, 1 bank |

Pages 0, 2 and 3 are empty.

**Rules:**
- Anything read from an interrupt, or by code that can run in any round, must be in the fixed half. The voice IRQ and the music are the reason sound and voices moved there.
- A round's data must sit in one page, and `sf2_round` must select it before the stage streams. It runs at boot and from `stream_reset`.
- Round 1 is deliberately in page 1, not page 0, so a missing or wrong page write breaks the tests at once.

**Code space is the tight resource now:** bank $00 has 0.6 KB left, bank $04 (game code) 1.4 KB and bank $05 (debug and late objects) 1 KB. The next sizeable module needs a third code bank. Map it in MPR2 alongside bank $05 (swap around calls), or move a module out to a bank of its own.

Check bank usage with `make … build/rastan.pce 2>&1 | grep ^BANK`. That build has the listing on, and `pceas` prints used and free space per bank.

### 4.3 VRAM map (words)

| Address | Use |
|---|---|
| `$0000` | BAT, 64×64 |
| `$1000–$4A7F` | Streamed BG tiles: 936 slots (`NUM_SLOTS` in `pce_stage.py`), peak use 930. The converter fails if a line would need more. |
| `$4A80–$4AFF` | The swarm's bat cells (`$268`, `$269`) |
| `$4B00–$4BFF` | The floor spears' cells |
| `$4C00–$4FFF` | Props: outside, the cave block. In the castle, the fire's 32 tiles (`$4C00-$4DFF`) and the hanging column's 6 cells (`$4E00-$4F7F`). |
| `$5000` / `$5600` | Rastan's two pattern buffers (double-buffered) |
| `$5C00–$76BF` | Object slot buffers |
| `$76C0` | The killed bat's cell (`$276`) |
| `$7700` | HUD (cells 0-12, 16-25); its cells 26-30 (`$7D80-$7EBF`) hold shaft 2's weights (`src/weights.asm`) |
| `$7F00` | SATB |

The still screens (title, GAME OVER, round clear) overwrite the BAT and tile area. Going back into play re-streams everything.

### 4.4 The frame

`core_main` in `src/main.asm` runs once per frame, right after VBLANK.

**VBLANK work comes first, in this order:**

1. `set_scroll_regs`
2. `dyn_update`: outdoors only, `bg_set` = 0
3. `fire_update`
4. `objects_upload`: changed object poses, at most 14 cells a frame
5. `sound_update`
6. `debug_check`
7. RUN → `game_pause`
8. slow motion

**Then the logic:**

1. `player_update` (and `door_enter` if Rastan is in a door)
2. `props_update`
3. `enemies_update`
4. `camera_update`, which falls through into `camera_clamp`
5. `stream_ahead`

**Then the SATB is built for the next frame:**

1. `player_draw`
2. `props_draw`
3. `enemies_draw`
4. `hud_update`
5. `checkpoint_track`

**Rules that keep frames clean:**

- The SATB is DMA'd at the start of VBLANK, before object cell uploads. So `enemies_draw` plans which slots will get new cells next VBLANK and draws each slot with the pose its buffer will hold.
- Every VDC register sequence runs with interrupts off (`sei`). The core's vblank handler restores the register select from `vdc_reg`, which a direct `st0` does not update.
- Every PSG write other than the voice's runs under `sei` and updates the `psg_ar` shadow.

### 4.5 Sprites (SATB packing)

Entries 0–11 are the HUD (`hud_satb`). The other sprites follow in this order:

1. Rastan: body, legs and up to 4 weapon sprites.
2. Props and traps.
3. Objects.

`satb_n` is the next free entry, and `en_cap` = 64 − `satb_n`. `en_satb_prev` remembers last frame's count so stale entries get cleared.

**Order of the object slots.** The walkers (slots 0–3) and the swarm (as a fifth) are drawn last, in an order that rotates every frame (`en_rot`, 0–4). The traps come after them.
- If the 64 entries or the VDC's 16-cells-a-line limit run out, a walker (or the swarm) loses pieces for one frame (it flickers), not the same one forever.
- `tools/swarm_budget.py god.pce <cp>` measures it for the bats: before the swarm joined the rotation, at checkpoint 4 (four soldiers on Rastan in god mode) they had a SATB entry 23% of the time; now 94% (86% whole on every line), at the cost of about 1,100 soldier pieces over the run.
- The audit reports these frames but does not fail on them, since they are a hardware limit.

**Object slots:**

| Slots | Use | Cells each |
|---|---|---|
| 0–3 | Walkers | 11 |
| 4 | Item | 4 |
| 5 | The item's bat | 4 |
| 6–8 | Specials (boulders, gargoyle body and wings, boss parts, jets, vines) | 13 |
| 9–16 | Projectiles | 2 |

Each slot has its own VRAM buffer. Pose changes copy cells there during VBLANK, so any number of enemy kinds fit in a round.

### 4.6 Palettes

There are two BG sets of 16 palettes:
- **outdoors** (`palette.bin`);
- **the castle** (`palette_castle.bin`), converted from `hall.snp` frame 4400. It includes the castle's stone colours (line `$2x`) and the fire (line `$14x`, `HALL_SEG` $12 only).

**The runtime routines:**

| Routine | Does |
|---|---|
| `bg_palettes` (A = 0/1) | Loads a set |
| `bg_palettes_here` | Picks by `p_x ≥ CASTLE_X` (8192) |
| `bg_black0` / `bg_color0` | Colour 0 black during a cut, then back to the set's colour 0 |

**When the sets change:**
- `door_enter` switches to the castle set at the gate.
- Checkpoint restarts use `bg_palettes_here`.

**The camera never shows both areas at once.** Outdoors, `scroll_x ≤ 7936`. Inside, `scroll_x ≥ 8192`. The clamp is in `camera_clamp`.

### 4.7 World streaming and camera

`tools/world.py` lays the arcade's segments out as 512 px squares, and `pce_stage.py` emits one record per BAT line (row or column), in play order.

**A record holds:**
- a header (row or column, door flag, trigger coordinate, camera region);
- its uploads, 3 bytes each: the VRAM slot and a pattern number in `stage_pats.bin`;
- its 64 BAT words as codes over 16 *quads* (4-word slices) in `stage_quads.bin`:
  - `$00-$DF`: quad number;
  - `$E0-$EF`: the last quad again, 1–16 times;
  - `$F0-$FF` plus a byte: quad numbers 0–4095.

The format is documented at the top of `tools/pce_stage.py` and above `stream_line`. The converter decodes every line back and asserts it matches before writing, and the scroll tests check the result on screen pixel for pixel.

**How streaming runs:**
- `stream_ahead` streams the next line once the camera reaches its trigger.
- The camera box is chosen by the next line's region:
  - forward-only on horizontal stretches;
  - free in shafts and the boss room;
  - in the lava hall, resting at `CAM_REST_Y` (−441) while `p_x` is in 8704–9215 (square `$12`, the fire's room), but never above `p_y − 36`. (It once covered square `$13` too, the room past the hall's wall: there the camera stayed at −441 while Rastan stood on its floor at −33, off the screen, after every restart at checkpoint 5.)

**Restarts** (`checkpoint_start`) fast-forward the stream from line 0 with the display off. This leaves VRAM exactly as if played that far.

### 4.8 Screens (`src/still.asm`)

- `still_show` copies a still's tiles, map and palettes with the display off.
- `still_wait` waits N frames or for RUN.
- `title_blink` toggles the PUSH RUN BUTTON palette.
- `still_on` is set while a still is up. The audit uses it so it does not count those frames as slowdown.

**The demo's flow:**

```
title_screen → stage_start → … → boss dies → round_end
  ($29 stops the music, $27 jingle, 420 frames, RUN skips after 2 s) → title

last life lost → game_over → title → new game
  (score reset; high score kept)
```

**Cuts:**
- `screen_cut`: display off at a VBLANK, colour 0 black.
- `screen_show`: display on at a VBLANK, colour 0 restored.

### 4.9 Sound and voices

**Music and effects** (`src/sound.asm`):
- Streams of per-channel PSG period and volume, converted from the real Z80 driver's YM2151 output (`sim/snd`).
- Played at the driver's 54.6 Hz tick, with an 8.8 fixed-point accumulator.
- Effects borrow channels 4 and 5.
- `$FE` ends a play-once tune, such as the round-clear jingle.

**Voices** (`src/voice.asm`):
- Two MSM5205 samples, the jump grunt and the death cry.
- Resampled to the timer's 6991 Hz and written by `voice_irq` to channel 5 in direct D/A mode (`PSG_CTRL` = `$DF`).
- While a voice plays, music skips channel 5. It gets the channel back the frame after the voice ends.
- Cost: about 90 cycles a tick, roughly 9% of the CPU while a voice plays.

### 4.10 The lava hall's fire (`src/fire.asm`)

The arcade draws a row of 32×32 flame sprites. That is too many for the VDC on one line, so the port bakes the flames into the BAT:

- The strip runs from x 8768 to 9168, with its top at y −320.
- The strip's cells point at 32 fixed tiles (`FIRE_TILE0`).
- `fire_update` rewrites those 32 tiles from `fire.bin` every 4 frames:
  - 4 phases;
  - odd blocks run one phase ahead.
- The tiles are written only while `bg_set` = 1. `bg_palettes` clears `fire_on`, so the props area is re-uploaded properly outdoors.

### 4.11 Checkpoints and the debug menu (`src/debug.asm`)

- **Checkpoints:** the arcade's continue table, at segments 0, 4, 8, 12, 16 and 19, plus a seventh target, the boss room.
- **Opening the menu:** UP+SELECT held for `DBG_HOLD` (45) frames. A press is not enough, because stray SELECT bits from emulator pad mappings used to open it at random.
- **In the demo build** (`DEBUG_MENU=0`), the menu is locked.
  - `dbg_on` starts at 0, and `debug_check` returns at once.
  - Holding UP+SELECT for `DBG_HOLD` frames on the title screen (`title_screen`, `src/still.asm`) sets `dbg_on` and `dbg_now`. The game then starts, and `debug_check` opens the menu on its first frame.
  - From then on, the menu works as in the debug build until power-off.
  - The code is in every build; `DEBUG_MENU` only sets `dbg_on` at boot.
- **What the menu does:** it draws into the BAT under the screen, using a font in enemy sprite cells, and restores the BAT on close.

---

## 5. Testing

All tests are headless and run through `tools/tgrun/tgrun`.

**`tgrun` usage:**

```
tgrun rom.pce frames out.ppm [from to padhex]...
```

**Environment variables:**

| Variable | Does |
|---|---|
| `TGRUN_DUMP` | Screens per frame |
| `TGRUN_PEEK` | RAM, read by name through `tools/peek.py` with `build/main.sym` |
| `TGRUN_SATB` | SATB per frame |
| `TGRUN_VCE` | VCE |
| `TGRUN_VRAM` | VRAM |
| `TGRUN_WAV` | Audio |
| `TGRUN_PSGLOG` | Every PSG register write |
| `TGRUN_NOSPRLIMIT=1` | Turns off the 16-cells-a-line sprite limit |
| `TGRUN_PC=1` | The CPU's PC at the end of every frame, on stderr (to find a hang) |

| Test | Checks |
|---|---|
| `test_scroll.py` (3 runs) | Every sampled frame of the camera build matches the converter's `preview.png` pixel for pixel: horizontal, downward and the castle shafts |
| `test_player.py` | Walk, crouch, jumps, attacks (including the standing up attack), ropes, collision, the frame budget |
| `test_enemies.py` | Hits, kills, a crouching Rastan ducking the lizardmen, spawn lanes and timing, clubs, frame budget |
| `test_effects.py` | Waterfall cycle, the sky's steps (and a restart's), hazards, death animation |
| `test_debug.py` | The menu needs a hold; the screen comes back exactly; warps, invincibility, checkpoint restart |
| `test_items.py` | Weapons, items, bats (weapon drawing is sampled over 4 frames: the fire sword's flame hides behind the blade on some) |
| `test_monsters.py` | Chimeras, boulders, gargoyle, woman, boss; the round-clear screen and jingle; the hurry-up swarm (arrives after 40 counts, closes in, bites every 45 frames at most, dies to the sword for 100; in a crowd, drawn 85% of the time or more) |
| `test_castle.py` | Soldiers, spears, jets, vines, doors, camera walls; the round is cleared within 4400 frames; the hanging column's cycle and its blocking; the sealing wall's timing and push; shaft 2's weights: when they appear, their 147-frame cycle, the kill standing and the crouch under them; the soldiers' high and low swings against a crouching and a standing Rastan; colour bank 48 / 64 (VCE) |
| `test_sound.py` | PSG writes match the streams; notes are in the audio spectrum; the voices' levels in order on channel 5 |
| `test_demo.py` | The image is a 2.5 MB SF2 card; title, blink, RUN starts, pause; no debug menu in play; UP+SELECT on the title opens it as a screen of its own (no game under it; SELECT back to the title; its new game starts at checkpoint 4, invincible, 5 lives, the axe), and still none in that game; GAME OVER → title → new game |

### The audit

`make audit` runs `tools/audit.py`.

**The god build:** for each checkpoint, a bot plays on and the audit writes contact sheets to `build/audit/cpN.png`. It fails on:
- poses a kind does not have;
- slowdown (frames with no logic, outside restarts, doors and stills).

**The bgcheck build:** every 10th frame is compared with the preview, and every pixel must match.

**Options:**
- `AUDIT_CPS=3,4` limits the run to those checkpoints.
- `AUDIT_EVERY` sets the sampling interval.

**Bot routes** are in `tools/routes.py`: `ROUTE_A` (castle), `ROUTE_SHAFT`, `ROUTE_B` (boss room) and `ROUTE_V`.
- They are frame-timed **from the frame play resumes after the warp**. `routes.resume(rom, cp)` measures that frame in the build under test, and `routes.keys(rom, cp, route)` places the warp and the route.
- **Restarts may take any time.** The compression made them up to 37 frames shorter, which used to break every route.
- **What still shifts the routes:** a change to the game's own timing once play has resumed, such as enemy clocks or the vines' shared clock. Re-time the routes with `shift()` in that case.

### Debugging tools

- `python3 tools/trace_player.py rom frames from to pad` prints Rastan's state every frame.
- `tools/peek.py` reads any `.zp`/`.bss` symbol.
- To debug something visual, dump the frames with `TGRUN_DUMP` and look at them.

---

## 6. Pitfalls that cost time

1. **PCEAS precedence:** `>X + 1` parses as `>(X+1)`. Write `(>X) + 1`. This made the GAME OVER wait never end.
2. **Local labels (`.name`) are scoped to the previous global label.**
   - A routine that jumps to a local label across a global label fails to assemble, or silently goes to the wrong place.
   - When in doubt, use global names, as `fire_done` and `fire_half` do.
3. **Map the bank before reading table data.**
   - `start_walk` read the walk animation without mapping the kind's group bank (`map_kind`).
   - Lizardmen went invisible, or showed stray blocks near the HUD, depending on which bank happened to be in MPR3.
   - Any routine that reads object data must call `map_kind` first.
4. **`camera_update` falls through into `camera_clamp`.**
   - Code inserted between them (once, `cam_rest`) silently disables the clamp.
   - `test_castle.py` now checks the camera walls, and the bgcheck audit catches the symptom (wrong tiles visible).
5. **PSG_AR (channel select) cannot be read back.**
   - The timer IRQ writes channel 5, so every other PSG access must run under `sei` and keep `psg_ar` current.
   - The IRQ restores it on exit.
6. **The timer IRQ swaps MPR3.**
   - It saves and restores the mapping.
   - Code that relies on MPR3 inside a `sei` section is safe. Code that changes MPR3 without `sei` is also safe, because the IRQ restores the mapping.
7. **The VDC's limits are real:**
   - 64 SATB entries;
   - 16 cells per scanline (a 32-wide sprite counts as 2).
   - The patched tgemu emulates the per-line limit. A test that passes with `TGRUN_NOSPRLIMIT=1` but not without it is a crowding problem, not a logic bug.
8. **tgemu as shipped by HuC** had a one-shot timer, no PSG direct D/A and no SF2 mapper. The copy in `tools/tgemu/` is patched. Do not swap in an upstream build.
   - Its SF2 decode is strict: only bank `$00` at offsets `$1FF0-$1FF3` switches pages, as on the card.
   - `make` rebuilds `tgrun` when the core's sources change.
9. **Segment-local coordinates vs world coordinates.**
   - Items and markers in shafts have negative world y.
   - Comparisons that only check x (as the morning star's appear check once did) trigger on the wrong floor. Check that the y signs match.
10. **SF2 pages.** Data in CPU banks `$40-$7F` exists only while its page is selected.
    - Anything shared between rounds, or read from an interrupt, goes in `$00-$3F`.
    - The page register is write-only and is not saved anywhere, so code that switches pages must switch back.
11. **`make` does not notice recipe changes.** Changing an argument in a rule (for example the objects' first bank) does not rebuild its target. Delete the output (`build/objects/objcells.bin`) to force the rebuild.
12. **Zero page is full.** The HuC core and System Card variables start at `$20DC`; the core's own (`_bp`, `_si`, `vdc_crl`, `irq_vec`, `_ax`…) from `$20EC`. PCEAS does not stop a `.zp` variable from landing on them. Six bytes of swarm variables did, `irq_vec` was overwritten, and the game hung in `wait_vsync` the moment the first bat appeared. New variables go in `.bss`. Check the top of the zero page in `src/main.lst` (`F8:20xx`); it now ends at `$20E1`. `TGRUN_PC=1` prints where a hang sits.
13. **`pb_*` is one solid box shared by the cave block, the hanging column and the sealing wall.** They never meet: outside, the first room's row 0, below row 0. The swarm borrows `pb_*` for its hit tests and restores it.
14. **Frame-timed routes and fixed-cycle objects.** The hanging column shuts route A's corridor for most of its 540-frame cycle, so route A waits there 540 frames (three vine periods too). A new periodic object on a route needs the same care. Shaft 2's weights (147 frames) kill even in the god build (traps check only the debug menu's invincibility, not `GOD_MODE`); route B passes between them, but a change in its timing before the corridor can put Rastan under one.
15. **The debug menu once popped up at random, and drew over the stage.** SELECT alone opened it, and some pads and emulators send it spuriously; and opened in play, its font and colours overwrote the stage's (the sky showed through in the menu's colours). It is now a screen of its own on the title (`title_menu`, UP+SELECT held), which sets up a new game; title builds have no menu in play (`dbg_on` stays 0). Only `testdbg.pce` and the other test builds, which have no title, keep the in-play menu for their warps.
16. **Arcade positions in the castle's later squares.** The census tools' camera x is `(segment - 1) × 512` plus the scroll register. In the jets' room and shaft 2 (the arcade's segments `$14`, `$15`) that counter is one ahead of the port's squares, so the port's x is that minus 512 (the restart point: 9808 → 9296; the jets: 10384 → 9870 was taken 2 px off). Take positions on frames where the scroll registers do not change: a moving camera puts 1-2 px of jitter in them. For the vertical, the same view is the port's `scroll_y` = the arcade's (Rastan's y − his screen y) + 8.
17. **pceas packs the HuC library's procedures into the bank with the least free space that holds them** (`vdc_set_mode`, `read_joypads`, `init_screen`, `vdc_clear_vram`, `clear_vce`, about 500 bytes). Packed into a code bank (4 or 5, assembled after them), the bank's location counter is left at the procedure's end and the bank's own code lands on top: hundreds of "Symbol's bank or address changed in final pass" errors through that bank, with no hint of the cause. It happens as soon as bank 4's or 5's free space drops below the landing bank's. `main.asm` keeps a landing place: the title's second bank (7) is filled up to `PROC_ROOM` (512) bytes from its end. If a code bank's free space ever falls between about 120 and 512 bytes, the procedures can pick it again: shrink `PROC_ROOM`, or watch for the symptom.
18. **`vce_list` once indexed its list with Y alone**, so a list over 63 colour pairs wrapped and rewrote the first ones. The sky's lists are longer: the pointer now moves on 4 bytes a pair. `dyncolor.inc` lives in data bank `$08` (bank 0 is full); `dyn_reset`/`dyn_update` map it into MPR3 themselves.
19. **The floor spears' clock starts when they appear** (the camera rising into the middle room), not at the restart. Route A's timing past them depends on it: it waits 36 frames more there, and 144 more at the room's left end so the vines' 180-frame clock (which runs from the restart) meets it as before. `routes.A_LATE` (720) is everything added to route A since it was measured; tests and the audit time route A with it.

---

## 7. Recipes

### A new enemy or object kind

1. Write a capture script in `sim/scripts/` that makes the enemy appear, and add it to the Makefile's snapshot rules.
2. Add the capture to `FILES`/`GROUPS` in `tools/object_specs.py`, with `PATHS` if it flies a fixed path. Re-run `pce_objects.py`.
3. Add the kind to `kind_ptab_l` and the related tables in `src/enemies.asm`, and write its update routine. Late kinds live in bank 5 and are reached from `enemies_update`.
4. Spawn it from its map marker. The collision map's high byte holds markers.
5. Add checks to the relevant `test_*.py`. Run `AUDIT_CPS=<n> make audit` on its section.

### A new still screen

Add a line to the Makefile:

```sh
python3 tools/pce_still.py NAME snap frame x0 y0 layers sprites build/still [--keep] [--clear] [--grey] [--text X,Y,STR]
```

Then:

1. `incbin` the resulting `NAME.bin` into a free bank in `main.asm`.
2. Add an entry to `still.asm`'s table.

### A new sound command

1. Find the command number in `sim/sim`'s `sndlog`.
2. Add it to `MUSIC` or `EFFECTS` in `tools/pce_sound.py`, with its length and whether it loops.
3. Rebuild. The converter writes `SND_*` and `SFX_*` indices to `build/sound/*.inc`, and their order follows the lists in `tools/pce_sound.py`.
4. Start it:
   - a tune: `lda #SND_x` / `jsr sound_music`;
   - an effect: `lda #SFX_x` / `jsr sound_sfx`.
   - `sound_stop` silences everything.

---

## 8. What to do next

The order is roughly by the value it adds to the demo for the effort.

1. **The rest of the hits by the arcade's rules.** The arcade's collision code is now known (below), and every object's body box, Rastan's body box per pose and his weapon's per pose and weapon come from its tables (`kind_*` in `enemies.asm`; `write_boxes` in `pce_player.py` → `player.inc`; `sword_box`/`body_box` in `player.asm`). So do the hits' effects (`player_hit`, `player_touch`, `kind_touch`; below). Still the port's own: the fire jets' and the item bat's boxes and touch, and the gargoyle (the arcade's sword test skips slot 9, its body, but not slot 10, its wings: they can be struck; the port's gargoyle cannot be). Also:
   - **What a hit does** (`$054A2C`): each hit-list entry's type (an object's `($29,A4)` for a touch, `($28,A4)` for its armed weapon) picks a handler from `$0550A8` at 2 × type − 1 (in round 1; `$10D388`, set by later rounds' items, changes that): type 1 and 2 drain `$400`/`$800` with no knockback (latch `$10D366` for 80 frames, `$059894`), 3-6 cost `$C00`-`$1800` knocked back, 12 kills. Not attacking, a hit puts him in the hurt state (`$10D2F0`, 23 frames; a drain's starts at 12, so 11), then 32 frames untouchable (`$10D30E`/`$10D30C`); attacking, he keeps on and is untouchable 16. Measured types: lizardmen and throwers 1, chimeras, gargoyles (body and wings) and soldiers 2, clubs, fireballs, boulders, the boss and its fire 3, the woman warrior 0; weapons 3 (the thrower's 2, unused).
   - **When Rastan's weapon hits** (`$054982` sets `$10D2F8`): not while `$10D2F0` = 1 (hurt; weapon frames 28-30, the pose once taken for an up thrust); in an attack (`$10D108` = 1) always with the fire sword (`$10D2FA` = 4) or in a down thrust (`$10D116` = 1), else while its timer `$10D10A` is 3..13; out of an attack only in state 2 (rising in a jump). Its box: the weapon's table indexed by `$10D244`, as is for facing left (`$10D114` = 2), mirrored otherwise. Rastan's body: `$05C90E` the same way (x0, x1, y0), y1 from `$05CD5A` by `$10D246` (26 in play).
   - The weapon test (`$044A7A`, when `$10D2F8` = 1) runs over slots 0-28, skipping slot 9, slots from 10 whose type (`+6`) is below 8 (except 3) or `$0F`/`$16`, and a few others; each against `$10D254`.
   - The soldiers swing high or low at random (the arcade: `($21,A4)` bit 2, a byte that changes each approach; boxes `$3A`/`$3C`, `$AE`/`$B0`; poses from the tables at `$042FBC` and `$042FD4`). The port captures both (`sword_low`, `mace_low`: `castle.snp` frames 1272-1350) and picks one per attack with `rand`; `e_alt` marks a low swing.
   - **How a swing hits:** the walker's attack step table (`$042F92`: per 3-frame step a pose and an armed box index at `($22,A4)`; `$38` the lizardman's) arms the weapon; `$044B2C` tests armed boxes (index + 1 facing left) against Rastan's and disarms on a hit, so a swing hits at most once. `($38,A4)` picks the reach: below 3 as listed, 3 adds `$70`, above 3 adds `$74` (the mace).
   - **How the arcade tests a touch:** `$0449B4` clears the hit lists (`$10D2A8`, `$10D2C8`, 4 entries of 8 bytes), then for each object slot takes a box index (`$0446BC`, or for map objects with `+$0B` set, `$044548` and its table at `$044582`: `$47` the column `$13` + length / 2, `$45` the weights `$27` + length / 2, `$4D` the wall `$43` + length / 2 − 1) and tests it (`$044CBA`, inclusive) against Rastan's box: `$10D248` for slots below 18, `$10D22C` (8 px narrower each side) from 18 on. Box entries are 4 signed bytes (x0, x1, y0, y1) at `$044CE0` + 4 × index, relative to the object's (x, y). A hit is processed the next frame (`$054A2C`): the entry's type picks the effect through the table at `$0550A8` (damage `$800`-`$1800`, or `$0553D6`: death).
   - The column's box (8 px either side, Rastan's 12) gives the measured 21 px push. The wall's box (x 16 .. 20 + 4 n) is relative to its object, whose x was not tied to the port's; its push stays measured.
2. **The lava hall's vines and the fire's sparks.** The three vines swing together, and their grab box is a guess. Measure them like the chasm vine (`vine.snp`).
3. **More compression, if needed.**
   - The stage stream is now 206 KB (dictionaries; §4.7). The 3,645 raw patterns are 57% of it.
   - A cheap per-pattern code would save about 15%: a bit mask for zero bytes and for rows that repeat the row above.
   - zlib-class LZ would save about 35%, but would need a RAM window and more CPU time in the frame.
   - At the current size, two rounds fit in each free page, so this is not urgent.
4. **Rounds 2–6.**
   - The world decoder, segment layout and converter are generic. The bot needs to reach those rounds to capture their palettes.
   - Each round needs its own stage outputs, placed in a free page (0, 2 or 3).
   - Make `sf2_round` and the `^stage_*` bank references per round: a small table of page, banks and line count, indexed by the round.
   - `$10D2A6` is only a candidate health counter. Poke invincibility, or jump straight to a round via the continue table.
5. **The exact port of the player.**
   - `tools/m68k` and `tools/lockstep.py` reproduce the arcade's player update call for call (9,215/9,215 calls).
   - A HuC6280 back end translating those routines would replace the hand-written `player.asm`.
   - PR #5 is the owner's work in this direction. Coordinate before touching it.
6. **Parallax.** See `docs/parallax-feasibility.md`. Round 1's BG strips could come back with raster splits, or with the SuperGrafx's second layer.

---

## 9. Where to look first

| If you are working on… | Read |
|---|---|
| Rastan's movement or attacks | `src/player.asm`, `tools/pce_player.py`, `README.md` §Rastan |
| Anything an enemy does | `src/enemies.asm` (object system), the kind's own file, `tools/object_specs.py` |
| Tiles streaming wrong | `tools/pce_stage.py`, `tools/world.py`, `stream_ahead` in `main.asm`; `make audit` with bgcheck |
| Camera | `camera_update`/`camera_clamp`/`cam_rest` in `player.asm`, `CAMERA_REST` in `tools/world.py` |
| Colours | `pce_stage.py` (palette packing, two sets), `bg_palettes*` in `main.asm`, `src/dyncolor.asm` |
| Sound | `tools/pce_sound.py`, `sim/snd.c`, `src/sound.asm`, `src/voice.asm` |
| Screens and the demo flow | `src/still.asm`, `tools/pce_still.py`, `tools/test_demo.py` |
