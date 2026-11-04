# Scalar array loops — 2026-11-04

Merge sort is **1.64x faster**, quicksort **1.35x**, and Sieve **2.43x** against
the preceding Blot release. Custom hash regresses about **4–5%**. Main saves
another **47,689B**; its compile time remains around **5.55s**. Benchmark ports
and sorting algorithms are unchanged.

[Machine-readable evidence](2026-11-04-sort-hills.json) pins sources, compilers,
Wasm, toolchains, samples, controls and incomplete qualification. Final compiler
SHA256: `dbb034d016d09d6b8a634ff97fbfac705915692848694658ec340f6175b169a7`. The
baseline is `4f0120a091870fd45722f4d878a9699f97843e4e40dd830e6583e06af07b09dd`.
ABI 8, session protocol 2, schema 26 and original integration budgets remain.

## What changed

Private fixed scalar-array descriptors still validate lazily at first actual
use. A small incremental scope proof removes later readiness guards dominated by
that validation. Arm, block and loop facts cannot escape their scope; outlining,
rewrites, rollback and function changes invalidate them. Scalar layout provides
a constant four-byte stride. Bounds checks remain.

After normal source, owner, effect and backedge checking, exact indexed
copy/literal-fill loops may use bulk memory operations. Full-range bounds,
stride, nonwrapping addresses and safe forward-copy overlap guard the fast path.
Otherwise the original scalar loop runs, preserving valid-prefix writes before a
later bounds trap. Empty/reversed ranges avoid validation; fewer than 16
elements retain scalar execution. Arbitrary literal fills preserve exact bits.
The proof is bounded to 32 carries and a 4,096-instruction canonical loop
suffix; pending outline/semantic coordinates reject replacement. Publication
reserves all output capacity first.

Astra reviewed the implementation and found no correctness blocker. Suggested
post-loop and skipped-read witnesses were added. No language feature was cut.

## Fresh release pairs

Five shuffled same-engine pairs use unchanged bounded workloads, one process
warmup and checked results. Sorts perform four measured 400,000-element runs
after one kernel warmup. Node is 24.22.1 / V8 13.6.233.17-node.58.

| Kernel         | Before (ms) | After (ms) | Median paired speedup |
| -------------- | ----------: | ---------: | --------------------: |
| Merge sort     |      382.89 |     234.48 |                1.641x |
| Quicksort      |      163.42 |     121.82 |                1.352x |
| Sieve          |       62.47 |      25.70 |                2.428x |
| CRC32          |       17.97 |      17.86 |                1.003x |
| Custom hash    |       98.46 |     102.41 |                0.954x |
| Fannkuch       |       14.17 |      14.12 |                0.983x |
| Mandelbrot F32 |       74.28 |      73.99 |                1.007x |

Custom hash's median rises 4.0%; its median paired slowdown is 4.8%. Do not
attribute this to a particular engine optimization without profiling. CRC32,
Fannkuch and Mandelbrot establish no material runtime gain. Fannkuch includes a
noisy 19.67ms candidate sample; retain dispersion and paired statistics.

A separate three-way development-compiler pilot isolates the broad levers: merge
370.74 → 281.68 → 229.42ms, quick 160.96 → 120.81 → 119.87ms for baseline,
guards/stride, then bulk lowering. Most quicksort gain comes from guards/stride;
bulk lowering helps merge. These are diagnostic clocks. Final release sort
binaries match the bulk pilot byte for byte; headline wins use the fresh release
pairs above.

Merge Wasm grows **6,741 → 6,991B (+250B)**; quicksort shrinks **6,244 → 6,153B
(-91B)**. Fresh cold process medians are **50.94 / 56.28ms**. This is not a
before/after cold-build comparison.

## Current Goose reference

Goose advanced independently from `95146ea8` to `0d1715ce`. Its compiler changes
from `353a3f1b…` to `8c09c1a6…`, and its emitted programs changed.
Cross-checkpoint Goose gaps therefore cannot establish a Blot-only win. The
frozen Blot baseline above supplies that comparison.

Five fresh pairs against the newer Goose give:

| Kernel      | Blot / Goose (ms) | Median paired ratio |
| ----------- | ----------------: | ------------------: |
| Merge sort  |   230.65 / 115.41 |              2.001x |
| Quicksort   |   120.25 / 110.58 |              1.106x |
| Sieve       |     25.26 / 11.01 |              2.305x |
| CRC32       |     17.85 / 13.45 |              1.321x |
| Custom hash |    102.25 / 13.95 |              7.368x |

All seven adapted pairs pass official test and bounded checksums and observable
revision checks. Fannkuch stays near parity; F32 Mandelbrot remains about 1.87x
slower. Original F64 and the other 43 catalog tasks remain outside paired
coverage. Byte storage still differs: Blot U32 versus Goose U8. Custom hash is
not cryptographic SHA-256. README charts use this fresh comparison.

## Main control and qualification

Three fresh uncached source pairs, shuffled side order and no deliberate
concurrent measurement work, give **5.555 → 5.545s**; MAD is **93 / 10ms**.
Per-pair changes are **+2 / -93 / -10ms**. This establishes no compile-speed
win. Main shrinks **10,097,652 → 10,049,963B (-0.47%)**; declared locals fall
**336,753 → 335,682**, with 9,440 functions unchanged. Local/global instructions
still occupy **6,510,841B**. Main admits ten bulk copies and three fills.

A separate exact-artifact profile records backend **4.430s**, checking
**0.500s**, lowering **0.124s**, validation **0.102s**, cumulative backend
requests **5.324GB**, and peak process RSS **1,110,332KiB**. Requested bytes are
not peak memory; overlapping timing families do not add. Scoped backend engine
subtimers remain unavailable.

Main SHA256: `8a5bc671b85bba52b8989abe4c2165e26d1e379c659e3db9666dd60ad7e5127b`.
A fresh inspected NVIDIA frame passes original budgets and matches the preceding
PNG/trace byte for byte; see
[frame evidence](../../evidence/integration/2026-11-04-sort-hills-frame.json).
Sibling source/assets remain Gdev `38af070`, Ink `ccaf08f`, Pen `d159492`.
Broader gameplay/software-adapter qualification and Pen's normal source bridge
remain pending.

- All 3,001 native laws compile without LLVM. All 438 affected native laws pass
  sampled allocation faults on the final native binary. Five focused laws pass
  full-fault mode, including three exhaustive sweeps, without leaks/errors.
- The development family passes 271 native laws / 250 guests in 76.3s. All 330
  affected guests pass on the final release compiler, including aliases,
  same-array reads after bulk loops, skipped reads, exact float bits, prefix
  traps and RHS ordering. Formatting, types and Zig lint pass.
- The full gate passes smoke/harness and 282 native laws without failures, then
  reaches its 180s budget. **Full qualification remains pending.**

Sub-five-second/subsecond Main compilation and 1–2MB output remain unmet. Main
still needs representation work beyond copies. Sorts retain bounds checks,
recursive descriptor parameters and repeated loads; custom hash's eight-lane
SIMD remains a separate hill.
