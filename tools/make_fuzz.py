"""make_fuzz.py out.txt seed frames : coin/start then random pad input held for random spans,
recording every player-update call (for lockstep tests)."""
import random
import sys
out, seed, n = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
r = random.Random(seed)
L = ["in 100 ff 3f", "in 106 ff 1f", "in 200 ff 17", "in 206 ff 1f", f"end {n}"]
f = 300
while f < n:
    p = 0xff
    d = r.choice([0, 0x08, 0x08, 0x04, 0x01, 0x02, 0x09, 0x05, 0x0a, 0x06])   # dirs (active low)
    p &= ~d
    if r.random() < 0.35: p &= ~0x20      # jump
    if r.random() < 0.35: p &= ~0x10      # attack
    L.append(f"in {f} {p & 0xff:02x} 1f")
    f += r.choice([2, 4, 8, 15, 30, 60])
open(out, "w").write("\n".join(L) + "\n")
