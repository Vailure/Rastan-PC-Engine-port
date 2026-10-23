"""pad_sf2.py rom.pce: pad a Street Fighter II mapper HuCard image to 2.5 MB.

The real card is 512 KB fixed + four 512 KB pages; emulators pick the mapper by
the image's size (MAME: exactly 2.5 MB; others: over 1 MB). Fills with $FF.
"""
import sys

SF2_SIZE = 0x280000
with open(sys.argv[1], 'r+b') as f:
    n = f.seek(0, 2)
    if n > SF2_SIZE:
        sys.exit(f'{sys.argv[1]}: {n} bytes, over the SF2 mapper\'s 2.5 MB')
    f.write(b'\xff' * (SF2_SIZE - n))
