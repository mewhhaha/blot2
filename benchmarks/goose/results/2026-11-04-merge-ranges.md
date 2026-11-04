# Guarded merge ranges — 2026-11-04

Unchanged merge sort improves another **156.70 → 137.19ms**, a **1.145x median
paired speedup**. Five fresh release pairs cover four 400,000-element sorts,
including original copy/clear work, after one kernel warmup and an excluded
whole-process warmup. The fresh matched Blot/Goose ratio is **1.19x**. Both
ports retain their original recursive algorithms and four-byte elements.

[Machine-readable evidence](2026-11-04-merge-ranges.json) pins sources,
compilers, workloads, Wasm and host, with every observation and diagnostic.
Baseline: `185a715584920517b479724982cd94bd59bbc69d`. Final release compiler
SHA256: `a18ced7646f5237d49f508ffdee850a0eed8490ee04944e3ec8c8f6e39da8745`. The
final release merge Wasm is byte-identical to the native-fast compiler pilot.

## What changed

The previous source proof already recognized exact U32 two-cursor merges. This
change retains that proof and adds complete-range checks for merges with at
least eight guaranteed steps from each source. Nested guards validate first
source, second source and destination, proving inclusive bounds, conservative
maximum output capacity and nonwrapping byte addresses. Fixed scalar admission
already proves the four-byte layout. A declined guard executes the exact checked
instruction suffix; short loops stay checked.

Only successful guards initialize private byte pointers. Every iteration reloads
both candidate values, selects/stores and advances pointers. Actual scalar
cursor positions are restored on exit. Aliases, ties, access ordering and the
iteration that exhausts a source remain observable exactly as before. Unsafe
ranges keep valid-prefix writes, original wrapping and traps through the
fallback. Capacity reservation and detached publication retain allocation
rollback.

A separate bounded Core walk removes unused destination old-value loads for
plain terminal scalar replacements without scalar addresses. It excludes `self`,
captures, globals, calls, dispatch and unsupported/exhausted walks. It never
uses the incomplete liveness map. Address/owner/read/bounds checks and the live
borrow still precede replacement evaluation; store order and exact scalar bits
remain. See [the contract](../../../docs/compiler/CONTRACT.md).

Astra reviewed guards, access ordering, fallback, scalar omission and pointer
restoration without finding blockers. Both tiers and sync/async tests exercise
fast-sized aliases/ties, nonzero offsets, final cursors, short targets, late
source bounds, wrapped indices, skipped accesses, persisted trap prefixes,
self-dependent replacements and F32 signed-zero/NaN bits.

## Measurements and tradeoffs

The range-only diagnostic gives about 5%. Scalar old-load deletion shrinks code
but adds no material isolated merge gain. Combining range checks and pointer
iteration gives about 15%; the headline uses final release pairs, not those
pilots. A before-change whole-invocation V8 profile places 981 of 1,421 guest
leaf samples in merge, 232 in owner validation, 72 in recursion and 68 in
checked addressing. Preparation/warmup are included. These samples are
diagnostic, not exclusive kernel timing or hardware counters.

| Workload       | Before ms | After ms | Paired speedup |    Wasm bytes |
| -------------- | --------: | -------: | -------------: | ------------: |
| fannkuch       |     13.86 |    13.44 |         1.042x | 6,035 → 5,984 |
| crc32          |     17.81 |    17.63 |         1.009x | 5,191 → 5,182 |
| custom_hash    |    102.52 |    97.67 |         1.048x | 5,943 → 5,925 |
| sieve          |     25.47 |    24.41 |         1.032x | 5,134 → 5,098 |
| sort_merge     |    156.70 |   137.19 |         1.145x | 6,810 → 7,196 |
| sort_quick     |    120.03 |   119.28 |         1.001x | 6,153 → 6,118 |
| mandelbrot_f32 |     73.04 |    73.96 |         0.998x | 6,152 → 6,143 |

All seven pairs are freshly compared with Goose as well; both README charts use
that current five-sample survey. Quicksort and Mandelbrot are effectively
unchanged. Mandelbrot's median rises about 1.3%, while its paired speedup is
0.998x; the distributions do not establish a material change. Small gains on
other kernels remain separate from the measured merge-path gain. The guarded
merge path costs **386B** (6,810 → 7,196B). Cold-build bars are fresh uncached
process timings, not evidence of a controlled compiler-latency gain. The Goose
executable and benchmark inputs match the preceding pinned comparison; its
independently changing checkout identity is recorded separately.

## Gdev and qualification

Main saves **10,976B** to **10,038,987B**. It admits zero merge rewrites and
records 1,425 static scalar old-load omissions. Emitter counters are not exact
final encoded instruction counts. Three fresh uncached release pairs measure
**5.362 → 5.306s**, with changes +14/-107/-33ms: no material compilation gain. A
fresh inspected NVIDIA frame passes the runner and matches the preceding PNG.
ABI 8, session 2, saved schema 26 and original 2MiB temporary / 256KiB
persistent / 2MiB transport / 4096-owner budgets remain. Broader gameplay and
software-adapter checks remain pending.

All **2,954 native laws compile without LLVM**. The development family passes
**10 native / 32 guests in 37.56s**, including complete native compilation. Four
focused laws pass full fault mode, including pinned growth/sibling writes and
detached merge rollback. All **32 affected release guests** and **four public
package/standalone/CLI laws** pass. Types, formatting and Zig lint pass.

The full gate was scheduled serially without concurrent qualification jobs. Its
final result is **incomplete**, after 180.37s of its 180s budget: 90 native
passes, 63 complete full allocation sweeps, 0 emitted native failures. Phase
records: smoke-build: exit 0; smoke: exit 0; harness: exit 0; native-compile:
exit 0; release-build: exit 0; native-run: exit 124. **Full qualification
remains pending.** Partial execution is not a pass. Complete raw shard output is
archived.

Compiler-only native rebuilds took 8–11s. One final frozen LLVM release took
about six minutes. A separate native-fast Main diagnostic hit its 30s cap and
produced no Wasm; it is explicitly incomplete, was not repeated, and cannot be
compared with LLVM compiler execution. No production native changes followed the
release freeze. Sibling source/assets are preserved.

Next measure per-call owner validation and recursive descriptor/call setup. A
validated internal borrowed descriptor may remove repeated work only where the
source/owner proof excludes invalidating effects. Authority-boundary checks,
prefix behavior and aliases remain requirements. Main representation/output,
subsecond compilation and production packed List emission are separate open
hills.
