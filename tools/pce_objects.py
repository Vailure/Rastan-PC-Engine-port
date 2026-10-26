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
from object_specs import MOBJ_CELLS, B64_GROUPS, BANK64_SNAP, ROUND_PAL_SNAPS, GROUP_ROUNDS, NUM_ROUNDS, FIXED_PALS, GROUP_BANK, CELL_SYMBOLS, FILES, GROUPS, POSE_SYMBOLS, GROUP_MAX, PATHS
import census_all

ROMDIR = os.environ.get('RASTAN_ROMS', os.path.join(os.path.dirname(__file__), '..', 'roms', 'rastan'))
PAL_SLOTS = [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 14, 13]   # 0 Rastan, 8 props, 13-14 floor spears, 15 HUD
LATE_SLOTS = (13, 14)    # round 1's floor spears' (enemies_load loads theirs after): not for round 1's colours
MAX_PIECES = 11                                           # walker slot buffers hold 11 cells
FIXED = 1000                                              # palette keys of FIXED_PALS' slots
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
        if 272 <= (py & 0x1ff) < 480:      # parked off-screen (unused piece)
            continue
        if code:
            out.append((d0 & 0xc00f, ((py - y + 256) & 511) - 256, code, ((px - x + 256) & 511) - 256))
    return out


def norm(p):
    if not p:
        return ()
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
    for rnd, lst in MOBJ_CELLS.items():
        for sym, cap, fr, code in lst:
            want.setdefault(cap, set()).add(fr)
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
    ap_rounds = {}          # arcade palette index -> the rounds whose objects use it
    for g, seqs in GROUPS.items():
        poses, ids, anims = [], {}, {}
        for name, cap, slot, a, b, *rest in seqs:
            # Options: a cell range (lo, hi), or {'cells': (lo, hi), 'index': (i0, i1)}
            # to keep pieces i0..i1-1 in the arcade's order (big objects split in two).
            opt = rest[0] if rest else {}
            if isinstance(opt, tuple):
                opt = {'cells': opt}
            lo, hi = opt.get('cells', (0, 0x2000))
            i0, i1 = opt.get('index', (0, 999))
            seq = []
            for f in range(a, b + 1):
                s = frames[cap, f]
                p = [q for q in pieces(s, slot) if lo <= q[2] < hi][i0:i1]
                if not p and 'index' not in opt:     # (a split part may be empty: keep its timing)
                    continue
                bank = GROUP_BANK.get(g, (s.sprctrl & 0xe0) >> 1)
                fixed = FIXED_PALS.get(g, {})
                p = [(attr, dy, code, dx, FIXED + fixed[attr & 15][0] if attr & 15 in fixed else bank + (attr & 15))
                     for attr, dy, code, dx in p]
                for q in p:
                    if q[4] < FIXED and q[4] not in used_pals:
                        used_pals[q[4]] = palette_rgb(s.pal)[q[4] * 16:q[4] * 16 + 16]
                    if q[4] < FIXED:
                        ap_rounds.setdefault(q[4], set()).update(GROUP_ROUNDS.get(g, range(1, NUM_ROUNDS + 1)))
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

    # Map objects' cells (MOBJ_CELLS): resident in VRAM per round (src/mobj.asm), not in
    # objcells.bin; their arcade palettes take PCE slots like the groups' do.
    mobj = {}                                # round -> [(sym, code, ap)]
    for rnd, lst in MOBJ_CELLS.items():
        for sym, cap, fr, code in lst:
            s = frames[cap, fr]
            e = next((e for e in range(256) if int(s.spr[e * 4 + 2]) & 0x1fff == code), None)
            if e is None:
                raise SystemExit(f'MOBJ_CELLS {sym}: cell {code:#x} not drawn in {cap} frame {fr}')
            ap = ((s.sprctrl & 0xe0) >> 1) + (int(s.spr[e * 4]) & 15)
            if ap not in used_pals:
                used_pals[ap] = palette_rgb(s.pal)[ap * 16:ap * 16 + 16]
            ap_rounds.setdefault(ap, set()).add(rnd)
            mobj.setdefault(rnd, []).append((sym, code, ap))

    # Scripted flight paths: world position per frame (census_all), as runs of
    # equal per-frame steps.
    paths = {}
    for pname, (pg, cap, slot, a, b) in PATHS.items():
        tracks = census_all.run([os.path.join(build, FILES[cap])])['tracks']
        t = next(t for t in tracks if t['slot'] == slot and t['frames'][0][0] <= a <= t['frames'][-1][0])
        pos = [(f[1], f[2]) for f in t['frames'] if a <= f[0] <= b]
        runs = []
        for (x0, y0), (x1, y1) in zip(pos, pos[1:]):
            d = (x1 - x0, ((y1 - y0 + 256) & 511) - 256)
            assert -128 <= d[0] < 128 and -128 <= d[1] < 128, (pname, d)
            if runs and tuple(runs[-1][:2]) == d and runs[-1][2] < 255:
                runs[-1][2] += 1
            else:
                runs.append([d[0], d[1], 1])
        paths[pname] = runs
        print(f'path {pname}: {len(pos)} frames, {len(runs)} runs')

    # PCE sprite palettes: identical arcade palettes share a slot.
    to9 = lambda c: tuple(int(round(int(v) * 7 / 255)) for v in c)
    # A slot holds a palette in colour bank 48 and (objpal_b64.bin) in bank 64: arcade
    # palettes share one only if both their colours agree. Bank 64 changes only the
    # palettes of the groups that can be seen after a restart at checkpoint 4 or 5
    # (B64_GROUPS); the others keep theirs, so that more of them can share a slot.
    cap, fr = BANK64_SNAP
    ref = next(s for s in read_snaps(os.path.join(build, FILES[cap])) if s.frame == fr)
    rgb64 = palette_rgb(ref.pal)
    late = {q[4] for g in B64_GROUPS for p in groups[g][0] for q in p}
    pal9, slot_of = {}, {}
    for g, fixed in FIXED_PALS.items():          # (slots of their own, loaded by the engine)
        for col, (ps, cap, fr, ap) in fixed.items():
            slot_of[FIXED + ps] = ps
            src = palette_rgb(next(s for s in read_snaps(os.path.join(build, FILES[cap])) if s.frame == fr).pal)
            v = bytearray()
            for r, g_, b in (tuple(int(round(int(c) * 7 / 255)) for c in src[ap * 16 + i]) for i in range(16)):
                v += ((g_ << 6) | (r << 3) | b).to_bytes(2, 'little')
            open(f'{out}/{g}_pal{ps}.bin', 'wb').write(v)
            used_pals[FIXED + ps] = src[ap * 16:ap * 16 + 16]    # (for the preview)
    # Slots: an arcade palette shares one with others whose colours agree, or which no
    # round uses together with it (each round loads its own colours into the slots).
    slot_aps = {}                                # PCE slot -> [(ap, key, alt)]
    # (round 1's palettes first: they may not take the late slots)
    for ap, cols in sorted(used_pals.items(), key=lambda kv: (1 not in ap_rounds.get(kv[0], {1}), kv[0])):
        if ap >= FIXED:
            continue
        key = tuple(to9(c) for c in cols)
        alt = (tuple(to9(c) for c in rgb64[(ap + 16) * 16:(ap + 16) * 16 + 16])
               if 48 <= ap < 64 and ap in late else key)
        order = [ps for ps in PAL_SLOTS if ps not in LATE_SLOTS] + ([] if 1 in ap_rounds[ap] else list(LATE_SLOTS))
        for ps in order:
            if all((k2, a2) == (key, alt) or not (ap_rounds[ap] & ap_rounds[ap2]) for ap2, k2, a2 in slot_aps.get(ps, [])):
                break
        else:
            for ps2, lst in sorted(slot_aps.items()):
                print('slot', ps2, [(hex(e[0]), sorted(ap_rounds[e[0]])) for e in lst])
            print('unplaced', hex(ap), sorted(ap_rounds[ap]), [g for g, (poses, _) in groups.items() if any(q[4] == ap for p in poses for q in p)])
            for g, (poses, _) in groups.items():
                print('  group', g, sorted(hex(a) for a in {q[4] for p in poses for q in p}))
            raise SystemExit('too many sprite palettes')
        slot_aps.setdefault(ps, []).append((ap, key, alt))
        slot_of[ap] = ps
    # (round 1's set: the colours of the slot's palette that round 1 uses, as captured)
    pal9 = {}
    for ps, lst in sorted(slot_aps.items()):
        ap, key, alt = next((e for e in lst if 1 in ap_rounds[e[0]]), lst[0])
        pal9[key, alt, ps] = ps
    print('sprite palette slots (arcade palette: rounds):',
          {ps: [(hex(e[0]), sorted(ap_rounds[e[0]])) for e in lst] for ps, lst in sorted(slot_aps.items()) if len(lst) > 1})

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
    assert len(cells) <= 1024, len(cells)
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

    def pce_cell(code):
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
        return b
    mobj_syms = []
    for rnd, lst in sorted(mobj.items()):
        order = []
        for sym, code, ap in lst:
            if (code, ap) not in order:
                order.append((code, ap))
            mobj_syms.append((sym, order.index((code, ap)), slot_of[ap]))
        open(f'{out}/mobj_r{rnd}.bin', 'wb').write(b''.join(pce_cell(c) for c, _ in order))
        mobj_syms.append((f'MOBJ_R{rnd}_CELLS', len(order), None))
        print(f'round {rnd}: {len(order)} map object cells')

    vce, vce64, changed = bytearray(), bytearray(), []
    for (key, alt, _), ps in sorted(pal9.items(), key=lambda kv: kv[1]):
        for r, g_, b in key:
            vce += ((g_ << 6) | (r << 3) | b).to_bytes(2, 'little')
        for r, g_, b in alt:
            vce64 += ((g_ << 6) | (r << 3) | b).to_bytes(2, 'little')
        if alt != key:
            changed.append(ps)
    open(f'{out}/objpal.bin', 'wb').write(vce)
    open(f'{out}/objpal_b64.bin', 'wb').write(vce64)
    print(f'bank 64 changes sprite palette slots {changed}')

    # Later rounds load sprite colours of their own (some of colour banks 48 and 64):
    # objpal_r<n>.bin and objpal_r<n>_b64.bin, the same slots with the colours of a
    # snapshot in that round (ROUND_PAL_SNAPS: bank 48's, bank 64's). Arcade palettes
    # that share a slot must agree there too.
    for rnd, ((c48, f48), (c64, f64)) in ROUND_PAL_SNAPS.items():
        r48 = palette_rgb(next(s for s in read_snaps(os.path.join(build, c48)) if s.frame == f48).pal)
        r64 = palette_rgb(next(s for s in read_snaps(os.path.join(build, c64)) if s.frame == f64).pal)
        v48, v64 = bytearray(), bytearray()
        for (key, alt, _), ps in sorted(pal9.items(), key=lambda kv: kv[1]):
            aps = sorted(ap for ap, sl in slot_of.items() if sl == ps and ap < FIXED and rnd in ap_rounds[ap])
            unused = not aps                     # (a slot this round's objects leave alone)
            aps = aps or sorted(ap for ap, sl in slot_of.items() if sl == ps and ap < FIXED)
            for vb, src, d in ((v48, r48, 0), (v64, r64, 16)):
                cols = {tuple(to9(c) for c in src[(ap + d) * 16:(ap + d) * 16 + 16]) for ap in aps}
                if len(cols) > 1 and not unused:
                    print(f'round {rnd}: slot {ps} (arcade palettes {aps}) differs between them; first kept')
                for r, g_, b in tuple(to9(c) for c in src[(aps[0] + d) * 16:(aps[0] + d) * 16 + 16]):
                    vb += ((g_ << 6) | (r << 3) | b).to_bytes(2, 'little')
        open(f'{out}/objpal_r{rnd}.bin', 'wb').write(v48)
        open(f'{out}/objpal_r{rnd}_b64.bin', 'wb').write(v64)
        print(f'round {rnd}: sprite slots changed {[PAL_SLOTS[i] for i in range(len(pal9)) if v48[i * 32:i * 32 + 32] != vce[i * 32:i * 32 + 32]]}'
              f' (bank 64: {[PAL_SLOTS[i] for i in range(len(pal9)) if v64[i * 32:i * 32 + 32] != vce64[i * 32:i * 32 + 32]]})')

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
            for pname, (pg, cap, slot, a, b) in PATHS.items():
                if pg == g:
                    f.write(f'path_{pname}:\t\t\t; (dx, dy, frames) runs from the spawn point, 0 frames: end\n')
                    for dx, dy, n in paths[pname]:
                        f.write(f'\t\tdb\t{dx & 0xff}, {dy & 0xff}, {n}\n')
                    f.write('\t\tdb\t0, 0, 0\n')

    with open(f'{out}/objects.inc', 'w') as f:
        f.write('; Generated by tools/pce_objects.py\n')
        f.write(f'OBJ_CELL_BANK\t= ${first_bank:02X}\nOBJ_CELLS\t= {len(cells)}\n')
        f.write(f'OBJ_FREE_BANK\t= ${first_bank + cell_banks + len(groups):02X}\t; first bank after the object data\n')
        for gi, g in enumerate(groups):
            f.write(f'GRP_{g.upper()}_BANK\t= ${first_bank + cell_banks + gi:02X}\n')
        for (g, name, step), sym in POSE_SYMBOLS.items():
            f.write(f'{sym}\t= {groups[g][1][name][step][0]}\n')
        for sym, (g, code) in CELL_SYMBOLS.items():
            ap = next(q[4] for p in groups[g][0] for q in p if q[2] == code)
            c, fx, fy = cell_of[code, slot_of[ap]]
            a = slot_of[ap] | ((c >> 8) << 4) | (0x40 if fx else 0) | (0x80 if fy else 0)
            f.write(f'{sym}\t= {c}\n{sym}_ATTR\t= ${a:02X}\n')
        for sym, v, ps in mobj_syms:
            f.write(f'{sym}\t= {v}\n')
            if ps is not None:
                f.write(f'{sym}_PAL\t= {ps}\n')
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
