"""make_bot.py out.txt [end [start [round [f0:f1:row:c0:c1 ...]]]] : simulator input script - coin, start,
invincible-ish run right with periodic attack/jump, from the round start or (start, hex) the checkpoint that
the arcade's restart table byte for the round's first segment names ($5073A + $17 x (round - 1)).
Used to capture round 1 palettes from the arcade program, and later rounds' objects: a round
after the first starts through the start switch $5FF9F, with the hazards off as in
sim/scripts/round2.txt.

Floor pokes (f0:f1:row:c0:c1): from frame f0 to f1 the cells of collision row `row`, columns
c0..c1 of the arcade's 64x64 window ($10DE00, a word per 8x8 cell), are solid floor (code 1),
so the bot crosses water, pits and climbs it cannot jump (each window opens as Rastan nears
the place and closes once he is past; found by trial: see the rounds' full runs in the Makefile).
The objects there carry on as usual."""
import sys
END = int(sys.argv[2]) if len(sys.argv) > 2 else 20000
ROUND = int(sys.argv[4]) if len(sys.argv) > 4 else 1
START = []
if ROUND > 1:
    START = [f"patch {a:x} {b}" for a0 in (0x53e0c, 0x54ebe, 0x553e6) for a, b in zip(range(a0, a0 + 6), "4e 71 4e 71 4e 71".split())]
    START.append(f"patch 5ff9f {0xff & ~(ROUND - 1):02x}")
if len(sys.argv) > 3 and sys.argv[3] != '-':
    START.append(f"patch {0x5073a + 0x17 * (ROUND - 1):x} {sys.argv[3]}")
L = START + ["in 100 ff 3f", "in 106 ff 1f", "in 200 ff 17", "in 206 ff 1f",
     "poke 300 30000 10c13a w 3000"]   # health ($13A,A5) held at max: no hit can kill in one frame
for spec in sys.argv[5:]:
    f0, f1, row, c0, c1 = (int(v) for v in spec.split(':'))
    L += [f"poke {f0} {f1} {0x10de00 + row * 128 + (c & 63) * 2:x} w 1" for c in range(c0, c1 + 1)]
L.append(f"end {END}")
for f in range(400, END, 2):
    p = 0xff & ~0x08              # right
    if f % 40 < 6: p &= ~0x10     # attack
    if f % 90 < 14: p &= ~0x20    # jump
    L.append(f"in {f} {p:02x} 1f")
open(sys.argv[1], "w").write("\n".join(L) + "\n")
