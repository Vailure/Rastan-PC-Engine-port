"""Read sim snapshots and render arcade frames (PC080SN x2 + PC090OJ) like MAME."""
import gzip
import struct
import numpy as np
from arcade_gfx import decode_packed

REC = 32 + 0x10000 + 0x1000 + 0x800 + 0x4000


class Snap:
    __slots__ = ("frame", "p1", "sys", "scry", "scrx", "vctrl", "sprctrl", "vram", "pal", "spr", "wram", "owner")

    def words(self, buf):
        return np.frombuffer(buf, dtype=">u2")

    def w(self, addr):  # work RAM word at absolute 68k address
        o = addr - 0x10c000
        return (self.wram[o] << 8) | self.wram[o + 1]


def read_snaps(path):
    import os
    own = gzip.open(path + '.own', 'rb') if os.path.exists(path + '.own') else None
    with gzip.open(path, "rb") as f:
        while True:
            b = f.read(REC)
            if len(b) < REC:
                return
            s = Snap()
            assert b[:4] == b"RSNP"
            s.frame = struct.unpack(">I", b[4:8])[0]
            s.p1, s.sys = b[8], b[9]
            r = struct.unpack(">7H", b[10:24])
            s.scry, s.scrx, s.vctrl, s.sprctrl = r[0:2], r[2:4], r[4:6], r[6]
            o = 32
            s.vram = np.frombuffer(b[o:o + 0x10000], ">u2"); o += 0x10000
            s.pal = np.frombuffer(b[o:o + 0x1000], ">u2"); o += 0x1000
            s.spr = np.frombuffer(b[o:o + 0x800], ">u2"); o += 0x800
            s.wram = b[o:o + 0x4000]
            s.owner = own.read(256) if own else None    # sprite entry -> object slot ($FF other, $FE unused)
            yield s


def palette_rgb(palwords):
    p = palwords.astype(np.uint32)
    r, g, b = p & 31, (p >> 5) & 31, (p >> 10) & 31
    rgb = np.stack([r, g, b], 1)
    return ((rgb << 3) | (rgb >> 2)).astype(np.uint8)


class Renderer:
    def __init__(self, tiles_region, sprites_region):
        self.tiles = decode_packed(tiles_region, 8, 8)
        self.sprites = decode_packed(sprites_region, 16, 16)

    def layer_map(self, s, n):
        """Return (code, color, flipx, flipy) arrays [64,64] for layer n."""
        words = s.vram[n * 0x4000:n * 0x4000 + 0x2000].reshape(64, 64, 2)
        attr, code = words[..., 0], words[..., 1] & 0x3fff
        return code, attr & 0x1ff, (attr >> 14) & 1, (attr >> 15) & 1

    def layer_pixels(self, s, n):
        """512x512 index image (palette index, -1 transparent) for layer n."""
        code, color, fx, fy = self.layer_map(s, n)
        t = self.tiles[code % len(self.tiles)]           # 64,64,8,8
        t = np.where(fx[..., None, None] == 1, t[..., :, ::-1], t)
        t = np.where(fy[..., None, None] == 1, t[..., ::-1, :], t)
        idx = color[..., None, None].astype(np.int32) * 16 + t
        idx = np.where(t == 0, -1, idx)
        return idx.transpose(0, 2, 1, 3).reshape(512, 512)

    def render(self, s, layers=(0, 1), sprites=True):
        pal = palette_rgb(s.pal)
        H, W = 256, 320
        out = np.zeros((H, W), np.int32)
        sy = np.arange(H)[:, None]
        sx = np.arange(W)[None, :]
        for n in layers:
            lp = self.layer_pixels(s, n)
            ty = (sy - s.scry[n]) & 511
            tx = (sx + 16 - s.scrx[n]) & 511
            px = lp[ty, tx]
            if n == 0:  # BG drawn opaque: pen 0 shows color*16+0
                code, color, _, _ = self.layer_map(s, 0)
                opaque = color.repeat(8, 0).repeat(8, 1)[ty, tx] * 16
                out = np.where(px < 0, opaque, px)
            else:
                out = np.where(px >= 0, px, out)
        if sprites:
            colbank = (s.sprctrl & 0xe0) >> 1
            for i in range(0, 0x400, 4):
                d0, y, code, x = (int(v) for v in s.spr[i:i + 4])
                code &= 0x1fff
                x &= 0x1ff; y &= 0x1ff
                if x > 0x140: x -= 0x200
                if y > 0x140: y -= 0x200
                fy, fx = (d0 >> 15) & 1, (d0 >> 14) & 1
                color = (d0 & 0xf) | colbank
                g = self.sprites[code % len(self.sprites)]
                if fx: g = g[:, ::-1]
                if fy: g = g[::-1, :]
                x0, y0 = x, y
                xs0, ys0 = max(0, -x0), max(0, -y0)
                xs1, ys1 = min(16, W - x0), min(16, H - y0)
                if xs0 >= xs1 or ys0 >= ys1:
                    continue
                gg = g[ys0:ys1, xs0:xs1]
                region = out[y0 + ys0:y0 + ys1, x0 + xs0:x0 + xs1]
                region[:] = np.where(gg != 0, color * 16 + gg.astype(np.int32), region)
        img = pal[out]
        return img[8:248]  # visible area 320x240
