"""Exercise the real Musashi writer and Python reader/interpreter without arcade assets."""
import gzip
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from callsnap import records


class CaptureIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (ROOT / 'sim/sim').exists() or not (ROOT / 'sim/dasm').exists():
            raise RuntimeError('build simulator first: make test-tooling')

    def make_rom(self, root):
        rom = bytearray(0x60000)
        struct.pack_into('>II', rom, 0, 0x10ff00, 0x100)
        # Disable interrupts; make 128 calls with X/Z/C set, then STOP.
        reset = bytes.fromhex('46fc2700 363c007f 44fc0015 4eb900000200 51cbfff4 4e722700')
        rom[0x100:0x100 + len(reset)] = reset
        # Branch on entry carry; exercise word arithmetic, RAM and sound writes.
        player = bytes.fromhex('6504 7401 6002 7402 13fc00120010c100 '
                               '303cabcd 72ff 5241 13fc0055003e0001 4e75')
        rom[0x200:0x200 + len(player)] = player
        path = root / 'synthetic.bin'
        path.write_bytes(rom)
        return path

    def capture(self, root, version):
        rom = self.make_rom(root)
        corpus = root / 'calls.csnp'
        script = root / 'script.txt'
        script.write_text(f'end 1\ncallsnap{"2" if version == 2 else ""} 200 {corpus}\n')
        run = subprocess.run([str(ROOT / 'sim/sim'), str(rom), str(script), '/dev/null', '1'],
                             capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        listing = root / 'full.asm'
        result = subprocess.run([str(ROOT / 'sim/dasm'), str(rom), '0', '300'],
                                capture_output=True, check=True)
        listing.write_bytes(result.stdout)
        # The disassembler fallback convention expects dasm beside the listing.
        (root / 'dasm').symlink_to(ROOT / 'sim/dasm')
        return rom, corpus, listing, script

    def replay(self, root, rom, corpus, listing, script, *extra):
        report = root / 'report.json'
        run = subprocess.run([sys.executable, str(ROOT / 'tools/lockstep.py'),
                              str(rom), str(listing), str(corpus), '200',
                              '--json', str(report), '--script', str(script), *extra],
                             capture_output=True, text=True)
        return run, json.loads(report.read_text())

    def test_v2_real_capture_replay_and_mutations(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rom, corpus, listing, script = self.capture(root, 2)
            rows = list(records(corpus))
            self.assertEqual(len(rows), 128)
            self.assertEqual(rows[0].sr_in & 31, 0x15)
            self.assertEqual(rows[0].regs_out[2], 2)  # entry carry took the branch
            self.assertEqual(rows[0].hw_writes, ((0x3e0001, 0x55),))
            run, report = self.replay(root, rom, corpus, listing, script,
                                      '--expected-calls', str(len(rows)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertEqual(report['ok'], len(rows))
            self.assertEqual(report['versions'], [2])
            self.assertIn('sha256', report['inputs']['script'])
            run, _ = self.replay(root, rom, corpus, listing, script,
                                 '--expected-calls', str(len(rows) + 1))
            self.assertNotEqual(run.returncode, 0)
            original = gzip.decompress(corpus.read_bytes())
            # Mutate each newly checked output independently in the first record.
            # magic+frame+entry+return+SRin+SRout+count+regsIn+regsOut+RAMin+RAMout+events
            for offset in (12, 19, 88, 152 + 0x4000, 152 + 0x8000 + 4):
                data = bytearray(original)
                data[offset] ^= 1
                corpus.write_bytes(gzip.compress(data))
                run, report = self.replay(root, rom, corpus, listing, script)
                self.assertNotEqual(run.returncode, 0, f'false pass at byte {offset}')
                self.assertGreater(report['bad'], 0)

    def test_legacy_capture_still_replays(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rom, corpus, listing, script = self.capture(root, 1)
            # Legacy entry CCR is unknown. The different D2 result is invisible
            # to RAM-only comparison; retain compatibility and label the limit.
            run, report = self.replay(root, rom, corpus, listing, script)
            self.assertEqual(report['versions'], [1])
            self.assertIn('Legacy CSNP', run.stdout)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_incomplete_call_and_failed_capture_open_are_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rom = self.make_rom(root)
            data = bytearray(rom.read_bytes())
            data[0x200:0x202] = bytes.fromhex('60fe')  # routine never returns
            rom.write_bytes(data)
            script = root / 'script.txt'
            corpus = root / 'calls.csnp'
            script.write_text(f'end 1\ncallsnap2 200 {corpus}\n')
            run = subprocess.run([str(ROOT / 'sim/sim'), str(rom), str(script), '/dev/null'],
                                 capture_output=True, text=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertIn('incomplete callsnap call', run.stderr)
            script.write_text(f'end 1\ncallsnap2 200 {root / "absent" / "calls.csnp"}\n')
            run = subprocess.run([str(ROOT / 'sim/sim'), str(rom), str(script), '/dev/null'],
                                 capture_output=True, text=True)
            self.assertNotEqual(run.returncode, 0)
