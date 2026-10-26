"""Turn the arcade's music and sound effects into PC Engine PSG streams.

usage: pce_sound.py audiocpu.bin adpcm.bin outdir

sim/snd runs the arcade's Z80 sound driver for one sound command and logs what it
writes to the YM2151; tools/ym2151.py reads that back as, per 60 Hz frame and per
FM channel, whether a note is sounding, its pitch and its level. This turns each
of those into a stream the PC Engine's 6 PSG channels can play.

The driver keeps music on FM channels 0-5 and sound effects on 6-7, so music
takes PSG channels 0-5 and an effect takes 4-5 while it plays. What is lost:
each FM voice becomes one PSG waveform, and a note below the PSG's range moves
up an octave.

Stream format (one byte at a time, read once a frame):
  $FF              end: the music loops here, an effect stops
  $FE              end of a tune that plays once (the round-clear jingle)
Each byte of wait is one driver tick (about 54.6 Hz, the rate the arcade's sound
driver sequences at), not a 60 Hz frame; src/sound.asm paces itself to match.
  $80 | mask       channels 0-5 in `mask` change; each one then has three bytes:
                   period low, period high (bit 7 = strike the note again),
                   volume 0-31 (0 = silent)
  n                wait n + 1 frames

Outputs:
  sound.bin   the streams, one after another
  sound.inc   SND_* track and effect numbers, their offsets and banks
"""
import os
import subprocess
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ym2151 import frames

PSG_CLOCK = 3579545.0
INIT = 0xef             # the main CPU's first command: the driver's own setup

# Sound commands, from the main CPU's writes to the sound latch (sim's sndlog) while
# the bot plays: tools/README notes which run showed each one.
MUSIC = [
    ('ROUND1', 0x1a, 7200, True),     # sent as round 1 starts
    ('CASTLE', 0x1b, 7200, True),     # the castle checkpoint
    ('BOSS', 0x1c, 7200, True),       # the boss room
    ('CLEAR', 0x27, 1200, False),     # the round is clear ($29 stops the music, then $27)
]
EFFECTS = [
    ('SWING', 0x09, 60),          # sword swing (pressing attack)
    ('JUMP', 0x0a, 60),           # jump
    ('ENEMY', 0x10, 60),          # an enemy dies
    ('ITEM', 0x15, 90),           # a weapon item taken
    ('BLOCK', 0x17, 90),          # the cave block broken
    ('DIE', 0x0d, 150),           # Rastan dies
    ('HIT', 0x07, 60),            # an enemy struck, not killed ($044804; $08 for some kinds)
    ('HURT', 0x0c, 60),           # Rastan hit ($0555B8, $05560C)
]
NCH = 6


def capture(snd, audio, adpcm, cmd, nframes, tmp, chans=range(NCH), per_tick=True):
    """The FM channels in `chans`, once per driver tick (or per 60 Hz frame). The
    driver keeps the music on FM 0-5 and sound effects on 6-7.

    Returns (rows, notes): `rows` is what each channel sounds like, `notes` the same
    thing as the driver's own note settings, which repeat exactly when a track loops."""
    log = os.path.join(tmp, f'snd_{cmd:02x}.log')
    subprocess.run([snd, audio, adpcm, log, f'{INIT},{cmd}', str(nframes)], check=True,
                   stdout=subprocess.DEVNULL)
    rows, notes = [], []
    for fr, chip, keyed, _ in frames(log, per_tick=per_tick):
        if not per_tick and fr < 30:
            continue
        row, note = [], []
        for ch in chans:
            on, hz, level = chip.state(ch)
            row.append((on and level > 0, hz, level, ch in keyed))
            note.append((chip.reg[0x28 + ch], chip.reg[0x30 + ch], on, ch in keyed))
        rows.append(row)
        notes.append(tuple(note))
    return rows, notes


def period(hz):
    """PSG frequency divider for a pitch, moved up by octaves until it fits."""
    n = int(round(PSG_CLOCK / (32.0 * hz))) if hz > 0 else 0
    while n > 4095:
        n = (n + 1) // 2
    return max(1, min(4095, n))


def volume(level):
    """FM level (0 silent .. 127) -> PSG volume 0-31 (1.5 dB a step, FM is 0.75)."""
    if level <= 0:
        return 0
    return max(1, min(31, 31 - (127 - level) // 2))


def states(rows, first=0):
    """Per frame, the channels as (period, volume, struck), from stream channel `first`."""
    out = []
    for row in rows:
        chans = [(0, 0, False)] * first
        chans += [(period(hz) if on else 0, volume(level) if on else 0, key)
                  for on, hz, level, key in row]
        out.append(chans + [(0, 0, False)] * (NCH - len(chans)))
    return out


def find_loop(notes, window=600):
    """(start, period) in ticks of the part a track repeats, or None.

    A track loops back to a point in its own sequence, so the driver's note settings
    repeat exactly from there. This scores every period by how much of the last
    `window` ticks it reproduces, takes the shortest that reproduces all of it, and
    then walks back to where the repeat began."""
    n = len(notes)
    if n < 2 * window:
        return None
    for period_ in range(30, n - window):
        if all(notes[i] == notes[i - period_] for i in range(n - window, n)):
            i = n - 1
            while i - period_ >= 0 and notes[i] == notes[i - period_]:
                i -= 1
            return max(0, i + 1 - period_), period_
    return None


def encode(st, loop=None):
    """Event stream: only what changes, with a wait count between changes."""
    out = bytearray()
    prev = [(0, 0)] * NCH
    wait = 0
    loop_at = None
    for i, row in enumerate(st):
        if loop is not None and i == loop[0]:
            if wait:
                out.append(wait - 1)
                wait = 0
            loop_at = len(out)
        mask, body = 0, bytearray()
        for ch, (p, v, key) in enumerate(row):
            if (p, v) != prev[ch] or (key and v):
                mask |= 1 << ch
                body += bytes([p & 0xff, ((p >> 8) & 0x0f) | (0x80 if key else 0), v])
                prev[ch] = (p, v)
        if not mask:
            wait += 1
            if wait == 128:
                out.append(127)
                wait = 0
            continue
        if wait:
            out.append(wait - 1)
            wait = 0
        out.append(0x80 | mask)
        out += body
        wait = 1
    if wait:
        out.append(wait - 1)
    out.append(0xFF)
    return bytes(out), loop_at


def main():
    audio, adpcm, out = sys.argv[1:4]
    # The driver sequences on the YM2151's timer A: 64 * (1024 - NA) / 3.579545 MHz.
    tick_rate = int(round((3579545.0 / (64 * 1024)) / 60.0 * 256))
    os.makedirs(out, exist_ok=True)
    tmp = os.environ.get('TMPDIR', '/tmp')
    snd = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'sim', 'snd')

    blob = bytearray()
    entries = []                          # (name, kind, offset, loop offset)
    for name, cmd, nframes, loops in MUSIC:
        rows, notes = capture(snd, audio, adpcm, cmd, nframes, tmp)
        loop = (find_loop(notes) or find_loop(notes, window=300)) if loops else None
        st = states(rows)
        if loop:
            st = st[:loop[0] + loop[1]]   # the way in, then one pass of the loop
        elif not loops:
            while st and all(v == 0 for _, v, _ in st[-1]):
                st.pop()                  # (a jingle: up to its last note)
        data, loop_at = encode(st, loop)
        if not loops:
            data = data[:-1] + b'\xfe'
        entries.append((name, 'M', len(blob), loop_at))
        blob += data
        print(f'{name}: command ${cmd:02x}, {len(st)} ticks, {len(data)} bytes'
              + (f', loops every {loop[1]} ticks from tick {loop[0]}' if loop else ', no loop found'))
    for name, cmd, nframes in EFFECTS:
        rows, _ = capture(snd, audio, adpcm, cmd, nframes, tmp, range(6, 8))
        st = states(rows, first=4)
        while st and all(v == 0 for _, v, _ in st[-1]):
            st.pop()                      # trim the silence after it
        data, _ = encode(st)
        entries.append((name, 'E', len(blob), None))
        blob += data
        print(f'{name}: command ${cmd:02x}, {len(st)} ticks, {len(data)} bytes')

    open(f'{out}/sound.bin', 'wb').write(blob)
    with open(f'{out}/sound.inc', 'w') as f:
        f.write('; Generated by tools/pce_sound.py\n')
        music = [e for e in entries if e[1] == 'M']
        effects = [e for e in entries if e[1] == 'E']
        for i, (name, _, _, _) in enumerate(music):
            f.write(f'SND_{name}\t= {i}\n')
        for i, (name, _, _, _) in enumerate(effects):
            f.write(f'SFX_{name}\t= {i}\n')
        f.write(f'SND_MUSIC_COUNT\t= {len(music)}\nSND_SFX_COUNT\t= {len(effects)}\n')
        f.write(f'SND_TICK_RATE\t= {tick_rate}\t; stream ticks per frame, 8.8 fixed point\n')
        f.write(f'SND_BYTES\t= {len(blob)}\n\n')
        for label, group in (('snd_music', music), ('snd_sfx', effects)):
            for part, idx in (('bank', None), ('lo', 0), ('hi', 1)):
                vals = []
                for _, _, off, _ in group:
                    vals.append(f'^snd_data + {off // 8192}' if part == 'bank'
                                else f'(${0x6000 + off % 8192:04X} >> {8 * idx}) & $FF')
                f.write(f'{label}_{part}:\tdb\t' + ', '.join(vals) + '\n')
        for part, idx in (('bank', None), ('lo', 0), ('hi', 1)):
            vals = []
            for _, _, off, loop_at in music:
                at = off + (loop_at if loop_at is not None else 0)
                vals.append(f'^snd_data + {at // 8192}' if part == 'bank'
                            else f'(${0x6000 + at % 8192:04X} >> {8 * idx}) & $FF')
            f.write(f'snd_loop_{part}:\tdb\t' + ', '.join(vals) + '\n')
    print(f'sound.bin {len(blob)} bytes ({(len(blob) + 8191) // 8192} banks)')


if __name__ == '__main__':
    main()
