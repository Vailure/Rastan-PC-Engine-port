"""Read sim/snd logs and follow the YM2151's eight FM channels frame by frame.

sim/snd runs the arcade's Z80 sound driver and logs its register writes. What a
PC Engine can use from that is, per channel and per 60 Hz frame: is a note
sounding, at what pitch, and how loud. That comes from

  $08        key on/off: bits 0-2 the channel, 3-6 which operators
  $20+ch     bits 0-2 the algorithm (which operators are carriers), 6-7 L/R
  $28+ch     KC: bits 4-6 the octave, 0-3 the note (3, 7, 11, 15 unused)
  $30+ch     KF: fine pitch, 1/64 of a semitone in bits 2-7
  $60+op*8+ch  TL: that operator's level, 0 loudest, 127 silent, 0.75 dB a step
  $0f        noise: bit 7 on, bits 0-4 the period (channel 7's operator 4)

A channel's loudness follows its loudest carrier (the operators the algorithm
sends to the output, which sum), which is how the driver fades a voice out.
"""
import math

# KC note field -> semitones above C#, which is where the OPM's octave starts.
NOTE = {0: 0, 1: 1, 2: 2, 4: 3, 5: 4, 6: 5, 8: 6, 9: 7, 10: 8, 12: 9, 13: 10, 14: 11}
# Carrier operators per algorithm (operator order M1, M2, C1, C2 = slots 0..3).
CARRIERS = {0: [3], 1: [3], 2: [3], 3: [3], 4: [2, 3], 5: [1, 2, 3], 6: [1, 2, 3], 7: [0, 1, 2, 3]}
A4 = 56          # KC octave 4, note 10 (A): 440 Hz


def frequency(kc, kf):
    """Hz for a KC/KF pair."""
    oct_, note = (kc >> 4) & 7, kc & 15
    semi = oct_ * 12 + NOTE.get(note, 0)
    return 440.0 * 2 ** ((semi - A4 + (kf >> 2) / 64.0) / 12.0)


class Chip:
    """The register file, and the state of each channel as the driver leaves it."""

    def __init__(self):
        self.reg = [0] * 256
        self.on = [False] * 8

    def write(self, r, v):
        self.reg[r] = v
        if r == 0x08:
            self.on[v & 7] = (v & 0x78) != 0

    def level(self, ch):
        """0 (silent) .. 127 (loudest), from the loudest carrier (they sum)."""
        alg = self.reg[0x20 + ch] & 7
        tl = [self.reg[0x60 + op * 8 + ch] & 127 for op in CARRIERS[alg]]
        return 127 - min(tl)

    def pan(self, ch):
        return (self.reg[0x20 + ch] >> 6) & 3

    def state(self, ch):
        """(sounding, Hz, level) for one channel."""
        return self.on[ch], frequency(self.reg[0x28 + ch], self.reg[0x30 + ch]), self.level(ch)

    def noise(self):
        """(on, period 0-31): channel 7's operator 4 is a noise source when enabled."""
        return bool(self.reg[0x0f] & 0x80), self.reg[0x0f] & 31


def frames(path, per_tick=False):
    """Yield (frame, chip, keyed, adpcm) once per logged frame, with `keyed` the set of
    channels keyed on during it (a note retriggered inside one frame still counts).

    With per_tick, yield once per driver tick (its timer IRQ, about 55 Hz) instead:
    that is the rate the music is written at, so a loop repeats tick for tick, while
    60 Hz samples of it drift."""
    chip = Chip()
    frame, keyed, adpcm = None, set(), []
    mark = 'T' if per_tick else 'F'
    for line in open(path):
        p = line.split()
        if not p or p[0] == ';':
            continue
        if p[0] == 'F' and not per_tick or p[0] == 'T' and per_tick:
            if frame is not None:
                yield frame, chip, keyed, adpcm
            frame = (int(p[1]) if p[0] == 'F' else (frame or 0) + 1)
            keyed, adpcm = set(), []
        elif p[0] == 'F' and per_tick and frame is None and int(p[1]) >= 0:
            frame = 0
        elif p[0] == 'Y':
            r, v = int(p[1], 16), int(p[2], 16)
            if r == 0x08 and (v & 0x78):
                keyed.add(v & 7)
            chip.write(r, v)
        elif p[0] == 'A' and len(p) > 2 and p[2] == 'start':
            adpcm.append(int(p[1], 16))
    if frame is not None:
        yield frame, chip, keyed, adpcm
