"""Build Rastan's PC Engine sprite data and stage collision from the arcade program.

usage: pce_player.py maincpu.bin actions.snp attract.snp thrusts.snp lizard.snp outdir

Poses are captured from the arcade's own player sprite list ($10D1B2, 8-byte entries
[attr, y, code, x]) at known frames of sim/scripts/actions.txt, relative to the
player anchor ($10BE x, $10C0 y). Each pose becomes a set of 16x16 PCE sprite cells
(right-facing; left-facing uses the PCE's horizontal flip).

Outputs:
  player.bin   pose table (3 bytes/pose: bank offset, addr lo, hi at $6000) + records:
               u8 ncells; ncells * (s8 dx, s8 dy); ncells * 128 bytes cell patterns
  player.inc   pose numbers, animation tables, hitbox constants
  sprpal.bin   16 colors (VCE format) for sprite palette 0
  collision.bin 368*16 block-collision indexes (column-major) + 16-byte 4x4 patterns
  poses.png    preview of the converted poses
"""
import os
import sys
import numpy as np
from PIL import Image
from arcade_gfx import load_region, decode_packed
from snap import read_snaps, palette_rgb
from fgmap import fg_blocks, block_collision

ROMDIR = os.environ.get('RASTAN_ROMS', os.path.join(os.path.dirname(__file__), '..', 'roms', 'rastan'))

# Pose name -> capture frame in actions.snp (see sim/scripts/actions.txt).
POSES = {
    'idle': 500,
    'walk1': 530, 'walk2': 540, 'walk3': 555, 'walk4': 562, 'walk5': 570,
    'crouch': 721,
    'catk1': 741, 'catk2': 742, 'catk3': 743, 'catk4': 744, 'catk5': 750,
    'jump': 805,
    'jatk1': 891, 'jatk2': 892, 'jatk3': 893, 'jatk4': 894, 'jatk5': 896,
    'atk1': 1061, 'atk2': 1062, 'atk3': 1063, 'atk4': 1064, 'atk5': 1066,
}
# Poses captured from the attract demo (it climbs a rope in segment 3).
POSES_ATTRACT = {'climb1': 4455, 'climb2': 4459, 'climb3': 4463, 'climb4': 4493}
# Air thrusts from sim/scripts/thrusts.txt: DOWN+attack in a jump (two
# transition poses, then the sword-down pose held until landing), and
# UP+attack in a high jump.
POSES_THRUSTS = {'dthr1': 532, 'dthr2': 536, 'dthr3': 540, 'uthr': 731}
# Being hit by a lizardman (sim/scripts/lizard.txt, passive Rastan): 3 poses, 23 frames.
POSES_HURT = {'hurt1': 667, 'hurt2': 674, 'hurt3': 682}

# Animations: (pose, frames) lists measured from the arcade (see README).
# A duration of 0 holds the pose forever.
ANIMS = {
    'idle': [('idle', 0)],
    'walk': [('walk1', 8), ('walk2', 8), ('walk1', 8), ('walk3', 8),
             ('walk4', 8), ('walk5', 8), ('walk4', 8), ('walk3', 8)],
    'crouch': [('crouch', 0)],
    'jump': [('jump', 0)],
    'attack': [('atk1', 1), ('atk2', 1), ('atk3', 1), ('atk4', 2), ('atk5', 8),
               ('atk4', 2), ('atk3', 2), ('atk2', 2), ('atk1', 2)],
    'catk': [('catk1', 1), ('catk2', 1), ('catk3', 1), ('catk4', 2), ('catk5', 8),
             ('catk4', 2), ('catk3', 2), ('catk2', 2), ('catk1', 2)],
    'climb': [('climb1', 3), ('climb2', 3), ('climb3', 3), ('climb4', 3)],
    'dthrust': [('dthr1', 4), ('dthr2', 4), ('dthr3', 0)],
    'uthrust': [('uthr', 8)],
    'hurt': [('hurt1', 7), ('hurt2', 8), ('hurt3', 8)],
    'jatk': [('jatk1', 1), ('jatk2', 1), ('jatk3', 1), ('jatk4', 2), ('jatk5', 10),
             ('jatk4', 2), ('jatk3', 2), ('jatk2', 2), ('jatk1', 2)],
}

# Arcade jump tables (index 0 is a $FF sentinel): (dx, up) per frame.
JUMP_TABLES = {'jump_low': 0x5B548, 'jump_high': 0x5B516, 'jump_low_fwd': 0x5B5A2, 'jump_high_fwd': 0x5B570}


def capture(snapf, poses):
    want = set(poses.values())
    out = {}
    for s in read_snaps(snapf):
        if s.frame in want:
            px, py = s.w(0x10d0be), s.w(0x10d0c0)
            pieces = []
            for i in range(15):
                b = 0x10d1b2 + i * 8
                attr, y, code, x = (s.w(b + k * 2) for k in range(4))
                if code:
                    pieces.append((attr, (y & 0x1ff) - py, code, (x & 0x1ff) - px))
            out[s.frame] = (pieces, palette_rgb(s.pal), (s.sprctrl & 0xe0) >> 1)
    return out


def to9(rgb):
    return tuple(int(round(c * 7 / 255)) for c in rgb)


def main():
    rom = open(sys.argv[1], 'rb').read()
    snapf, attractf, thrustf, lizardf, out = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
    os.makedirs(out, exist_ok=True)
    spr = decode_packed(load_region(ROMDIR, 'pc090oj'), 16, 16).astype(int)
    act = capture(snapf, POSES)
    att = capture(attractf, POSES_ATTRACT)
    caps = {n: act[f] for n, f in POSES.items()}
    caps.update({n: att[f] for n, f in POSES_ATTRACT.items()})
    thr = capture(thrustf, POSES_THRUSTS)
    caps.update({n: thr[f] for n, f in POSES_THRUSTS.items()})
    hurt = capture(lizardf, POSES_HURT)
    caps.update({n: hurt[f] for n, f in POSES_HURT.items()})
    all_poses = list(POSES) + list(POSES_ATTRACT) + list(POSES_THRUSTS) + list(POSES_HURT)

    # Compose each pose into an RGB image around the anchor (anchor at (64, 96)).
    AX, AY, W, H = 64, 96, 128, 128
    imgs = {}
    for name in all_poses:
        pieces, pal, colbank = caps[name]
        img = np.full((H, W, 3), -1, int)
        for attr, dy, code, dx in pieces:
            g = spr[code]
            if attr & 0x4000: g = g[:, ::-1]
            if attr & 0x8000: g = g[::-1, :]
            col = ((attr & 0xf) | colbank) * 16
            for yy in range(16):
                for xx in range(16):
                    if g[yy, xx]:
                        img[AY + dy + yy, AX + dx + xx] = pal[col + g[yy, xx]]
        imgs[name] = img

    # Shared 15-color sprite palette (9-bit), merging nearest colors if needed.
    colors = {}
    for img in imgs.values():
        m = img[..., 0] >= 0
        for c in img[m]:
            k = to9(c)
            colors[k] = colors.get(k, 0) + 1
    cl = sorted(colors, key=lambda k: -colors[k])
    pal9 = cl[:15]
    if len(cl) > 15:
        print(f'{len(cl)} sprite colors, keeping the 15 most used and mapping the rest')
    remap = {c: min(range(len(pal9)), key=lambda i: sum((a - b) ** 2 for a, b in zip(c, pal9[i]))) + 1 for c in cl}

    # Cells: 16x16 grid aligned to the anchor; keep non-empty cells.
    blob_records = []
    preview = []
    for name in all_poses:
        img = imgs[name]
        idx = np.zeros((H, W), np.uint8)
        m = img[..., 0] >= 0
        for y, x in zip(*np.nonzero(m)):
            idx[y, x] = remap[to9(img[y, x])]
        cells = []
        for cy in range(0, H, 16):
            for cx in range(0, W, 16):
                c = idx[cy:cy + 16, cx:cx + 16]
                if c.any():
                    cells.append((cx - AX, cy - AY, c))
        assert len(cells) <= 24, (name, len(cells))
        rec = bytearray([len(cells)])
        for dx, dy, _ in cells:
            rec += bytes([dx & 0xff, dy & 0xff])
        for _, _, c in cells:
            b = bytearray(128)       # 4 planes x 16 rows x 16-bit words (little-endian words)
            for p in range(4):
                for y in range(16):
                    v = 0
                    for x in range(16):
                        if (c[y, x] >> p) & 1:
                            v |= 0x8000 >> x
                    b[p * 32 + y * 2] = v & 0xff
                    b[p * 32 + y * 2 + 1] = v >> 8
            rec += b
        blob_records.append(rec)
        pv = np.array([[0, 0, 0]] + [list(c) for c in pal9], int)[idx] * 255 // 7
        pv[~m] = (40, 40, 60)
        preview.append(pv[32:128, 24:120])
    table_size = 3 * len(blob_records)
    blob, offs = bytearray(), []
    for r in blob_records:
        offs.append(table_size + len(blob))
        blob += r
    table = bytearray()
    for o in offs:
        a = 0x6000 + o % 8192
        table += bytes([o // 8192, a & 0xff, a >> 8])
    open(f'{out}/player.bin', 'wb').write(table + blob)

    vce = bytearray()
    for r, g, b in [(0, 0, 0)] + list(pal9) + [(0, 0, 0)] * (15 - len(pal9)):
        vce += ((g << 6) | (r << 3) | b).to_bytes(2, 'little')
    open(f'{out}/sprpal.bin', 'wb').write(vce)

    # Jump tables (skip the sentinel), terminated by $FF.
    names = all_poses
    with open(f'{out}/player.inc', 'w') as f:
        f.write('; Generated by tools/pce_player.py\n')
        for i, n in enumerate(names):
            f.write(f'POSE_{n.upper()}\t= {i}\n')
        f.write(f'POSE_COUNT\t= {len(names)}\n\n')
        for an, frames in ANIMS.items():
            f.write(f'anim_{an}:\n')
            for p, d in frames:
                f.write(f'\t\tdb\tPOSE_{p.upper()}, {d}\n')
            f.write('\t\tdb\t$FF, $FF\t\t; end\n')
        for tn, a in JUMP_TABLES.items():
            f.write(f'{tn}:\t\t\t\t; (dx, up) per frame, from arcade ${a:05X}\n')
            i = a + 2
            vals = []
            while rom[i] != 0xff:
                vals.append(f'{rom[i]},{rom[i + 1]}')
                i += 2
            f.write('\t\tdb\t' + ', '.join(vals) + '\n')
            f.write(f'{tn.upper()}_LEN\t= {len(vals)}\n')
    Image.fromarray(np.concatenate(preview, 1).astype(np.uint8)).save(f'{out}/poses.png')
    print(f'{len(names)} poses, {sum(r[0] for r in blob_records)} cells, player.bin {len(table) + len(blob)} bytes, '
          f'{len(pal9)} sprite colors')

    # ---- collision for round 1 (segments 0..$16 = 368 block columns)
    attr, blk = fg_blocks(rom)
    pats, colmap = {}, bytearray()
    for c in range(368):
        for r in range(16):
            p = block_collision(rom, int(blk[r, c]))
            k = bytes(int(v) & 0xff for v in p.flat)
            colmap.append(pats.setdefault(k, len(pats)))
    data = colmap + b''.join(sorted(pats, key=pats.get))
    assert len(data) <= 8192
    open(f'{out}/collision.bin', 'wb').write(data)
    with open(f'{out}/player.inc', 'a') as f:
        f.write(f'\nCOLL_PATTERNS\t= {len(colmap)}\t; offset of 4x4 patterns in collision.bin\n')
    print(f'collision: {len(pats)} patterns, {len(data)} bytes')


if __name__ == '__main__':
    main()
