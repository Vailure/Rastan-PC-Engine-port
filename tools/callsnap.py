"""Strict reader for gzip-compressed player-call snapshots.

CSNP is the legacy RAM-only format. CSN2 also records the call boundary,
entry/exit SR, exit registers, and ordered non-work-RAM byte writes.
All integers on disk are big endian; RAM retains arcade byte order.
"""
from dataclasses import dataclass
import gzip
import struct

RAM_SIZE = 0x4000
REGS = struct.Struct('>16I')
V2_HEADER = struct.Struct('>IIIHHI')  # frame, entry, return_pc, SR in/out, write count
EVENT = struct.Struct('>IB')
MAX_EVENTS = 1_000_000  # reject corrupt counts before allocating/reading large payloads


class SnapshotError(ValueError):
    pass


@dataclass(frozen=True)
class CallSnapshot:
    frame: int
    regs_in: tuple
    ram_in: bytes
    ram_out: bytes
    version: int = 1
    entry: int | None = None
    return_pc: int | None = None
    sr_in: int | None = None
    sr_out: int | None = None
    regs_out: tuple | None = None
    hw_writes: tuple | None = None


def read_exact(stream, size, field):
    data = stream.read(size)
    if len(data) != size:
        raise SnapshotError(f'truncated {field}: expected {size} bytes, got {len(data)}')
    return data


def read_records(stream):
    """Read uncompressed records; only EOF between complete records is valid."""
    count = 0
    version = None
    while True:
        magic = stream.read(4)
        if not magic:
            if not count:
                raise SnapshotError('empty snapshot corpus')
            return
        if len(magic) != 4:
            raise SnapshotError('truncated record magic')
        if magic not in (b'CSNP', b'CSN2'):
            raise SnapshotError(f'invalid record magic {magic!r}')
        current = 1 if magic == b'CSNP' else 2
        if version is not None and version != current:
            raise SnapshotError('mixed snapshot versions')
        version = current
        if version == 1:
            frame, = struct.unpack('>I', read_exact(stream, 4, 'frame'))
            entry = return_pc = sr_in = sr_out = None
            nwrite = 0
        else:
            frame, entry, return_pc, sr_in, sr_out, nwrite = V2_HEADER.unpack(
                read_exact(stream, V2_HEADER.size, 'CSN2 header'))
            if nwrite > MAX_EVENTS:
                raise SnapshotError(f'excessive hardware-write count {nwrite}')
        regs_in = REGS.unpack(read_exact(stream, REGS.size, 'entry registers'))
        regs_out = REGS.unpack(read_exact(stream, REGS.size, 'exit registers')) if version == 2 else None
        ram_in = read_exact(stream, RAM_SIZE, 'entry RAM')
        ram_out = read_exact(stream, RAM_SIZE, 'exit RAM')
        hw = tuple(EVENT.unpack(read_exact(stream, EVENT.size, 'hardware write'))
                   for _ in range(nwrite)) if version == 2 else None
        count += 1
        yield CallSnapshot(frame, regs_in, ram_in, ram_out, version, entry,
                           return_pc, sr_in, sr_out, regs_out, hw)


def records(path):
    with gzip.open(path, 'rb') as stream:
        yield from read_records(stream)
