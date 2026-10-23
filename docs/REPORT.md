# Rastan → PC Engine: round 1 proof-of-concept report

**State on 2026-10-23, branch `section1-parity`.**

Round 1 of Taito's *Rastan* (1987 arcade) runs on a PC Engine / TurboGrafx-16 HuCard. The run covers the title screen, the whole round with its castle and boss, the round-clear screen with its jingle, and GAME OVER. Everything on screen and in the speakers was converted from the arcade program and ROMs by the tools in this repository. Gameplay values were measured by running the arcade program headless.

The demo ROM is `build/rastan.pce`:
- size: a 2.5 MB image for the Street Fighter II mapper card, the PC Engine's largest HuCard;
- round 1's stage data: compressed 2.5x, from 513 KB to 206 KB;
- test suite: passes;
- full-playthrough audit: 0 problems.

---

## 1. What the demo shows

| Part | In the demo |
|---|---|
| **Title** | The arcade's title screen in its own font. PUSH RUN BUTTON blinks, and RUN starts the game. |
| **Round 1, outdoors** | The arcade's map from the start to the castle gate:<br>• the cave and its block, broken by a down thrust;<br>• ropes;<br>• the chasm vine;<br>• the waterfall, with its flowing colour cycle and deadly lip;<br>• the sky's 8 steps toward dusk (a restart shows its checkpoint's);<br>• rockfalls and rolling boulders. |
| **Enemies outdoors** | • Lizardmen;<br>• blue club throwers and their clubs;<br>• chimeras and their fireballs;<br>• two gargoyle flights;<br>• the woman warrior;<br>• five weapon items, each with its bat. |
| **The castle** | Laid out as the arcade lays it out, in the castle's own colours:<br>• the first room;<br>• shaft 1, scrolling up;<br>• the lava hall, with its animated fire and three vines;<br>• the jets' room;<br>• shaft 2;<br>• the boss room door. |
| **Enemies in the castle** | • Sword and mace soldiers, gold and blue (green after a restart at the last two checkpoints, as in the arcade);<br>• floor spears;<br>• the first room's hanging column, which shuts the top corridor most of the time;<br>• the lava hall's sealing wall, which pushes a lingering Rastan into the fire;<br>• fire jets;<br>• shaft 2's three spiked weights, which come down on the corridor at its top and kill on touch. |
| **Hurry-up swarm** | Anywhere but the boss room: dawdle 42 s in one pair of segments and nine small bats come for Rastan, faster with each wave. |
| **Boss** | Drops in, walks, leaps, staff swing, a fan of fire from above. Ten hits kill it. |
| **Round clear** | The arcade's screen (YOU ARE A BRAVE FIGHTER…) with its jingle for 7 s (RUN skips it after 2 s), then the title. |
| **Rastan** | • Walk, crouch, jumps (low, high and forward);<br>• attacks: standing, crouched, in the air;<br>• the standing up-swing;<br>• down and up thrusts;<br>• ropes and vines;<br>• the four weapons;<br>• knockback, invulnerability flashes and the death animation. |
| **HUD** | The arcade's: 1UP score, high score, lives, the Rastan icon, the draining health bar, and ROUND 1. |
| **Sound** | • The round 1, castle and boss music, converted from the arcade's YM2151 output;<br>• the effects;<br>• the jump grunt and death cry as real samples (MSM5205 ADPCM, played through the PSG's D/A). |
| **Flow** | • Deaths restart at the arcade's checkpoints.<br>• GAME OVER when the last life goes, then the title.<br>• **RUN pauses** the game and the sound. |

**Controls:**
- **D-pad:** move and crouch; UP grabs ropes.
- **I:** jump. Hold a direction for a forward jump, or UP for the high jump.
- **II:** attack. UP+II standing swings overhead. In the air, DOWN+II is the down thrust and UP+II the up thrust.
- **RUN:** start and pause.

### Presenting it

- The image uses the **Street Fighter II mapper**, so it needs an emulator or flash cart that supports that mapper.
  - Emulators recognise the mapper by the image size, which is why the image is padded to exactly 2.5 MB. MAME accepts only that size.
  - MAME and Mednafen support the mapper, because they run *Street Fighter II' Champion Edition*. For other emulators, check before relying on them.
  - Not every flash cart supports it. Check yours before a live demo.
  - So far the image has been run only in the project's own test emulator, which is patched to decode the mapper like the real card. Try it in your target emulator before presenting.
- **The debug menu is on the start screen only.**
  - There is no menu in play, so no button can interrupt a presentation.
  - To show a particular section, hold **UP + SELECT on the title screen** for about ¾ s (`rastan_debug.pce`: SELECT). The menu is a screen of its own: pick the checkpoint to start at, invincibility, lives and so on, then START GAME (or RUN).

---

## 2. How it was verified

### 2.1 Test suite (`make test`, a few minutes, headless)

Every test drives the real ROM in a patched copy of HuC's `tgemu` emulator (`tools/tgrun`).
- The tests feed it pad input and read back RAM, screens, the SATB, PSG writes or audio.
- They do not depend on the game's own debug output.

| Area | What is checked |
|---|---|
| Background | 3 camera runs (horizontal, downward, the castle shafts). Every sampled frame must be pixel-identical to the converter's preview of the map. |
| Rastan | Movement, jumps, attacks including the up-swing, ropes, collision, and that no frame overruns. |
| Enemies | Hits, kills, spawn lanes and timing, projectiles, and the frame budget with crowds. |
| Effects | Waterfall cycle, the sky's steps, hazards and the death animation. |
| Debug | The menu needs a hold; the screen is restored exactly; warps, invincibility and checkpoint restarts. |
| Items | Weapons, items and bats. |
| Later monsters | Chimeras, boulders, gargoyle, woman warrior, the boss; the round-clear screen and jingle. |
| Castle | Soldiers, spears, jets, vines, doors and the camera walls. A bot clears the round inside 4400 frames. |
| Sound | PSG writes match the converted streams, and the notes appear in the audio spectrum. Voice samples reach channel 5 complete and in order, and the music gets the channel back. |
| Demo flow | Title, blink, RUN to start, pause; no debug menu in play; UP+SELECT held on the title opens it as a screen of its own, whose new game starts where and as it says; GAME OVER → title → a new game. |

### 2.2 Playthrough audit (`make audit`)

A bot plays every section in god mode, starting from each checkpoint.

**What is checked:**
- **The god build:** every frame is checked for impossible object poses and for slowdown.
- **The bgcheck build:** every 10th frame is compared pixel for pixel with the converter's preview. That build shows the tile map alone.
- **Contact sheets** (`build/audit/cpN.png`) are written for review by eye.

The results below are from the run on 2026-10-23, with the swarm, the hanging column, the sealing wall and shaft 2's spiked weights in.

| Section (start) | Distance covered (world x) | Slow frames | Bad poses | Tile-map frames wrong | SATB full¹ | Frames with a sprite lost to the 16-a-line limit¹ |
|---|---|---|---|---|---|---|
| cp0: round start | 49 → 1830 | 0 | 0 | 0 / 240 | 0 | 191 |
| cp1: segment 4 | 2097 → 4708 | 0 | 0 | 0 / 240 | 114 | 322 |
| cp2: segment 8 (waterfall) | 4145 → 5638 | 0 | 0 | 0 / 240 | 120 | 176 |
| cp3: segment 12 → castle | 6193 → 8662 | 0 | 0 | 0 / 240 | 0 | 226 |
| cp4: segment 16 (castle) | 8253 → 9300 | 0 | 0 | 0 / 411 | 0 | 272 |
| cp5: lava hall → boss | 9306 → 11728 | 0 | 0 | 0 / 377 | 0 | 683² |
| **Problems** | | | | | | **0 (both runs)** |

² Up from 502 before the weights: the weights' 32 px bars (two cells a line each) share the corridor's lines with Rastan and the soldiers.

¹ These are reported, not failed: they are the PC Engine's hardware limits, 64 sprites and 16 sprite cells per scanline. When either runs out, the walkers and the swarm take turns losing pieces, which shows as flicker, as many PC Engine games do. No single enemy disappears for good.

**Deaths:** cp0 and cp2 each show one death. In both, the bot fell off the map, which kills even in god mode. They exercise the restart path.

### 2.3 What the audit and tests caught during this phase

All of these are fixed, and each now has a check:

- **Invisible lizardmen, or stray blocks next to the HUD.** The walk animation was read from whatever bank was mapped.
- **The castle gate dropped Rastan 256 px too high,** without the castle music.
- **A torn frame at the boss room door.** Cuts now turn the display off at a VBLANK.
- **Castle soldiers losing pieces.** The SATB ran out of entries; it is now packed.
- **The camera clamp silently disabled** by code inserted in front of it.
- **The debug menu opening at random, and drawing over the stage.** It was opened by stray SELECT bits, and in play its font and colours overwrote the stage's. It now needs a hold, and is a screen of its own on the title only.
- **Voice samples landing on the wrong PSG channel.** The music's writes moved the channel select; this is fixed with a shadow register and `sei`.
- **Stage loads got faster with compression,** which put the frame-timed bot routes out of step: Rastan died at the spears and missed the vines. Routes are now timed from the frame play resumes, measured in each build, so restart length no longer matters.
- **Two bugs in the test emulator itself:** a one-shot timer, and no PSG direct D/A. It also now emulates the per-line sprite limit, so the tests see what hardware would show.

---

## 3. Fidelity: what is exact and what is approximate

### Exact or measured

- **The map:**
  - every tile of round 1, decoded from the arcade's world map, including its 2-D castle layout;
  - streamed so the screen matches the converter pixel for pixel.
- **Colours:**
  - quantised to the PC Engine's 9-bit RGB;
  - packed into two sets of 16 palettes (outdoors and the castle);
  - every segment matches the arcade's colours after quantisation, except the waterfall's colour-cycling ones.
- **Sprite graphics:** the arcade's own cells, captured from its sprite list for every pose.
- **Timings:**
  - spawn timing and lanes;
  - enemy speeds and attack timings;
  - weapon durations;
  - health costs;
  - jump tables;
  - checkpoint positions.
  - All were measured from simulator runs of the real program.
- **Music and effects:** the real sound driver run in a Z80 simulator, at the driver's own tick rate. Loops repeat tick for tick.
- **Voices:** the arcade's ADPCM samples, decoded and resampled.

### Approximate

- **Rastan's movement code is hand-written** from measured values, not translated from the arcade program. The groundwork for an exact translation exists: a 68000 interpreter that matches the arcade on 9,215 of 9,215 recorded calls.
- **Enemy behaviour is re-implemented** from captures (walk in, attack, back off). Paths such as the gargoyle's are replayed exactly.
- **The FM music becomes PSG square/wave voices:** one shared waveform, and low notes moved up an octave.
- **Parallax is gone.** The BG layer is flattened into the FG at 1:1 (see `docs/parallax-feasibility.md`).
- **The lava hall's fire** is baked into the tile map, because there are too many sprites per line for the VDC. Its drifting sparks are not drawn.
- **The lava hall's vines** swing in step. Their grab box is not measured.
- **The standing up-swing's hitbox** is the up thrust's, which has not been measured for this attack.

---

## 4. Known gaps (round 1)

| Gap | Effect on the demo | Notes |
|---|---|---|
| Rastan's hurt box by pose | Two forms only | The arcade's (`$10D248`) is set per pose (x −18/−12/−8 .. 6/12); the port uses its standing and crouched forms |
| Sprite flicker in crowds | Visible when 3–4 walkers share a line, or with the swarm | Hardware limit; mitigated by rotation (walkers and the swarm take turns, and the bats among themselves) |
| Fire sparks | Not drawn | Cosmetic |

---

## 5. Resource use

| Resource | Use |
|---|---|
| **ROM** | A 2.5 MB SF2 image. The fixed 512 KB half holds the code and everything shared between rounds, with 136 KB free. Round 1's own data (stage and collision, 224 KB) is in page 1. Pages 0, 2 and 3 (1.5 MB) are empty. |
| **Code** | About 11,100 lines of PCEAS assembly in 23 modules. Code space is tight: bank $00 has 0.6 KB free, bank $04 1.4 KB, bank $05 1 KB. |
| **VRAM** | BG tile pool: 936 slots, peak 930. Rastan is double-buffered. 17 object slot buffers, plus the HUD (whose free cells hold shaft 2's weights) and the SATB. |
| **CPU** | No slow frames in any audited section. The voice IRQ costs about 9% of the CPU while a sample plays. |
| **Sprites** | The HUD takes the first 12 of 64 entries. Rastan, his weapon, props and objects are packed after it each frame. |

**Scaling.**
- **Before:** round 1's stage stream was 513 KB, so six rounds could not have fitted even in 2.5 MB.
- **Compression:** every BG pattern is now stored once, and the tile map is coded over a dictionary of 4-tile slices of the arcade's blocks. That brings the stream to 206 KB, and the stream decodes faster than the old raw copy.
- **Room for the rest:** at that size, the other five rounds fit two to a page in the three free pages.
- See `HANDOFF.md` §4.2 and §8.

---

## 6. Phase history

The project spans 44 commits (2026-10-20 → 2026-10-23).

1. **Tools:**
   - arcade graphics decoder;
   - a headless 68000 simulator of the arcade board;
   - static world-map decoder;
   - headless PC Engine runner.
2. **Milestone 1:** stage 1 scrolls on the PC Engine, pixel-checked.
3. **Milestone 2:** Rastan (approximate), plus the exact-port groundwork (interpreter and lockstep).
4. **Milestone 3 onwards:**
   - lizardmen, health and HUD;
   - waterfall colours and hazards;
   - spawn lanes;
   - checkpoints and the debug menu;
   - weapons and items;
   - each remaining enemy;
   - the castle's 2-D layout;
   - the boss;
   - music, effects and voices.
5. **This phase:**
   - voice samples and the standing up-attack;
   - the debug menu needs a hold;
   - the playthrough audit and the bugs it found;
   - RUN pause;
   - title, GAME OVER and round-clear screens;
   - the demo build;
   - the castle's own palettes and the lava hall camera;
   - the lava hall's fire;
   - the castle shaft's morning star;
   - the camera clamp fix;
   - stage compression (513 KB → 206 KB) and the move to the Street Fighter II mapper.
   - the hurry-up swarm, the sprite colour bank (soldiers' colours), the hanging column and the sealing wall;
   - shaft 2's spiked weights (marker `$45`), from an arcade bot that now climbs shaft 2;
   - the swarm's share of the sprites: it takes turns with the walkers, so its bats no longer vanish behind a crowd;
   - the bats' bite and the weights' kill read from the arcade's collision code (its box tables), no longer measured;
   - the lizardmen's, soldiers' and clubs' hits on Rastan from the same tables: crouching now ducks a lizardman's swing, as in the arcade, and clubs reach 7 px, not 19;
   - the soldiers' low swing (the arcade picks high or low at random), which does reach a crouching Rastan.

The next steps, in order, are in `docs/HANDOFF.md` §8:
1. the remaining kinds' hits by the arcade's boxes (woman, gargoyle, chimera, boss), and Rastan's box per pose;
2. the lava hall's vines and fire sparks;
3. more compression, if needed;
4. rounds 2–6;
5. the exact player port;
6. parallax.
