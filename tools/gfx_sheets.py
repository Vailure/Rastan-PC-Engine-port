"""Render grayscale sheets of all arcade tiles/sprites to verify decoding."""
import sys
import numpy as np
from PIL import Image
from arcade_gfx import load_region, decode_packed


def sheet(tiles, cols, scale=1):
    n, h, w = tiles.shape
    rows = (n + cols - 1) // cols
    img = np.zeros((rows * h, cols * w), np.uint8)
    for i, t in enumerate(tiles):
        r, c = divmod(i, cols)
        img[r * h:(r + 1) * h, c * w:(c + 1) * w] = t
    im = Image.fromarray((img * 17).astype(np.uint8))
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST) if scale > 1 else im


if __name__ == "__main__":
    romdir, outdir = sys.argv[1], sys.argv[2]
    tiles = decode_packed(load_region(romdir, "pc080sn"), 8, 8)
    spr = decode_packed(load_region(romdir, "pc090oj"), 16, 16)
    print("tiles", tiles.shape, "sprites", spr.shape)
    print("blank tiles", int((tiles.reshape(len(tiles), -1).max(1) == 0).sum()),
          "blank sprites", int((spr.reshape(len(spr), -1).max(1) == 0).sum()))
    # tiles: 16384 -> 4 sheets of 4096 (64 cols)
    for i in range(4):
        sheet(tiles[i * 4096:(i + 1) * 4096], 64).save(f"{outdir}/tiles_{i}.png")
    for i in range(2):
        sheet(spr[i * 1024:(i + 1) * 1024], 32).save(f"{outdir}/sprites_{i}.png")
