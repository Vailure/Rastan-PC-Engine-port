"""make_bot.py out.txt : simulator input script - coin, start, invincible-ish run right
with periodic attack/jump. Used to capture round 1 palettes from the arcade program."""
import sys
L = ["in 100 ff 3f", "in 106 ff 1f", "in 200 ff 17", "in 206 ff 1f",
     "poke 300 30000 10d2a6 w e",   # candidate health counter (see README)
     "end 20000"]
for f in range(400, 20000, 2):
    p = 0xff & ~0x08              # right
    if f % 40 < 6: p &= ~0x10     # attack
    if f % 90 < 14: p &= ~0x20    # jump
    L.append(f"in {f} {p:02x} 1f")
open(sys.argv[1], "w").write("\n".join(L) + "\n")
