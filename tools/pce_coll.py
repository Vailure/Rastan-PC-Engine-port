"""Round collision for the PC Engine, per world square (tools/world.py; RASTAN_ROUND picks
the round).

usage: pce_coll.py maincpu.bin outdir   -> outdir/collision.bin, outdir/coll.inc
"""
import os
import sys
import world


def main():
    rom = open(sys.argv[1], 'rb').read()
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    # ---- collision per world square:
    #   $000  3 x 24 bytes: square id at (square x, square y + 2), $FF none
    #   $100  256 bytes per square id: 4x4 pattern index per block, column-major
    #   COLL_PATTERNS: 16-byte 4x4 patterns
    # Engine byte: the collision code's low nibble (1 solid, 2 rope, 3/4/7 floors,
    # 6 water, 8 deadly, $E a door: $7E), bit 4 for an enemy lane (arcade spawn
    # marker $3A in the high byte, at the height of an enemy's anchor, 16 px above
    # a floor) and bit 7 for a passage a shaft seals behind the camera ($80, $82).
    table = bytearray([0xFF] * 0x100)
    squares = bytearray()
    pats = {}
    for sid, seg in enumerate(world.ORDER):
        sx, sy, _ = world.LAYOUT[seg]
        assert 0 <= sx < 24 and -2 <= sy <= 0
        table[(sy + 2) * 24 + sx] = sid
        coll = world.square_tiles(rom, seg)[2]
        for bc in range(16):
            for br in range(16):
                p = coll[br * 4:br * 4 + 4, bc * 4:bc * 4 + 4]
                k = bytes((int(v) & 0x0f) | (0x10 if int(v) >> 8 == 0x3a else 0) | (0x80 if int(v) & 0x80 else 0)
                          for v in p.flat)
                squares.append(pats.setdefault(k, len(pats)))
    data = table + squares + b''.join(sorted(pats, key=pats.get))
    assert len(data) <= 8192
    open(f'{out}/collision.bin', 'wb').write(data)
    with open(f'{out}/coll.inc', 'w') as f:
        f.write(f'\nCOLL_PATTERNS\t= {len(table) + len(squares)}\t; offset of 4x4 patterns in collision.bin\n')
    print(f'collision: {len(pats)} patterns, {len(data)} bytes')


if __name__ == '__main__':
    main()
