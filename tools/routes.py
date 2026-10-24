"""Input routes through round 1 (tgrun key lists), shared by the tests and tools/audit.py.

A route is timed from the frame play resumes after a debug-menu warp (its frame 0 is
the first game frame after the restart), not from power-on: a restart's length
depends on how fast the stage streams, and the routes must not change with it.
keys(rom, cp, route) gives the warp and the route placed for a given build.
"""
import subprocess
I = '40'
OPEN, RIGHT = '11', '04'

def shift(route, d):
    """The same route d frames later."""
    return [v + d if isinstance(v, int) else v for v in route]


# Route A, measured against this build (the arcade cannot be driven through here):
# 830 waits for the middle corridor's floor spears to sink; the four jumps from 2990
# cross the lava hall on its three vines.
ROUTE_A = [200, 449, '04', 450, 453, '08', 470, 473, '41', 474, 700, '01', 710, 713, '48', 714, 760, '08',
           830, 1050, '08', 1055, 1058, '04', 1070, 1073, '41', 1074, 1310, '01', 1320, 1323, '44',
           1324, 1580, '04', 1581, 1584, '08', 1600, 1603, '41', 1604, 1840, '01', 1850, 1853, '48',
           1854, 2080, '08', 2081, 2100, '04', 2105, 2108, '41', 2109, 2460, '01', 2470, 2473, '44',
           2474, 2639, '04', 2645, 2648, '41', 2649, 2840, '01', 2850, 2853, '44', 2854, 2989, '04',
           2990, 2993, '45', 2994, 3123, '04', 3124, 3127, '44', 3128, 3229, '04', 3230, 3233, '44',
           3234, 3329, '04', 3330, 3333, '44', 3334, 3600, '04']
# (Measured from power-on on a build whose warp to checkpoint 4 resumed play 2 frames
# sooner than the one that later ran it at 223: the route, 2 frames later, from 223.)
ROUTE_A = shift(ROUTE_A, 2 - 223)
# The top corridor's hanging column (src/column.asm) comes down as he walks right at
# 1103 and shuts the corridor for most of its 540-frame cycle: he keeps pushing right
# until it has gone up and he is through (at the rope by about 1700), 540 frames more
# (the column's period, three of the vines'), so the rest runs as it did.
_i = ROUTE_A.index(1359)                 # (the end of that walk: 1580 - 221)
ROUTE_A = ROUTE_A[:_i] + [1359 + 540] + shift(ROUTE_A[_i + 1:], 540)
# The middle corridor's floor spears appear as the camera rises into its room, their
# clock starting then (src/traps.asm): he waits 36 frames more before walking left
# past them, then 144 more at the room's left end (x 8233, clear of them), so the
# rest keeps the vines' 180-frame phase. A_LATE: the frames added since measuring.
_i = ROUTE_A.index(609)
ROUTE_A = ROUTE_A[:_i] + shift(ROUTE_A[_i:], 36)
_i = ROUTE_A.index(870)
ROUTE_A = ROUTE_A[:_i] + shift(ROUTE_A[_i:], 144)
A_LATE = 540 + 180
# The same up to the top of shaft 1's lower rope, where he hangs still (from 2969).
SHAFT_HANG = 2249 + A_LATE
ROUTE_SHAFT = ROUTE_A[:ROUTE_A.index(SHAFT_HANG)]

ROUTE_B = [200, 830, '05'] + sum([[f, f + 3, I] for f in range(220, 830, 60)], []) + [
    831, 1100, '04', 864, 867, I, 914, 917, I, 964, 967, I, 1101, 1103, '08', 1110, 1113, '41', 1114, 1470, '01',
    1480, 1483, '48', 1484, 1572, '08', 1590, 1593, '41', 1594, 1830, '01', 1840, 1843, '48', 1844, 1990, '08',
    1991, 1995, '04', 2010, 2013, '41', 2014, 2280, '01', 2290, 2293, '44', 2294, 2491, '04', 2510, 2513, '41',
    2514, 2760, '01', 2770, 2773, '48', 2774, 3278, '08', 3283, 3285, '04'] + sum([[f, f + 1, '80'] for f in range(3298, 4150, 25)], [])
# (In the boss room he walks left down the steps to the floor the boss walks, turns
# and swings at it as it comes: from the top step his blade passes over its box.)

ROUTE_B = shift(ROUTE_B, -228)          # (that build resumed at 228 from checkpoint 5)

ROUTE_V = [200, 350, '04', 360, 363, '41', 364, 600, '01', 610, 613, '44', 614, 1300, '04', 730, 733, '44',
           832, 835, '45', 965, 968, '44']
ROUTE_V = shift(ROUTE_V, -173)          # (and at 173 from checkpoint 1)


def warp_at(cp):
    """The frame warp(cp) applies its checkpoint: 150 (later for the later rounds')."""
    return max(150, 100 + 6 * cp + 6)


def warp(cp):
    """Debug menu: open it, pick checkpoint cp (numbered through every round: src/debug.asm),
    apply (frame warp_at(cp))."""
    if cp == 0:
        return []
    return ([40, 90, OPEN] + sum([[100 + 6 * k, 100 + 6 * k, RIGHT] for k in range(cp)], [])
            + [warp_at(cp), warp_at(cp), I])


_resumed = {}


def resume(rom, cp):
    """The frame play resumes after warp(cp) in this build: the first frame after the
    warp in which player_update runs (p_frame moves)."""
    if (rom, cp) not in _resumed:
        from peek import peek
        r = peek(rom, 500, warp(cp), {'p_frame': 1})
        start = warp_at(cp) + 1 if cp else 1
        _resumed[rom, cp] = next(i for i in range(start, len(r)) if r[i]['p_frame'] != r[i - 1]['p_frame'])
    return _resumed[rom, cp]


def keys(rom, cp, route, extra=()):
    """warp(cp), then route (and extra keys, timed like it) from the frame play resumes.
    Returns (keys, that frame)."""
    base = resume(rom, cp)
    return warp(cp) + shift(list(route) + list(extra), base), base
