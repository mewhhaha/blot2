# Runtime hills: loops and indexed assignments

Three small compiler changes improve all shared kernels. Five fresh matched
pairs use the same pinned workloads, checksums and Node 24.22.1 / V8
13.6.233.17-node.58. Preparation and warmup remain outside the kernel clock. All
samples pass. Exact observations and fingerprints are in
[the evidence](2026-11-03-runtime-hills.json).

| Kernel                 | Before (ms) | After (ms) | Paired speedup |
| ---------------------- | ----------: | ---------: | -------------: |
| Fannkuch               |      728.86 |     186.21 |          3.93x |
| CRC32                  |    1,328.81 |     141.69 |          9.46x |
| Custom eight-lane hash |    5,767.96 |     987.32 |          5.81x |

These are bounded workloads with unchanged production problem sizes and reduced
repetition counts. This covers three of seven adapted LangArena tasks, not the
full 50-task catalog. Hash buffers use U32 elements in Blot versus U8 in Goose;
ABI costs also differ. The original eight-lane hash is not cryptographic
SHA-256. Shared-host dispersion and every paired sample are retained in the
evidence.

A separate five-pair release run compares the current compiler to the original
frozen Goose direct backend. All Goose artifacts still match the previous
comparator byte-for-byte. Cold builds use fresh uncached drivers with profiling
disabled; complete process wall includes startup.

| Kernel                 | Cold build Blot / Goose (ms) | Wasm Blot / Goose (bytes) | Kernel Blot / Goose (ms) |
| ---------------------- | ---------------------------: | ------------------------: | -----------------------: |
| Fannkuch               |                68.53 / 71.01 |             6,073 / 4,067 |           187.37 / 15.65 |
| CRC32                  |                49.88 / 73.97 |             5,068 / 3,309 |           138.25 / 14.42 |
| Custom eight-lane hash |                53.68 / 71.68 |             5,833 / 6,788 |           984.79 / 15.67 |

The README runtime chart uses the matched before/after medians and Goose from
the separate comparison. It uses a linear axis starting at zero. Tiny-source
compilation does not establish large-source or Gdev throughput.

All three **unchanged official production workloads now finish below the
30-second process cap**, with their official checksums. The previous compiler
timed out on all three. One completion run per case is not a production
performance ranking.

| Production case        | Whole process | Measured kernel |
| ---------------------- | ------------: | --------------: |
| Fannkuch               |        19.60s |          16.17s |
| CRC32                  |         6.50s |           5.16s |
| Custom eight-lane hash |        22.41s |          18.47s |

The baseline CPU profile attributed about 27% of samples to region rewind and
38% to checked addressing. The compiler emitted rewind even in owner-free inner
loops, and pure arithmetic helpers retained unused storage marks. The final
changes are:

- Use the existing no-owner cleanup proof on loop backedges and exits.
  Conditional allocations and closed temporaries still retain their cleanup.
- Replace an unused frame mark with neutral instructions only after the complete
  scope proves that it created no owner. Instruction coordinates remain stable;
  allocating scopes keep their marks.
- Reuse an indexed assignment’s pre-RHS checked address. The selected borrow
  pins the nonmoving extent, preserving growth, sibling alias writes, variant
  validation and bounds-before-RHS ordering.

Eight-node scalar inlining was tried separately. Its single-sample pilot showed
no runtime gain over address reuse, so it was reverted before qualification.
Diagnostic noLLVM compiler timings are not compared to release compiler timings.

The new release produces **12,550,610 bytes** for actual Gdev Main, down from
12,932,581 (381,971B / 2.95%). One matched compile pilot takes **6.16s →
6.07s**. That is not enough evidence for a latency improvement; the five-second,
subsecond and 1–2MB goals remain unmet. The old Main hash matches the preceding
checkpoint exactly. World/editor and hand checks pass with smaller Wasm; all
seven renderer streams remain identical.

Main also passes V8 validation and engine compilation. Declared locals grow
408,892 → 413,749 and mutable globals 56,122 → 56,176; these counts are not
monotonic improvements. Encoded local/global traffic falls 184,899B, calls
85,192B and constants 111,981B. Payload load/store and arithmetic byte counts
remain identical.

Qualification:

- All 2,931 native laws compile without LLVM. The affected 195-law family and
  190 executed-Wasm tests pass in 44.79s, with sampled allocation faults and
  zero Zig lint findings.
- Ten focused native laws pass exhaustive allocation-failure sweeps with no
  leaks. Final LLVM also passes all 190 affected guest tests.
- New regressions cover bounded scratch reuse, nested break/continue,
  conditional owner returns, alias growth, sibling writes, trap-before-RHS order
  and shrinking rejection. Both tiers and sync/async calls run.
- Baseline-reproduced obsolete helper/proof counters were updated to positive
  completed-plan contracts. Wide-field tests accept either indexing or
  forwarding every result word; all executed expectations remain.
- Full compiler qualification still stops at the unchanged List/chunk
  storage-escape failure: 48 smoke passes / one failure. Installed Pen rejects
  ABI 8, so no new full-game frame or PNG is qualified.

The next hill is a validated fixed-array span: retain per-access bounds and
lifetime/effect order while validating stable descriptor/owner facts once. The
current array path still performs repeated header and epoch validation. The
post-change profile mostly attributes work to the digest body, including inlined
helpers; it does not isolate the remaining checks numerically.
