"""Object kinds captured from the arcade for tools/pce_objects.py.

FILES maps a capture name to a snapshot in the build directory (written every frame by
sim/sim, with the .own sidecar). GROUPS lists object groups; each group's poses and
animations share one ROM bank (mapped at $8000 while its objects run). A sequence is
(animation name, capture, slot, first frame, last frame[, cell range]); consecutive
frames with the same pieces collapse into one animation step with a duration.
Slots are the arcade's 64-byte object slots from $10C2C0 (0-2 map objects, 4-8 enemies,
9-10 big flyers, 14-16 rocks/items, 17 boss, 18-22 projectiles, 23-28 small things).
"""

FILES = {
    'lizard': 'lizard.snp',      # sim/scripts/lizard.txt: passive, then swinging Rastan at the start
    'blue': 'blue.snp',          # sim/scripts/blue.txt: the same at checkpoint 2
}

GROUPS = {
    # Section 1: lizardmen, blue club throwers and their clubs.
    'sect1': [
        ('liz_walk', 'lizard', 8, 420, 451),
        ('liz_attack', 'lizard', 8, 658, 697),
        ('liz_death', 'lizard', 8, 1536, 1566),
        ('blue_walk', 'blue', 8, 404, 435),
        ('blue_throw', 'blue', 6, 1623, 1658),
        ('blue_walk2', 'blue', 6, 1660, 1691),
        ('blue_death', 'blue', 6, 1946, 1977),
        ('club', 'blue', 18, 1632, 1647),
    ],
}

# Poses the engine refers to by number: (group, animation, step) -> symbol.
POSE_SYMBOLS = {
    ('sect1', 'liz_attack', 3): 'POSE_LIZ_CLUB_OUT',
}
