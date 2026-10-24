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
    'item_r2': 'item_r2.snp',    # sim/scripts/item_r2.txt: round 2's first item and its dragonfly
    'chimera': 'chimera.snp',    # sim/scripts/chimera.txt: chimeras from checkpoint segment 4
    'gargoyle': 'gargoyle.snp',  # sim/scripts/gargoyle.txt: the gargoyle from checkpoint segment 8
    'gargkill': 'gargkill.snp',  # sim/scripts/gargkill.txt: the gargoyle struck down
    'woman': 'woman.snp',        # sim/scripts/woman.txt: the woman warrior (x 4523)
    'castle': 'castle.snp',      # sim/scripts/castle.txt: castle soldiers (mace slot 4, sword slot 6)
    'boss': 'boss.snp',          # sim/scripts/boss.txt: the boss (slot 17), its fire (slots 18-22)
    'vine': 'vine.snp',          # the bot run (build/vine.txt): the vine at x 2750, slot 0
    'swarm': 'swarm.snp',        # sim/scripts/swarm.txt: the hurry-up swarm at the round start
    'snake': 'snake.snp',
    'knight': 'boss2.snp',       # sim/scripts/boss2.txt: round 2's boss (slot 17), passive Rastan, its orbs
    'knight_leap': 'boss2_leap.snp',  # sim/scripts/boss2_leap.txt: its float leap
    'knight_kill': 'boss2_kill.snp',  # sim/scripts/boss2_kill.txt: its death        # sim/scripts/snake.txt: round 2's snakes (slot 5 crawls, strikes, dies)
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
        ('dfly', 'item_r2', 16, 964, 971),        # round 2's guard (wings beating)
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
        ('garg_death', 'gargkill', 9, 1163, 1179),
        ('wings_death', 'gargkill', 10, 1163, 1179),
    ],
    # The woman warrior (arcade slot 7): walk, hop down a step, death.
    'woman': [
        ('woman_walk', 'woman', 7, 3105, 3120),
        ('woman_hop', 'woman', 7, 3141, 3169),
        ('woman_death', 'woman', 7, 3239, 3269),
    ],
    # Castle soldiers: the same body with a mace or a sword; walk, two swings (high, or
    # low: the arcade picks by bit 2 of the slot's byte $21), death.
    'castle': [
        ('mace_walk', 'castle', 4, 2526, 2557),
        ('mace_attack', 'castle', 4, 2622, 2699),
        ('mace_low', 'castle', 4, 1272, 1350),
        ('mace_death', 'castle', 4, 2726, 2756),
        ('sword_walk', 'castle', 6, 2526, 2557),
        ('sword_attack', 'castle', 6, 2622, 2699),
        ('sword_low', 'castle', 6, 1272, 1350),
        ('sword_death', 'castle', 6, 2726, 2756),
    ],
    # Fire jets over the castle's lava pits: the flame rising, then the column flickering.
    'jets': [
        ('jet_rise', 'castle', 1, 1481, 1497),
        ('jet_column', 'castle', 0, 1477, 1485),
    ],
    # The boss (arcade slot 17, up to 18 pieces): every animation in two parts, the first
    # 13 pieces in the arcade's order and the rest, drawn by two objects. Its fire
    # (slots 18-22): forming at the top of the screen, then raining down.
    'boss': [
        ('boss_walk', 'boss', 17, 950, 1013, {'index': (0, 13)}),
        ('boss2_walk', 'boss', 17, 950, 1013, {'index': (13, 99)}),
        ('boss_rain', 'boss', 17, 1107, 1178, {'index': (0, 13)}),
        ('boss2_rain', 'boss', 17, 1107, 1178, {'index': (13, 99)}),
        ('boss_staff', 'boss', 17, 1365, 1413, {'index': (0, 13)}),
        ('boss2_staff', 'boss', 17, 1365, 1413, {'index': (13, 99)}),
        ('boss_leap', 'boss', 17, 1299, 1335, {'index': (0, 13)}),
        ('boss2_leap', 'boss', 17, 1299, 1335, {'index': (13, 99)}),
        ('boss_death', 'boss', 17, 2224, 2240, {'index': (0, 13)}),
        ('boss2_death', 'boss', 17, 2224, 2240, {'index': (13, 99)}),
        ('frag_form', 'boss', 18, 1107, 1136),
        ('frag_fly', 'boss', 18, 1140, 1160),
    ],
    # Swinging vines (marker $4F, arcade slot 0): one whole swing, 180 frames.
    'vine': [
        ('vine_swing', 'vine', 0, 10755, 10934),
    ],
    # Round 2's snakes (arcade slot 5): crawl (anims 181-183, 4 frames each), one strike of the three
    # in a row (181, 184, 185 for 3, 6, 9 frames), death (the walkers' burst).
    'snake': [
        ('snake_crawl', 'snake', 5, 523, 538),
        ('snake_strike', 'snake', 5, 744, 761),
        ('snake_death', 'snake', 5, 791, 820),
    ],
    # Round 2's boss, the caped knight (arcade slot 17, up to 20 pieces: in two parts like round 1's
    # boss, the first 13 pieces and the rest): standing in the door, in the air (jumps and hops),
    # landing, walking (anims 215-218, 9 frames each), the swing (214, 220-223), the float leap
    # (210-213 rising, 206-209 coming down), death (157-160). Its orbs (slots 18-20, anims 237-239).
    'knight': [
        ('kn_stand', 'knight', 17, 470, 475, {'index': (0, 13)}),
        ('kn2_stand', 'knight', 17, 470, 475, {'index': (13, 99)}),
        ('kn_air', 'knight', 17, 520, 525, {'index': (0, 13)}),
        ('kn2_air', 'knight', 17, 520, 525, {'index': (13, 99)}),
        ('kn_land', 'knight', 17, 595, 602, {'index': (0, 13)}),
        ('kn2_land', 'knight', 17, 595, 602, {'index': (13, 99)}),
        ('kn_walk', 'knight', 17, 823, 858, {'index': (0, 13)}),
        ('kn2_walk', 'knight', 17, 823, 858, {'index': (13, 99)}),
        ('kn_swing', 'knight', 17, 760, 778, {'index': (0, 13)}),
        ('kn2_swing', 'knight', 17, 760, 778, {'index': (13, 99)}),
        ('kn_rise', 'knight_leap', 17, 999, 1061, {'index': (0, 13)}),
        ('kn2_rise', 'knight_leap', 17, 999, 1061, {'index': (13, 99)}),
        ('kn_float', 'knight_leap', 17, 1062, 1101, {'index': (0, 13)}),
        ('kn2_float', 'knight_leap', 17, 1062, 1101, {'index': (13, 99)}),
        ('kn_death', 'knight_kill', 17, 731, 746, {'index': (0, 13)}),
        ('kn2_death', 'knight_kill', 17, 731, 746, {'index': (13, 99)}),
        ('orb', 'knight', 19, 667, 701),
    ],
    # The hurry-up swarm's small bats (arcade slots 20-28): flapping (cells $268-$26A,
    # all bats on one global clock) and the cell a sword hit leaves ($276). src/swarm.asm
    # draws them itself (CELL_SYMBOLS); these captures only bring in the cells.
    'swarm': [
        ('swarm_flap', 'swarm', 21, 2895, 2926),
        ('swarm_dead', 'swarm', 20, 2932, 2934),
    ],
}

# The arcade's sprite colour bank (PC090OJ control, palettes bank..bank+15) is 48 in
# round 1, but a restart at a checkpoint from segment 16 on (the castle's last two)
# switches it to 64 ($0452DA: the restart segment mod 23 >= 16), so everything drawn
# with bank 48's palettes takes bank 64's: the castle soldiers go from gold and blue
# to green. GROUP_BANK fixes a group's bank where its capture used the other one
# (castle.snp's soldiers walk in after such a restart); pce_objects also writes
# objpal_b64.bin, the same palette slots with bank 64's colours, from BANK64_SNAP.
# (The boss capture also ran in bank 64.) B64_GROUPS: the groups a restart at checkpoint
# 4 or 5 can show, whose colours objpal_b64.bin changes.
GROUP_BANK = {'castle': 48, 'boss': 48, 'knight': 48}
# Rounds after the first: snapshots (file in the build directory, frame) with the round's
# sprite colours in bank 48 and in bank 64 (pce_objects writes objpal_r<n>[_b64].bin).
ROUND_PAL_SNAPS = {2: (('round2.snp', 420), ('round2_castle.snp', 420))}
# Groups drawn with a PCE sprite palette of their own, whose colours the engine loads itself:
# group -> {arcade colour: (PCE palette, capture, frame, arcade palette)}. Round 2's knight
# (colour 15) in sprite palette 8 (round 1's props', unused in round 2), with the colours the
# arcade loads for it in the boss room (bank 64's palette 79; build/objects/sprpal8.bin).
FIXED_PALS = {'knight': {15: (8, 'knight', 700, 79)}}
BANK64_SNAP = ('castle', 2600)
B64_GROUPS = ('castle', 'jets', 'vine', 'swarm', 'items', 'boss', 'knight')

# Single cells the engine draws by itself: symbol -> (group, arcade cell). objects.inc
# gets SYMBOL (the cell's number in objcells.bin) and SYMBOL_ATTR (its SATB attribute
# byte as pce_objects writes it for poses: palette, cell bits 8-9, flips).
CELL_SYMBOLS = {
    'SWARM_CELL0': ('swarm', 0x268),
    'SWARM_CELL1': ('swarm', 0x269),
    'SWARM_CELL2': ('swarm', 0x26A),
    'SWARM_DEAD': ('swarm', 0x276),
}

# Scripted flights, replayed relative to the spawn point:
# name -> (group, capture, slot, first frame, last frame).
PATHS = {
    'gargoyle': ('gargoyle', 'gargoyle', 9, 861, 1271),
}

# Pieces per pose (src/enemies.asm slot buffers): walkers 11 (the default), items and
# bats 4, specials 13; projectiles 2 (single-piece here).
GROUP_MAX = {'items': 4, 'rocks': 13, 'gargoyle': 13, 'jets': 13, 'boss': 13, 'vine': 13, 'knight': 13}

# Poses the engine refers to by number: (group, animation, step) -> symbol.
POSE_SYMBOLS = {
    ('sect1', 'liz_attack', 3): 'POSE_LIZ_CLUB_OUT',
    ('castle', 'mace_attack', 6): 'POSE_MACE_OUT',      # arcade anim 166: the swing's reach
    ('castle', 'sword_attack', 6): 'POSE_SWORD_OUT',
    ('castle', 'mace_low', 6): 'POSE_MACE_LOW',         # arcade anim 156: the low swing's reach
    ('castle', 'sword_low', 6): 'POSE_SWORD_LOW',
    ('snake', 'snake_strike', 3): 'POSE_SNAKE_OUT',     # arcade anim 185: the strike's reach
    ('knight', 'kn_swing', 4): 'POSE_KN_OUT',           # arcade anim 223: its sword out (box $93)
}
