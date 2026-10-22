from contextlib import redirect_stdout, redirect_stderr
import gzip
import io
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from callsnap import (RAM_SIZE, REGS, V2_HEADER, EVENT, SnapshotError,
                      read_records, records)
from lockstep import compare_call, main
from m68k.interp import Machine

RAM = bytes(RAM_SIZE)
REG = tuple(range(16))


def encoded(version=1, writes=((0x3e0001, 0x55),)):
    if version == 1:
        return b'CSNP' + struct.pack('>I', 42) + REGS.pack(*REG) + RAM * 2
    return (b'CSN2' + V2_HEADER.pack(42, 0x200, 0x100, 0x2715, 0x2710, len(writes))
            + REGS.pack(*REG) * 2 + RAM * 2
            + b''.join(EVENT.pack(*event) for event in writes))


class SnapshotTests(unittest.TestCase):
    def test_legacy_fields_and_multiple_records(self):
        rows = list(read_records(io.BytesIO(encoded() * 2)))
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0].regs_in, REG)
        self.assertEqual(rows[0].frame, 42)
        self.assertIsNone(rows[0].sr_in)

    def test_v2_fields(self):
        row, = read_records(io.BytesIO(encoded(2)))
        self.assertEqual((row.entry, row.return_pc, row.sr_in, row.sr_out),
                         (0x200, 0x100, 0x2715, 0x2710))
        self.assertEqual(row.regs_out, REG)
        self.assertEqual(row.hw_writes, ((0x3e0001, 0x55),))

    def test_empty_and_invalid_magic(self):
        for data in (b'', b'CS', b'NOPE'):
            with self.subTest(data=data), self.assertRaises(SnapshotError):
                list(read_records(io.BytesIO(data)))

    def test_truncation_at_every_field(self):
        for version, cuts in ((1, (4, 7, 8, 71, 72, 100, 16455, 16456, 32839)),
                              (2, (4, 23, 24, 87, 88, 151, 152, 1000, 32919, 32920, 32924))):
            data = encoded(version)
            for cut in cuts:
                with self.subTest(version=version, cut=cut), self.assertRaises(SnapshotError):
                    list(read_records(io.BytesIO(data[:cut])))

    def test_trailing_partial_header_and_mixed_versions(self):
        for tail in (b'C', b'CSN', b'CSNP', encoded(2)):
            with self.subTest(tail=tail[:8]), self.assertRaises(SnapshotError):
                list(read_records(io.BytesIO(encoded() + tail)))

    def test_excessive_event_count(self):
        data = b'CSN2' + V2_HEADER.pack(0, 0x200, 0x100, 0, 0, 1000001)
        with self.assertRaisesRegex(SnapshotError, 'excessive'):
            list(read_records(io.BytesIO(data)))

    def test_gzip_and_corrupt_footer(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'calls.csnp'
            p.write_bytes(gzip.compress(encoded(2)))
            self.assertEqual(len(list(records(p))), 1)
            p.write_bytes(p.read_bytes()[:-4])
            with self.assertRaises(EOFError):
                list(records(p))


class CompareTests(unittest.TestCase):
    def test_ccr_round_trip(self):
        m = Machine(b'', {})
        for ccr in range(32):
            m.ccr = ccr
            self.assertEqual(m.ccr, ccr)
        m.ccr = 0x2715
        self.assertEqual(m.ccr, 0x15)

    def test_all_v2_outputs_and_entry_flags_are_checked(self):
        from dataclasses import replace
        row, = read_records(io.BytesIO(encoded(2)))

        class Fake:
            count = 1
            ram = bytearray(RAM)
            hw_writes = list(row.hw_writes)

            def call(self, entry):
                self.asserted_entry_ccr = self.ccr
                self.ccr = row.sr_out & 31
                self.D, self.A = list(REG[:8]), list(REG[8:])
                return row.return_pc

        machine = Fake()
        self.assertEqual(compare_call(machine, row, 0x200), [])
        self.assertEqual(machine.asserted_entry_ccr, 0x15)
        cases = [replace(row, ram_out=b'\x01' + RAM[1:]),
                 replace(row, sr_out=row.sr_out ^ 1),
                 replace(row, return_pc=0x102),
                 replace(row, regs_out=(99,) + REG[1:]),
                 replace(row, hw_writes=((0x3e0001, 0x54),))]
        for changed in cases:
            with self.subTest(changed=changed.return_pc):
                self.assertTrue(compare_call(Fake(), changed, 0x200))
        with self.assertRaisesRegex(SnapshotError, 'entry mismatch'):
            compare_call(Fake(), row, 0x202)

    def test_cli_empty_corpus_and_expected_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'rom').write_bytes(b'\x4e\x75')
            (root / 'full.asm').write_text('000000  4e75  rts\n')
            corpus = root / 'calls.csnp'
            report = root / 'report.json'
            corpus.write_bytes(gzip.compress(b''))
            args = [str(root / 'rom'), str(root / 'full.asm'), str(corpus), '0', '--json', str(report)]
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(main(args), 1)
            import json
            self.assertFalse(json.loads(report.read_text())['passed'])
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(main(args + ['--expected-calls', '0']), 1)
