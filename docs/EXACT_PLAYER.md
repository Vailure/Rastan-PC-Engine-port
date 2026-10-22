# Exact-player translation: verification boundary

This change prepares the HuC6280 translation. It does not replace the approximate
controller or establish arcade gameplay parity. The documented 9,215-call legacy
result has not been reproduced by these tests: the repository excludes the arcade
ROM and recordings.

## Run the independent tests

```
make test-tooling
```

Needs Python 3.10+, a C compiler, zlib development headers and libm. No arcade
assets, Pillow, numpy, HuC checkout, or PCE assembler are needed. Tests build the
actual Musashi simulator and disassembler, create a synthetic program, capture
128 completed calls, and replay them through the reference interpreter. Mutations
of each output category must fail. Legacy captures remain readable but explicitly
report their narrower comparison contract.

## Capture the arcade routine with the stronger contract

```
make lockstep LOCKSTEP_SEED=1 LOCKSTEP_FRAMES=6000
make lockstep LOCKSTEP_SEED=2 LOCKSTEP_FRAMES=6000
```

These commands require the user's own World rev 1 Rastan ROM set, as before.
Each invocation replaces `build/fuzz.txt`, `build/fuzz.csnp`, and
`build/lockstep.json`; preserve all three under seed-specific names to retain a
corpus. JSON includes the entry address, seed, counts, pass/fail status, error,
and SHA-256 hashes of ROM, listing, recording and script. To verify a known corpus
length, supply `--expected-calls N` directly to `tools/lockstep.py`.

`callsnap2 5132a path.csnp` captures the new format; `callsnap` retains legacy
output. Capture completes only when both the expected return PC and stack pointer
are restored. A call still active at simulation end fails capture. Storage failures
also fail instead of leaving an apparently successful run.

## Binary format

Every record is gzip-compressed in the file. All numeric fields are big endian;
RAM bytes keep arcade ordering. Records of different versions cannot be mixed.
There is no file-level header.

| Field | Legacy CSNP | CSN2 |
|---|---|---|
| Magic | 4 bytes `CSNP` | 4 bytes `CSN2` |
| Frame at return | u32 | u32 |
| Entry PC, return PC | absent | two u32 |
| Entry SR, exit SR | absent | two u16 |
| Hardware-write count | absent | u32 |
| Entry D0..D7, A0..A7 | sixteen u32 | sixteen u32 |
| Exit D0..D7, A0..A7 | absent | sixteen u32 |
| Entry RAM, exit RAM | two 16,384-byte arrays | two 16,384-byte arrays |
| Hardware events | absent | count × (u32 address, u8 value) |

The comparison restores entry CCR and checks all RAM, all exit registers, exit
CCR, return PC and ordered writes outside work RAM. Only SR bits 0..4 are compared:
the reference interpreter models CCR, not supervisor state or interrupt masks.
Hardware events include writes to sound latches; actual sound synthesis is outside
this contract. Non-RAM reads remain unsupported by the interpreter unless already
implemented. New failures are evidence to investigate, not grounds to mask outputs.

Empty recordings, incomplete fields, bad magic, mixed versions, gzip corruption,
and excessive event counts fail. A structurally complete prefix cannot be detected
without an expected call count; use the count from the retained corpus report.

## Next implementation gates, in order

1. Re-record directed actions, attract ropes and several fuzz seeds using CSN2.
   Resolve any new register/CCR/event mismatches against Musashi before treating
   the interpreter as a complete translation oracle. Retain expected counts and
   hashes. Add directed fixtures for states the scripts do not reach.
2. Use `focus 5132a` with `profile` to collect `ramtouch.bin` and `profile.out`.
   Classify player/global/stack writes, read-only tables, collision window and
   presentation data. Design an explicit arcade-to-PCE address map that fits in
   8 KB alongside the engine. A touched-byte count alone does not establish safe
   compaction or whole-game coverage.
3. Reuse `m68k/decode.py` for a fail-closed HuC6280 emitter. Start with captured
   leaf helpers; retain original-PC labels. Test widths, partial register writes,
   sign extension, borrow, overflow, effective-address side effects and stack
   behavior against the reference before lowering a full player call.
4. Add a test-only entry-state loader and completion handshake to `tgrun`. Run
   each translated helper and then `$05132A` from recorded states. Expand compact
   PCE output back to arcade addresses for comparison; validate untouched bytes.
   Follow isolated-call tests with chained multi-frame tests.
5. Add an opt-in `EXACT_PLAYER` playable build. Move animation progression out of
   `player_draw`; test that repeated or skipped drawing leaves simulation intact.
   Adapt input edges and coordinate spaces explicitly. Keep the approximate build
   available until exact mode passes behavior and timing checks.
6. Add bidirectional residency to the offline-forward-only stage streamer before
   enabling leftward camera travel. Verify reversals pixel-for-pixel. Extend poses,
   collision effects and external damage/weapon/enemy producers with directed
   capture coverage, then measure worst-case frame time including uploads.
