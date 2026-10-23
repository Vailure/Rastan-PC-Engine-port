"""Build Rastan's PC Engine sprite data and stage collision from the arcade program.

usage: pce_player.py maincpu.bin actions.snp attract.snp thrusts.snp lizard.snp waterfall.snp outdir

Poses are captured from the arcade's own player sprite list ($10D1B2, 8-byte entries
[attr, y, code, x]) at known frames of sim/scripts/actions.txt, relative to the
player anchor ($10BE x, $10C0 y). Each pose becomes a set of 16x16 PCE sprite cells
(right-facing; left-facing uses the PCE's horizontal flip).

Outputs:
  player.bin   pose table (3 bytes/pose: bank offset, addr lo, hi at $6000) + records:
               u8 ncells; ncells * (s8 dx, s8 dy); ncells * 128 bytes cell patterns
  player.inc   pose numbers, animation tables, hitbox constants
  sprpal.bin   16 colors (VCE format) for sprite palette 0
  collision.bin square table, per-square block-collision indexes, 16-byte 4x4 patterns
  poses.png    preview of the converted poses
"""
import os
import sys
import numpy as np
from PIL import Image
from arcade_gfx import load_region, decode_packed
from snap import read_snaps, palette_rgb
from fgmap import fg_blocks, block_collision
from player_frames import frames as part_frames, PARTS

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
# Standing UP+attack, a swing over his head (sim/scripts/upatk.txt): three poses,
# the arcade's bodies 12-14, held 4, 4, 8, 2, 4 frames.
POSES_UATK = {'uatk1': 522, 'uatk2': 526, 'uatk3': 530}
# Being hit by a lizardman (sim/scripts/lizard.txt, passive Rastan): 3 poses, 23 frames.
POSES_HURT = {'hurt1': 667, 'hurt2': 674, 'hurt3': 682}
# Dying (arcade state 8), from the bot's death on the first waterfall's lip: 9 poses, 57 frames.
# Hanging from a swinging vine (bot1 run, build/vine.snp): one pose, the arcade's body 15, legs 13.
POSES_SWING = {'swing': 11100}
POSES_DEATH = {'die1': 1658, 'die2': 1662, 'die3': 1666, 'die4': 1674, 'die5': 1682,
               'die6': 1690, 'die7': 1698, 'die8': 1706, 'die9': 1714}

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
    'uattack': [('uatk1', 4), ('uatk2', 4), ('uatk3', 8), ('uatk2', 2), ('uatk1', 4)],
    'hurt': [('hurt1', 7), ('hurt2', 8), ('hurt3', 8)],
    'death': [('die1', 4), ('die2', 4), ('die3', 8), ('die4', 8), ('die5', 8), ('die6', 8),
              ('die7', 8), ('die8', 8), ('die9', 1)],
    'swing': [('swing', 0)],
    'jatk': [('jatk1', 1), ('jatk2', 1), ('jatk3', 1), ('jatk4', 2), ('jatk5', 10),
             ('jatk4', 2), ('jatk3', 2), ('jatk2', 2), ('jatk1', 2)],
}

# Arcade jump tables (index 0 is a $FF sentinel): (dx, up) per frame.
JUMP_TABLES = {'jump_low': 0x5B548, 'jump_high': 0x5B516, 'jump_low_fwd': 0x5B5A2, 'jump_high_fwd': 0x5B570}


def capture(snapf, poses):
    """frame -> (body pieces, palette, color bank, weapon frame, weapon mirrored).

    The first 4 sprite entries are the weapon (frame $10D244 of the weapon's part table,
    see player_frames.py); they are left out of the pose and drawn from WEAPONS instead.
    Weapon frame -1: no weapon drawn in this pose."""
    want = set(poses.values())
    out = {}
    for s in read_snaps(snapf):
        if s.frame in want:
            px, py = s.w(0x10d0be), s.w(0x10d0c0)
            pieces, weapon = [], []
            for i in range(15):
                b = 0x10d1b2 + i * 8
                attr, y, code, x = (s.w(b + k * 2) for k in range(4))
                if code:
                    (weapon if i < 4 else pieces).append((attr, (y & 0x1ff) - py, code, (x & 0x1ff) - px))
            fi, mirror = -1, 0
            if weapon:
                fi = s.w(0x10d244)
                mirror = weapon[0][0] & 0x4000 ^ WTAB[1][fi][0][3] & 0x4000
                assert sorted(weapon) == sorted(weapon_pieces(1, fi, mirror)), (snapf, s.frame)
            out[s.frame] = (pieces, palette_rgb(s.pal), (s.sprctrl & 0xe0) >> 1, fi, mirror)
    return out


def weapon_pieces(w, fi, mirror, flame=0):
    """Weapon w's sprite pieces (attr, dy, code, dx) for weapon frame fi, relative to the anchor."""
    out = []
    for code, dx, dy, attr in WTAB[w][fi]:
        if mirror:
            dx, attr = -dx - 16, attr ^ 0x4000
        out.append((attr, dy + 1, code + flame, dx))
    return out


# Weapons ($10D2FA): 1 sword, 2 axe, 3 morning star, 4 fire sword. The fire sword's
# flame cycles its cells by +0/+2/+4/+6, 2 frames each.
WEAPON_PARTS = {1: 'sword', 2: 'weapon2', 3: 'weapon3', 4: 'weapon4'}
FLAMES = 4
WTAB = {}
BODY_CELLS = 20                 # of a 24-cell pose buffer; the weapon uses the last 4


def to9(rgb):
    return tuple(int(round(c * 7 / 255)) for c in rgb)


def main():
    rom = open(sys.argv[1], 'rb').read()
    snapf, attractf, thrustf, lizardf, waterf, vinef, uatkf, out = sys.argv[2:10]
    os.makedirs(out, exist_ok=True)
    for w, n in WEAPON_PARTS.items():
        WTAB[w] = part_frames(rom, PARTS[n])
    spr = decode_packed(load_region(ROMDIR, 'pc090oj'), 16, 16).astype(int)
    act = capture(snapf, POSES)
    att = capture(attractf, POSES_ATTRACT)
    caps = {n: act[f] for n, f in POSES.items()}
    caps.update({n: att[f] for n, f in POSES_ATTRACT.items()})
    thr = capture(thrustf, POSES_THRUSTS)
    caps.update({n: thr[f] for n, f in POSES_THRUSTS.items()})
    hurt = capture(lizardf, POSES_HURT)
    caps.update({n: hurt[f] for n, f in POSES_HURT.items()})
    die = capture(waterf, POSES_DEATH)
    caps.update({n: die[f] for n, f in POSES_DEATH.items()})
    sw = capture(vinef, POSES_SWING)
    caps.update({n: sw[f] for n, f in POSES_SWING.items()})
    ua = capture(uatkf, POSES_UATK)
    caps.update({n: ua[f] for n, f in POSES_UATK.items()})
    all_poses = (list(POSES) + list(POSES_ATTRACT) + list(POSES_THRUSTS) + list(POSES_HURT) + list(POSES_DEATH)
                 + list(POSES_SWING) + list(POSES_UATK))

    # Compose each pose into an RGB image around the anchor (anchor at (64, 96)).
    AX, AY, W, H = 96, 112, 192, 176    # canvas around the anchor (death sparkles spread wide)
    imgs = {}
    for name in all_poses:
        pieces, pal, colbank = caps[name][:3]
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

    # Weapon cells: every piece of every weapon frame (all flame steps for the fire sword).
    pieces0, pal0, bank0 = caps['idle'][:3]
    wcodes = []
    for w in WEAPON_PARTS:
        for fr in WTAB[w]:
            for code, dx, dy, attr in fr:
                for k in range(FLAMES if w == 4 else 1):
                    if (code + 2 * k, attr & 15) not in wcodes:
                        wcodes.append((code + 2 * k, attr & 15))
    wimgs = {}
    for code, c in wcodes:
        g = spr[code]
        img = np.full((16, 16, 3), -1, int)
        for yy in range(16):
            for xx in range(16):
                if g[yy, xx]:
                    img[yy, xx] = pal0[((c | bank0) * 16) + g[yy, xx]]
        wimgs[code, c] = img

    # Shared 15-color sprite palette (9-bit), merging nearest colors if needed.
    colors = {}
    for img in list(imgs.values()) + list(wimgs.values()):
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
        assert len(cells) <= BODY_CELLS, (name, len(cells))
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
        preview.append(pv[48:144, 56:152])
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

    # Weapon cells (weapons.bin, 128 bytes each) and weapon_tab.inc: per variant
    # (1-3: weapons 1-3, 4-7: fire sword flame steps 0-3), a word per pose pointing at
    # count, then per piece dx, dy, cell, SATB attribute high byte ($08 X flip, $80 Y flip).
    wblob = bytearray()
    for key in wcodes:
        img = wimgs[key]
        idx = np.zeros((16, 16), np.uint8)
        for y, x in zip(*np.nonzero(img[..., 0] >= 0)):
            idx[y, x] = remap[to9(img[y, x])]
        b = bytearray(128)
        for p in range(4):
            for y in range(16):
                v = 0
                for x in range(16):
                    if (idx[y, x] >> p) & 1:
                        v |= 0x8000 >> x
                b[p * 32 + y * 2] = v & 0xff
                b[p * 32 + y * 2 + 1] = v >> 8
        wblob += b
    assert len(wcodes) < 256
    open(f'{out}/weapons.bin', 'wb').write(wblob)
    lists, labels = {}, []
    with open(f'{out}/weapon_tab.inc', 'w') as f:
        f.write('; Generated by tools/pce_player.py\nweapon_vtab:\n')
        variants = [(1, 0), (2, 0), (3, 0)] + [(4, k) for k in range(FLAMES)]
        for v in range(len(variants)):
            f.write(f'\t\tdw\twv_{v}\n')
        body = []
        for v, (w, k) in enumerate(variants):
            f.write(f'wv_{v}:\n')
            for name in all_poses:
                fi, mirror = caps[name][3:5]
                pcs = weapon_pieces(w, fi, mirror, 2 * k) if fi >= 0 else []
                rec = [len(pcs)]
                for attr, dy, code, dx in pcs:
                    rec += [dx & 0xff, dy & 0xff, wcodes.index((code, attr & 15)),
                            (0x08 if attr & 0x4000 else 0) | (0x80 if attr & 0x8000 else 0)]
                rec = tuple(rec)
                if rec not in lists:
                    lists[rec] = f'wl_{len(lists)}'
                    body.append(f'{lists[rec]}:\tdb\t' + ', '.join(str(x) for x in rec) + '\n')
                f.write(f'\t\tdw\t{lists[rec]}\t; {name}\n')
        f.writelines(body)
    print(f'weapons: {len(wcodes)} cells, {len(lists)} piece lists')

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

    # ---- collision for round 1, per world square (tools/world.py):
    #   $000  3 x 24 bytes: square id at (square x, square y + 2), $FF none
    #   $100  256 bytes per square id: 4x4 pattern index per block, column-major
    #   COLL_PATTERNS: 16-byte 4x4 patterns
    # Engine byte: the collision code's low nibble (1 solid, 2 rope, 3/4/7 floors,
    # 6 water, 8 deadly, $E a door: $7E), bit 4 for an enemy lane (arcade spawn
    # marker $3A in the high byte, at the height of an enemy's anchor, 16 px above
    # a floor) and bit 7 for a passage a shaft seals behind the camera ($80, $82).
    import world
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
    with open(f'{out}/player.inc', 'a') as f:
        f.write(f'\nCOLL_PATTERNS\t= {len(table) + len(squares)}\t; offset of 4x4 patterns in collision.bin\n')
    print(f'collision: {len(pats)} patterns, {len(data)} bytes')


if __name__ == '__main__':
    main()
