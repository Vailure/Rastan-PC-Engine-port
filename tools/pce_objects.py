"""Build object (enemy, projectile, item) sprite data from arcade captures.

usage: pce_objects.py builddir outdir first_bank

Groups, sequences and captures are listed in object_specs.py. The arcade draws objects
from 16x16 PC090OJ pieces, the PCE's 16x16 sprite cell size, so each unique piece
(image up to flips, arcade palette) becomes one PCE cell. A pose is a list of pieces
(dx, dy, cell, attr) relative to the object's anchor, in the arcade's drawing order.
Cells are not resident: the engine uploads a pose's cells into its object slot's VRAM
buffer when the pose changes (during VBLANK), so any number of kinds can appear.

Outputs (outdir):
  objcells.bin      all cells, 128 bytes each (PCE sprite format), from bank first_bank on
  objects_data.inc  one bank per group (.page 4, mapped at $8000): pose table, poses, anims
  objects.inc       constants: OBJ_CELL_BANK, group banks, pose symbols, palette list
  objpal.bin        sprite palettes, 32 bytes each, in OBJ_PAL_SLOTS order
  objects.png       preview of every pose

Pose: count, then per piece dx, dy, cell low byte, attr;
  attr bits 0-3 PCE sprite palette, 4-5 cell bits 8-9, bit 6 X flip, bit 7 Y flip.
Animation: (pose, frames) pairs, $FF end; pose numbers are per group.
"""
import os
import sys
import numpy as np
from PIL import Image
from arcade_gfx import load_region, decode_packed
from snap import read_snaps, palette_rgb
from object_specs import FILES, GROUPS, POSE_SYMBOLS, GROUP_MAX

ROMDIR = os.environ.get('RASTAN_ROMS', os.path.join(os.path.dirname(__file__), '..', 'roms', 'rastan'))
PAL_SLOTS = [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14]   # 0 Rastan, 8 props, 15 HUD
MAX_PIECES = 12                                           # walker and special slot buffers hold 12 cells
JITTER = 3                                                # poses this close count as one (see below)


def pieces(s, k):
    b = 0x10c2c0 + k * 64
    x, y = s.w(b + 0x1e), s.w(b + 0x22)
    out = []
    for e in range(256):
        if s.owner[e] != k:
            continue
        d0, py, code, px = (int(v) for v in s.spr[e * 4:e * 4 + 4])
        code &= 0x1fff
        if code:
            out.append((d0 & 0xc00f, ((py - y + 256) & 511) - 256, code, ((px - x + 256) & 511) - 256))
    return out


def norm(p):
    mx = min(q[3] for q in p)
    my = min(q[1] for q in p)
    return tuple(sorted((a, dy - my, c, dx - mx) for a, dy, c, dx in p))


def main():
    build, out, first_bank = sys.argv[1], sys.argv[2], int(sys.argv[3], 0)
    os.makedirs(out, exist_ok=True)
    spr = decode_packed(load_region(ROMDIR, 'pc090oj'), 16, 16).astype(int)

    # Snapshots needed, per capture.
    want = {}
    for seqs in GROUPS.values():
        for name, cap, slot, a, b, *rest in seqs:
            want.setdefault(cap, set()).update(range(a, b + 1))
    frames = {}
    for cap, fs in want.items():
        for s in read_snaps(os.path.join(build, FILES[cap])):
            if s.frame in fs:
                if s.owner is None:
                    raise SystemExit(f'{FILES[cap]}: no .own sidecar; rerun sim/sim')
                frames[cap, s.frame] = s

    # Poses and animations per group; arcade palettes (bank-qualified) as used.
    groups = {}
    used_pals = {}          # arcade palette index (with bank) -> 16 RGB colors
    for g, seqs in GROUPS.items():
        poses, ids, anims = [], {}, {}
        for name, cap, slot, a, b, *rest in seqs:
            lo, hi = rest[0] if rest else (0, 0x2000)
            seq = []
            for f in range(a, b + 1):
                s = frames[cap, f]
                p = [q for q in pieces(s, slot) if lo <= q[2] < hi]
                if not p:
                    continue
                bank = (s.sprctrl & 0xe0) >> 1
                p = [(attr, dy, code, dx, bank + (attr & 15)) for attr, dy, code, dx in p]
                for q in p:
                    if q[4] not in used_pals:
                        used_pals[q[4]] = palette_rgb(s.pal)[q[4] * 16:q[4] * 16 + 16]
                k = norm([q[:4] for q in p])
                if k not in ids:
                    # The same cells in the same order, a few px apart (an object
                    # shaking): reuse that pose, so its cells need no new upload.
                    cells_k = [q[:3:2] for q in p]
                    near = next((i for i, o in enumerate(poses) if [q[:3:2] for q in o] == cells_k
                                 and all(abs(a[1] - b[1]) <= JITTER and abs(a[3] - b[3]) <= JITTER
                                         for a, b in zip(o, p))), None)
                    if near is None:
                        near = len(poses)
                        poses.append(p)
                    ids[k] = near
                pid = ids[k]
                if seq and seq[-1][0] == pid:
                    seq[-1][1] += 1
                else:
                    seq.append([pid, 1])
            if not seq:
                raise SystemExit(f'{g}/{name}: nothing captured in {cap} slot {slot} frames {a}-{b}')
            anims[name] = seq
        assert len(poses) < 128, g        # pose_ptr doubles the number in 8 bits
        for i, p in enumerate(poses):
            assert len(p) <= GROUP_MAX.get(g, MAX_PIECES), f'{g} pose {i} has {len(p)} pieces'
        groups[g] = (poses, anims)

    # PCE sprite palettes: identical arcade palettes share a slot.
    to9 = lambda c: tuple(int(round(int(v) * 7 / 255)) for v in c)
    pal9, slot_of = {}, {}
    for ap, cols in sorted(used_pals.items()):
        key = tuple(to9(c) for c in cols)
        if key not in pal9:
            if len(pal9) == len(PAL_SLOTS):
                raise SystemExit('too many sprite palettes')
            pal9[key] = PAL_SLOTS[len(pal9)]
        slot_of[ap] = pal9[key]

    # Cells: unique image up to flips, per PCE palette slot.
    cells, cell_ids, cell_of = [], {}, {}
    for g, (poses, _) in groups.items():
        for p in poses:
            for attr, dy, code, dx, ap in p:
                ps = slot_of[ap]
                if (code, ps) in cell_of:
                    continue
                img = spr[code]
                for fx, fy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                    h = img[:, ::-1] if fx else img
                    h = h[::-1] if fy else h
                    if (h.tobytes(), ps) in cell_ids:
                        cell_of[code, ps] = (cell_ids[h.tobytes(), ps], fx, fy)
                        break
                else:
                    cell_ids[img.tobytes(), ps] = len(cells)
                    cell_of[code, ps] = (len(cells), 0, 0)
                    cells.append(code)
    assert len(cells) <= 1024
    blob = bytearray()
    for code in cells:
        g = spr[code]
        b = bytearray(128)
        for pl in range(4):
            for y in range(16):
                v = 0
                for x in range(16):
                    if (g[y, x] >> pl) & 1:
                        v |= 0x8000 >> x
                b[pl * 32 + y * 2] = v & 0xff
                b[pl * 32 + y * 2 + 1] = v >> 8
        blob += b
    open(f'{out}/objcells.bin', 'wb').write(blob)
    cell_banks = (len(blob) + 8191) // 8192

    vce = bytearray()
    for key, ps in sorted(pal9.items(), key=lambda kv: kv[1]):
        for r, g_, b in key:
            vce += ((g_ << 6) | (r << 3) | b).to_bytes(2, 'little')
    open(f'{out}/objpal.bin', 'wb').write(vce)

    # Data banks: cells first, then one bank per group.
    with open(f'{out}/objects_data.inc', 'w') as f:
        f.write('; Generated by tools/pce_objects.py\n\n\t\t.data\n')
        f.write(f'\t\t.bank\t${first_bank:02X}\n\t\t.page\t3\nobj_cells:\tincbin\t"objcells.bin"\n')
        for gi, (g, (poses, anims)) in enumerate(groups.items()):
            size = 2 * len(poses) + sum(1 + 4 * len(p) for p in poses) + sum(2 * len(s) + 2 for s in anims.values())
            assert size <= 8192, f'group {g} needs {size} bytes'
            f.write(f'\n\t\t.bank\t${first_bank + cell_banks + gi:02X}\n\t\t.page\t4\n')
            f.write(f'grp_{g}_ptab:\n')
            for i in range(len(poses)):
                f.write(f'\t\tdw\tgrp_{g}_p{i}\n')
            for i, p in enumerate(poses):
                f.write(f'grp_{g}_p{i}:\tdb\t{len(p)}\n')
                for attr, dy, code, dx, ap in p:
                    c, fx, fy = cell_of[code, slot_of[ap]]
                    a = (slot_of[ap] | ((c >> 8) << 4) | (0x40 if bool(attr & 0x4000) != bool(fx) else 0)
                         | (0x80 if bool(attr & 0x8000) != bool(fy) else 0))
                    f.write(f'\t\tdb\t{dx & 0xff}, {dy & 0xff}, {c & 0xff}, ${a:02X}\n')
            for name, seq in anims.items():
                f.write(f'anim_{name}:\n')
                for pid, d in seq:
                    f.write(f'\t\tdb\t{pid}, {min(d, 255)}\n')
                f.write('\t\tdb\t$FF, $FF\n')

    with open(f'{out}/objects.inc', 'w') as f:
        f.write('; Generated by tools/pce_objects.py\n')
        f.write(f'OBJ_CELL_BANK\t= ${first_bank:02X}\nOBJ_CELLS\t= {len(cells)}\n')
        f.write(f'OBJ_FREE_BANK\t= ${first_bank + cell_banks + len(groups):02X}\t; first bank after the object data\n')
        for gi, g in enumerate(groups):
            f.write(f'GRP_{g.upper()}_BANK\t= ${first_bank + cell_banks + gi:02X}\n')
        for (g, name, step), sym in POSE_SYMBOLS.items():
            f.write(f'{sym}\t= {groups[g][1][name][step][0]}\n')
        f.write(f'OBJ_PAL_COUNT\t= {len(pal9)}\n')
        f.write('obj_pal_slots:\tdb\t' + ', '.join(str(ps) for ps in sorted(pal9.values())) + '\n')
        f.write('; Arcade palette (bank + color) -> PCE sprite palette:\n')
        for ap, ps in sorted(slot_of.items()):
            f.write(f';   {ap:3d} -> {ps}\n')

    # Preview.
    pv = []
    for g, (poses, _) in groups.items():
        for p in poses:
            img = np.full((96, 96, 3), (40, 40, 60), np.uint8)
            for attr, dy, code, dx, ap in p:
                im = spr[code]
                if attr & 0x4000: im = im[:, ::-1]
                if attr & 0x8000: im = im[::-1, :]
                for y in range(16):
                    for x in range(16):
                        yy, xx = 72 + dy + y, 48 + dx + x
                        if im[y, x] and 0 <= yy < 96 and 0 <= xx < 96:
                            img[yy, xx] = used_pals[ap][im[y, x]]
            img[72, 48] = (255, 0, 0)
            pv.append(img)
    rows = [np.concatenate(pv[i:i + 16] + [np.zeros_like(pv[0])] * (16 - len(pv[i:i + 16])), 1)
            for i in range(0, len(pv), 16)]
    Image.fromarray(np.concatenate(rows, 0)).save(f'{out}/objects.png')
    print(f'{len(cells)} cells in {cell_banks} banks, {len(pal9)} palettes; '
          + '; '.join(f'{g}: {len(p)} poses, {len(a)} anims' for g, (p, a) in groups.items()))


if __name__ == '__main__':
    main()
