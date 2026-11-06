"""test_sound.py rastan.pce god.pce builddir : the PSG music and effects, headless.

The arcade's tunes and effects are converted by tools/pce_sound.py into streams of
PSG frequencies and volumes (see src/sound.asm). This checks the ROM plays them:
what it writes to the PSG must match the stream, the sound that comes out must hold
the notes the stream asks for, and the right tune must start in each place.

tools/tgrun writes a WAV of the emulated PSG (TGRUN_WAV) and a log of every PSG
register write (TGRUN_PSGLOG).
"""
import os
import subprocess
import sys
import wave
import numpy as np
from trace_player import TGRUN

rom, god, build = sys.argv[1:4]
tmp = os.environ.get('TMPDIR', '/tmp')
fails = []
SEL, RIGHT, I, II = '11', '04', '40', '80'
PSG_CLOCK = 3579545.0


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f'  ({detail})' if detail else ''))
    if not ok:
        fails.append(name)


def equ(name):
    for line in open(os.path.join(build, 'sound', 'sound.inc')):
        if line.startswith(name + '\t'):
            return int(line.split('=')[1].split(';')[0].strip())
    raise KeyError(name)


def stream(track):
    """[(tick, channel, period, volume)] for a music track, up to its loop; only the
    notes it starts, since a note ending writes no frequency."""
    blob = open(os.path.join(build, 'sound', 'sound.bin'), 'rb').read()
    offs = []
    for name in ('ROUND1', 'CASTLE', 'BOSS'):
        offs.append(0)
    # The offsets are in sound.inc as bank/lo/hi; rebuild them the same way.
    banks = [l for l in open(os.path.join(build, 'sound', 'sound.inc')) if l.startswith('snd_music_')]
    bank = [int(v.split('+')[1]) for v in banks[0].split('db')[1].split(',')]
    lo = [int(v.split('$')[1].split(' ')[0], 16) for v in banks[1].split('db')[1].split(',')]
    off = bank[track] * 8192 + (lo[track] - 0x6000)
    out, tick, i = [], 0, off
    while i < len(blob):
        b = blob[i]; i += 1
        if b == 0xFF:
            break
        if b & 0x80:
            for ch in range(6):
                if (b >> ch) & 1:
                    p = ((blob[i + 1] & 0x0f) << 8) | blob[i]
                    if blob[i + 2]:
                        out.append((tick, ch, p, blob[i + 2]))
                    i += 3
            tick += 1
        else:
            tick += b + 1
    return out


def run(r, frames, keys, wav=None, psg=None):
    env = dict(os.environ)
    if wav:
        env['TGRUN_WAV'] = wav
    if psg:
        env['TGRUN_PSGLOG'] = psg
    out = os.path.join(tmp, f'snd_{os.getpid()}.ppm')
    subprocess.run([TGRUN, r, str(frames), out] + [str(k) for k in keys], check=True,
                   capture_output=True, env=env)


def psg_notes(path):
    """[(write index, channel, period, volume)] from a PSG register log."""
    cur, out = {}, []
    for n, line in enumerate(open(path)):
        ch, a, d = line.split()
        ch, a, d = int(ch), int(a, 16), int(d, 16)
        c = cur.setdefault(ch, [0, 0])
        if a == 0x802:
            c[0] = d
        elif a == 0x803:
            c[1] = d & 15
        elif a == 0x804 and (d & 0x80):
            out.append((n, ch, (c[1] << 8) | c[0], d & 31))
    return out


# 1. What the ROM writes to the PSG is what the stream says (round 1 starts at once).
psg = os.path.join(tmp, f'psg_{os.getpid()}.log')
run(rom, 240, [], psg=psg)
played = psg_notes(psg)
want = stream(equ('SND_ROUND1'))
first_want = [(ch, p, v) for _, ch, p, v in want[:6]]
first_got = [(ch, p, v) for _, ch, p, v in played[:6]]
check('the ROM plays round 1 from its first notes', first_got == first_want,
      f'{first_got} vs {first_want}')
check('every channel is used', len({ch for _, ch, _, _ in played}) >= 5,
      f'channels {sorted({ch for _, ch, _, _ in played})}')

# 2. The sound that comes out holds those notes.
wav = os.path.join(tmp, f'snd_{os.getpid()}.wav')
run(rom, 420, [], wav=wav)
w = wave.open(wav)
a = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, 2).mean(1)
check('it makes a sound', np.sqrt((a ** 2).mean()) > 500, f'rms {np.sqrt((a ** 2).mean()):.0f}')
# Frequencies the stream holds through the window 3 s .. 4 s (ticks 164 .. 218).
hold = {}
for tick, ch, p, v in want:
    if tick <= 218:
        hold[ch] = (p, v) if v else None
expect = sorted(PSG_CLOCK / (32 * p) for p, v in (x for x in hold.values() if x) if p)
seg = a[3 * 44100:4 * 44100]
sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
fr = np.fft.rfftfreq(len(seg), 1 / 44100)
peaks = [float(fr[i]) for i in np.argsort(sp)[-12:][::-1] if fr[i] > 30]
matched = [f for f in peaks[:5] if any(abs(f - e) / e < 0.03 for e in expect)]
check('the notes it plays are the ones the stream asks for', len(matched) >= 3,
      f'peaks {[round(f) for f in peaks[:5]]} vs {[round(e) for e in expect]}')

# 3. An attack plays the swing effect on channels 4 and 5.
quiet = len([1 for _, ch, _, _ in psg_notes(psg) if ch >= 4])
run(rom, 400, [300, 302, II], psg=psg)
swung = len([1 for _, ch, _, _ in psg_notes(psg) if ch >= 4])
check('swinging the sword plays an effect', swung > quiet, f'{swung} writes to channels 4-5 (idle: {quiet})')

# 4. The castle and the boss room have their own tunes (the debug menu's warps).
for cp, track, name in ((4, 'SND_CASTLE', 'castle'), (6, 'SND_BOSS', 'boss room')):
    keys = [40, 90, SEL] + sum([[100 + 6 * k, 100 + 6 * k, RIGHT] for k in range(cp)], []) + [150, 150, I]
    run(god, 900, keys, psg=psg)   # (each tune starts with the arcade's own lead-in)
    played = [(ch, p, v) for _, ch, p, v in psg_notes(psg)]
    want = [(ch, p, v) for _, ch, p, v in stream(equ(track))[:4]]
    ok = any(played[i:i + len(want)] == want for i in range(len(played)))
    check(f'the {name} plays its own tune', ok, f'wanted {want[:2]}, got {played[-4:]}')

# 5. Jumping and dying play the arcade's voice samples on channel 5's direct D/A:
# exactly the levels tools/pce_voice.py made, one per timer tick, and the music has
# its channel back afterwards.
def dda(path):
    """[(write index, channel, level)] for waveform-port writes in D/A mode, and the
    index of the first ordinary note written to channel 5 after them."""
    mode, out, back = {}, [], None
    for n, line in enumerate(open(path)):
        ch, a, d = line.split()
        ch, a, d = int(ch), int(a, 16), int(d, 16)
        if a == 0x804:
            mode[ch] = d & 0xC0
            if ch == 5 and out and d & 0xC0 == 0x80 and back is None:
                back = n
        elif a == 0x806 and mode.get(ch) == 0xC0:
            out.append((n, ch, d))
    return out, back


voice = open(os.path.join(build, 'voice', 'voice.bin'), 'rb').read()
jump = voice[:voice.index(0x80)]
run(god, 460, [360, 363, I], psg=psg)        # (god: no lizardman's hit stops the jump)
got, back = dda(psg)
check('a jump plays the jump voice on channel 5, level for level',
      [d for _, _, d in got] == list(jump) and {ch for _, ch, _ in got} == {5},
      f'{len(got)} of {len(jump)} levels, channels {sorted({ch for _, ch, _ in got})}')
check('the music gets channel 5 back after it', back is not None, f'write {back}')
wav2 = os.path.join(tmp, f'snd_v_{os.getpid()}.wav')
run(god, 460, [360, 363, I], wav=wav2)
w = wave.open(wav2)
b = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, 2).mean(1)
run(god, 460, [], wav=wav)
w = wave.open(wav)
q = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, 2).mean(1)
seg = slice(int(361 / 60 * 44100), int(380 / 60 * 44100))
extra = np.sqrt(((b[seg] - q[seg]) ** 2).mean())
check('the voice is heard over the music', extra > 300, f'rms difference {extra:.0f}')

print(f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
