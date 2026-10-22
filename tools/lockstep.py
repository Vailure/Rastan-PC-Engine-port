"""Replay recorded player calls against the 68000 reference interpreter.

Legacy CSNP compares all 16 KB RAM. CSN2 additionally checks D0..A7,
CCR (SR bits 0..4), return PC, and ordered hardware byte writes.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys
import zlib
from callsnap import records, SnapshotError
from m68k.decode import load_listing
from m68k.interp import Machine, Unsupported


def compare_call(machine, record, entry):
    if record.entry is not None and record.entry != entry:
        raise SnapshotError(f'entry mismatch: record {record.entry:06x}, requested {entry:06x}')
    machine.D = list(record.regs_in[:8])
    machine.A = list(record.regs_in[8:])
    machine.ram[:] = record.ram_in
    machine.ccr = record.sr_in & 31 if record.sr_in is not None else 0
    return_pc = machine.call(entry)
    differences = []
    ram_diff = [i for i, (actual, expected) in enumerate(zip(machine.ram, record.ram_out))
                if actual != expected]
    if ram_diff:
        differences.append(f'{len(ram_diff)} RAM bytes differ: ' + ' '.join(
            f'{0x10c000+i:06x}:expected={record.ram_out[i]:02x}/actual={machine.ram[i]:02x}'
            for i in ram_diff[:12]))
    if record.version == 2:
        for i, (actual, expected) in enumerate(zip(machine.D + machine.A, record.regs_out)):
            if actual != expected:
                name = f'D{i}' if i < 8 else f'A{i-8}'
                differences.append(f'{name}: expected={expected:08x}/actual={actual:08x}')
        if machine.ccr != record.sr_out & 31:
            differences.append(f'CCR: expected={record.sr_out & 31:02x}/actual={machine.ccr:02x}')
        if return_pc != record.return_pc:
            differences.append(f'return PC: expected={record.return_pc:08x}/actual={return_pc:08x}')
        if tuple(machine.hw_writes) != record.hw_writes:
            differences.append('hardware writes differ: '
                               f'expected={record.hw_writes[:8]}/actual={machine.hw_writes[:8]}')
    return differences


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(data)
    return h.hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rom')
    parser.add_argument('listing')
    parser.add_argument('corpus')
    parser.add_argument('entry', type=lambda x: int(x, 16))
    parser.add_argument('--expected-calls', type=int)
    parser.add_argument('--json', dest='report', help='write machine-readable results and input hashes')
    parser.add_argument('--script', help='capture script to hash in the report')
    parser.add_argument('--seed', type=int, help='capture seed to record in the report')
    args = parser.parse_args(argv)
    result = dict(ok=0, bad=0, calls=0, instructions=0, versions=[], error=None)
    try:
        if args.expected_calls is not None and args.expected_calls <= 0:
            raise SnapshotError('--expected-calls must be positive')
        rom = Path(args.rom).read_bytes()
        lines = load_listing(args.listing, dasm=str(Path(args.listing).with_name('dasm')), rom=args.rom)
        for record in records(args.corpus):
            machine = Machine(rom, lines)
            result['calls'] += 1
            if record.version not in result['versions']:
                result['versions'].append(record.version)
            try:
                differences = compare_call(machine, record, args.entry)
            except Unsupported as exc:
                differences = [f'unsupported: {exc}']
            result['instructions'] += machine.count
            if differences:
                result['bad'] += 1
                if result['bad'] <= 5:
                    print(f'call {result["calls"]}, frame {record.frame}: ' + '; '.join(differences))
            else:
                result['ok'] += 1
        if args.expected_calls is not None and result['calls'] != args.expected_calls:
            raise SnapshotError(f'expected {args.expected_calls} calls, read {result["calls"]}')
    except (OSError, EOFError, zlib.error, SnapshotError, ValueError, KeyError) as exc:
        result['error'] = str(exc)
    result['passed'] = result['error'] is None and result['bad'] == 0 and result['calls'] > 0
    if result['error']:
        print(f'ERROR: {result["error"]}', file=sys.stderr)
    print(f'{result["ok"]} calls match, {result["bad"]} differ; '
          f'{result["instructions"] / max(1, result["calls"]):.0f} instructions/call')
    if result['versions'] == [1]:
        print('Legacy CSNP: entry CCR assumed zero; exit registers/CCR/return PC/hardware writes unchecked.')
    if args.report:
        result.update(entry=f'{args.entry:06x}', seed=args.seed)
        try:
            result['inputs'] = {name: dict(path=path, sha256=sha256(path))
                                for name, path in [('rom', args.rom), ('listing', args.listing),
                                                   ('corpus', args.corpus), ('script', args.script)] if path}
            Path(args.report).write_text(json.dumps(result, indent=2) + '\n')
        except OSError as exc:
            print(f'ERROR writing report: {exc}', file=sys.stderr)
            return 1
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
