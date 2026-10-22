"""Object kinds captured from the arcade for tools/pce_objects.py.

FILES maps a capture name to a snapshot in the build directory (written every frame by
sim/sim, with the .own sidecar). GROUPS lists object groups; each group's poses and
animations share one ROM bank (mapped at $8000 while its objects run). A sequence is
(animation name, capture, slot, first frame, last frame[, cell range]); consecutive
frames with the same pieces collapse into one animation step with a duration.
Arcade slots are its 64-byte object slots from $10C2C0 (0-2 map objects, 4-8 enemies,
9-10 big flyers, 14-16 rocks/items, 17 boss, 18-22 projectiles, 23-28 small things).
"""

FILES = {
    'lizard': 'lizard.snp',      # sim/scripts/lizard.txt: passive, then swinging Rastan at the start
    'blue': 'blue.snp',          # sim/scripts/blue.txt: the same at checkpoint 2
    'item': 'item.snp',          # sim/scripts/item.txt: the axe in the cave and its bat
    'fire': 'item_fire.snp',     # sim/scripts/item_fire.txt: the fire sword (segment 4)
    'star': 'item_star.snp',     # sim/scripts/item_star.txt: the morning star (segment $0C)
    'chimera': 'chimera.snp',    # sim/scripts/chimera.txt: chimeras from checkpoint segment 4
    'gargoyle': 'gargoyle.snp',  # sim/scripts/gargoyle.txt: the gargoyle from checkpoint segment 8
    'woman': 'woman.snp',        # sim/scripts/woman.txt: the woman warrior (x 4523)
    'castle': 'castle.snp',      # sim/scripts/castle.txt: castle soldiers (mace slot 4, sword slot 6)
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
    # Weapon items (slot 17, a 16-frame shimmer) and the bat that guards each (slot 16).
    'items': [
        ('item_axe', 'item', 17, 1057, 1072),
        ('item_fire', 'fire', 17, 1296, 1311),
        ('item_star', 'star', 17, 873, 888),
        ('bat', 'item', 16, 1100, 1131),
    ],
    # Chimeras (walk left, stop to breathe fireballs) and their fireballs.
    'chimera': [
        ('chim_walk', 'chimera', 7, 759, 792),
        ('chim_breath', 'chimera', 7, 946, 1058),
        ('chim_death', 'chimera', 7, 2132, 2162),
        ('fireball', 'chimera', 18, 1028, 1043, (0x1ba, 0x1bc)),
    ],
    # Boulders (arcade slots 14/15): one spin cycle.
    'rocks': [
        ('boulder', 'chimera', 14, 1294, 1341),
    ],
    # The gargoyle: body (arcade slot 9) and wings (slot 10), one flap cycle each
    # (the body keeps one pose).
    'gargoyle': [
        ('garg_body', 'gargoyle', 9, 900, 900),
        ('garg_wings', 'gargoyle', 10, 875, 890),
    ],
    # The woman warrior (arcade slot 7): walk, hop down a step, death.
    'woman': [
        ('woman_walk', 'woman', 7, 3105, 3120),
        ('woman_hop', 'woman', 7, 3141, 3169),
        ('woman_death', 'woman', 7, 3239, 3269),
    ],
    # Castle soldiers: the same body with a mace or a sword; walk, two swings, death.
    'castle': [
        ('mace_walk', 'castle', 4, 2526, 2557),
        ('mace_attack', 'castle', 4, 2622, 2699),
        ('mace_death', 'castle', 4, 2726, 2756),
        ('sword_walk', 'castle', 6, 2526, 2557),
        ('sword_attack', 'castle', 6, 2622, 2699),
        ('sword_death', 'castle', 6, 2726, 2756),
    ],
    # Fire jets over the castle's lava pits: the flame rising, then the column flickering.
    'jets': [
        ('jet_rise', 'castle', 1, 1481, 1497),
        ('jet_column', 'castle', 0, 1477, 1485),
    ],
}

# Scripted flights, replayed relative to the spawn point:
# name -> (group, capture, slot, first frame, last frame).
PATHS = {
    'gargoyle': ('gargoyle', 'gargoyle', 9, 861, 1271),
}

# Pieces per pose (src/enemies.asm slot buffers): walkers 11 (the default), items and
# bats 4, specials 13; projectiles 2 (single-piece here).
GROUP_MAX = {'items': 4, 'rocks': 13, 'gargoyle': 13, 'jets': 13}

# Poses the engine refers to by number: (group, animation, step) -> symbol.
POSE_SYMBOLS = {
    ('sect1', 'liz_attack', 3): 'POSE_LIZ_CLUB_OUT',
    ('castle', 'mace_attack', 6): 'POSE_MACE_OUT',      # arcade anim 166: the swing's reach
    ('castle', 'sword_attack', 6): 'POSE_SWORD_OUT',
}
