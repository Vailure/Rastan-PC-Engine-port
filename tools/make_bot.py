"""make_bot.py out.txt [end [start]] : simulator input script - coin, start, invincible-ish run
right with periodic attack/jump, from the round start or (start, hex) the checkpoint that
the arcade's restart table byte $5073A names. Used to capture round 1 palettes from the
arcade program."""
import sys
END = int(sys.argv[2]) if len(sys.argv) > 2 else 20000
START = [f"patch 5073a {sys.argv[3]}"] if len(sys.argv) > 3 else []
L = START + ["in 100 ff 3f", "in 106 ff 1f", "in 200 ff 17", "in 206 ff 1f",
     "poke 300 30000 10c13a w 3000",   # health ($13A,A5) held at max: no hit can kill in one frame
     f"end {END}"]
for f in range(400, END, 2):
    p = 0xff & ~0x08              # right
    if f % 40 < 6: p &= ~0x10     # attack
    if f % 90 < 14: p &= ~0x20    # jump
    L.append(f"in {f} {p:02x} 1f")
open(sys.argv[1], "w").write("\n".join(L) + "\n")
