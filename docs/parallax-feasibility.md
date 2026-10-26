# Background parallax on one PC Engine BG layer: feasibility

In the arcade, the BG layer (sky, mountains, statues) scrolls horizontally at half the speed of the FG layer
(ground, cliffs, ropes, platforms). The two layers share the vertical scroll. The port currently merges both
into one layer at the FG's speed, so the parallax is gone.

## Technique

The standard PC Engine approach is a **raster split**. A scanline interrupt (RCR) changes the BG scroll registers
partway down the screen:

- **Above the split:** a BG-only band scrolled at half speed.
- **Below the split:** the merged map as now.

The split must sit above every FG pixel on screen. Otherwise FG objects in the band would vanish.
The CPU cost is negligible: one interrupt and two register writes per frame.

## Measurements (round 1, section 1 = world x 0-2047, camera y about 171)

| Question | Result |
|---|---|
| Positions where nothing in the FG rises above the ground line | **76%**. There the split sits at the ground and the result **matches the arcade exactly**, with the seam hidden behind the ground |
| Positions where FG rises above the ground (cliff at the start, rope mountain, floating platforms) | 24%. The split moves up to that object, so the mountains between it and the ground scroll at full speed and a **horizontal seam** cuts through them (median 82 lines, worst case the whole band) |
| BG band tiles needed (visible rows above the ground, any 34-column window) | 445-517 unique patterns |
| Merged-map tiles below the ground line | 339 at peak |
| Total with nothing above the ground | about 790-860 of 1,024 tile slots: **fits** |
| Merged-map tiles today (full height columns) | 930 at peak |
| Later in round 1 (castles, forests) | FG reaches the top of the screen in more than a quarter of the positions. Little BG shows there, so the split would simply sit near the top |

Mockups (`build/parallax_mock.png`, generated locally from the arcade data) compare the arcade, the port today
and the split at two positions. On open ground the split looks the same as the arcade. At the rope mountain the
statue is cut in two by the seam.

## What it would take

The current engine cannot add a band just by adding an interrupt. Two of its foundations would change:

1. **Tile map space.** The 64x64 tile map is full: the merged map's columns hold all 64 rows (512 px) so vertical
   scrolling is free, and side by side the two layers would need 34 + 34 = 68 columns. The band has to use rows
   instead. That means streaming the map in **rows as well as columns**: about 29 rows for the merged map and
   up to 23 for the band.
2. **Tile residency.** VRAM tiles are scheduled offline per full-height column (`tools/pce_stage.py`). With
   vertical windows, which tiles are needed depends on the camera's height at run time, so the offline schedule
   no longer works. A **run-time tile cache** would replace it: reference counts per resident pattern, freed when no
   visible tile uses them. The working-RAM cost is a few hundred bytes for the resident set, not a table per pattern.

The ROM data changes too: BG strips at half speed need their own column records (they're small, round 1 has 5
distinct strips), and merged-map records only need the FG-covered rows below the split.

## Options

| Option | Look | Effort |
|---|---|---|
| **A. Keep 1:1** (today) | No parallax | None |
| **B. Raster split at the topmost FG pixel**, with 2D streaming and a tile cache | Matches the arcade on open ground (76% of section 1); a seam through the mountains when something tall is on screen | Large: rewrite of map streaming and VRAM management |
| C. Sky-only band (clouds above the highest mountain peak at half speed) | Partial parallax, sky slides against the mountains; not what the arcade does | Medium (still needs row-space in the tile map) |

## Recommendation

**B is feasible within the hardware limits** and gives arcade parallax most of the time. It costs a
streaming rewrite, which also gives us row streaming (useful for the castle and vertical sections later).
Because it touches the core of the engine, it is best done **after section 1 reaches parity**, not before,
so that the parity tests can check it doesn't break anything.
