# Shared compiler hills — 2026-11-04

CRC32 is **6.2x faster**, Gdev is **155,377B smaller**, and the evaluated fold
probes allocate zero bytes per invocation. Gdev compilation regresses **2.5%**;
this is not a Main compile-speed win. All original benchmark ports are
unchanged.

[Machine-readable evidence](2026-11-04-shared-hills.json) pins compiler, source,
Wasm, toolchain, samples, controls and qualification. Release compiler SHA256:
`4f0120a091870fd45722f4d878a9699f97843e4e40dd830e6583e06af07b09dd`. Baseline
compiler: `f90931ef17ec2b143f880db68253d54392ec4f19a44e9eb58ff09b587d6d967b`.
ABI 8, session protocol 2, saved schema 26, sibling source/assets and original
integration memory budgets remain unchanged.

## CRC: remove serial bit rounds

The compiler proves an exact affine transform for a fixed range of one through
eight rounds over one U32 carry. Normal source and ownership checks finish
first. A bounded interpreter admits only pure scalar bit operations, closed
helpers and affine branches; effects, memory, iterator use, other live carries,
arithmetic traps, nonlinear operations and escaping control keep the original
loop. Composed columns emit a balanced XOR tree. Scanned/pending/semantic
coordinates block replacement, and output is prepared before modifying the
machine body.

The unchanged CRC benchmark now uses one composed eight-round transform. Five
fresh shuffled release-Wasm pairs give **110.33 → 17.78ms (6.21x)**, including
four measured million-byte iterations after one kernel warmup. Wasm grows
**5,033 → 5,098B (+65B)**. Against Goose, five fresh matched pairs measure
**18.06 / 13.55ms**, a paired **1.33x** gap. The preceding gap was 8.10x. These
are separate measurement rounds; direct before/after claims use the Blot pairs,
not ratios of old and new Goose medians.

Private diagnostic controls explain the lever: original 114.12ms, branchless
round loop 34.68ms, eight explicitly unrolled branched rounds 104.22ms, composed
basis 17.96ms. All four use the same experimental compiler and pass checksums;
they are causal controls, not replacement benchmark scores. The selected
optimization is generic across coefficients and input words, with basis/random
checks, count boundaries, helper edits and negative cases in both codegen tiers.

## Main: preserve dominating snapshots

Copy forwarding now follows structured scopes. Incoming snapshots survive
branches; arm-local definitions cannot escape. Source versions stay monotonic.
Unwritten sources and unique writes already encountered outside every active
loop remain stable through later loops/jumps. Helpers inherit caller scope and
loop depth, and cannot return early or branch to their function label. Traps and
root returns do not invalidate a continuing path. Every original read must still
be proved; retained intermediate snapshots and default-zero behavior remain.

A private capture of actual Main IR passes the independent copy-input audit:

| Metric                |    Before |     After |
| --------------------- | --------: | --------: |
| Copies removed        |    79,227 |    93,704 |
| Reads forwarded       |    27,314 |    43,128 |
| Outline bank globals  |    36,863 |    36,548 |
| Prepared locals       |   546,468 |   538,476 |
| Prepared instructions | 4,180,982 | 4,152,344 |

Replay stays around three seconds; these diagnostic clocks are not a paired
whole-compiler result. Promoting branch-free nested block scopes added no
savings on this capture, so that extra implementation was removed.

Three fresh uncached Gdev pairs, seeded side order and no deliberate concurrent
measurement work, give:

| Metric                    |     Before |      After |
| ------------------------- | ---------: | ---------: |
| Compile median            |     5.283s |     5.414s |
| Median absolute deviation |     0.027s |     0.013s |
| Main bytes                | 10,253,029 | 10,097,652 |
| Declared locals           |    355,179 |    336,753 |
| Wasm functions            |      9,440 |      9,440 |

Main shrinks **1.52%**; compile time rises **2.49%**, with paired changes
+112/+144/+105ms. Keep that regression visible. A separate exact-artifact
profile records backend **4.439s**, checking **0.518s**, lowering **0.124s**,
validation **0.102s**, cumulative backend allocation requests **5.315GB**, and
peak process RSS **1,107,548KiB**. Requested bytes are not peak memory.
Overlapping timing families do not add. Main admits zero bit recurrences.

The final Main SHA256 is
`fcaf7e05e434d6647f1b53b56bf1c39d95fe02e92a1933b8b6fdca3bbc0faa3f`. A fresh
NVIDIA frame passes the original budgets; its inspected PNG and guest trace
match the baseline exactly. See
[frame evidence](../../../tasks/storage-handoff-evidence/2026-11-04-shared-hills-frame.json).
Broader gameplay/software-adapter qualification remains pending.

## Allocation and gate repairs

Statically selected/imported, saturated scalar primitive aliases now use the
checked direct scalar ABI rather than materializing curried environments. Full
semantic arrows, exact arity and provider/result layout remain checked; partial
and unsupported values retain closures.

The same observer, source and release compiler pair measure rounded heap traffic
over 100 calls after warmup:

| Probe         | Before bytes | After bytes |
| ------------- | -----------: | ----------: |
| take(0)       |       19,200 |           0 |
| range(4,096)  |   78,643,200 |           0 |
| map(4,096)    |  117,964,800 |           0 |
| filter(4,096) |  137,625,600 |           0 |
| take(4,096)   |   78,662,400 |           0 |

The obsolete source-only partial-application diagnostic expectation now matches
the language guide, while retaining a literal-only arity negative. The principal
recorder fixture excludes unrelated ECS runtime exports and strengthens
persisted nonempty/call-proof checks. It does not establish ECS request-handler
execution; that backend coverage remains separate.

## Controls and qualification

All seven adapted Goose pairs pass checksum and observable revision checks at
official test and bounded production sizes. Each has five fresh builds and five
warmed runtime pairs in Node 24.22.1 / V8 13.6.233.17-node.58. Original F64 and
the other 43 catalog tasks remain outside paired coverage. Byte buffers still
use U32 in Blot and U8 in Goose; custom Hash::SHA256 is not cryptographic
SHA-256.

Other runtime changes are not attributed to the compiler. Sieve, merge sort and
quicksort remain byte-identical; the Sieve timing control nevertheless moves
7.5% in the separate before/after round. Custom hash remains roughly 7x slower
than Goose; its periodic eight-lane SIMD is a different hill.

Tiny scalar-wrapper inlining was tested and rejected: five pairs across all
seven kernels showed no runtime gain despite removing CRC wrapper calls, while
adding 93/125/245B to CRC/hash/F32 Mandelbrot. Its code/tests were removed; the
[implementation patch](2026-11-04-rejected-scalar-inline.patch), compiler,
artifacts and raw measurements remain pinned as rejected evidence. Its
experimental compiler also includes in-progress coalescer/alias changes; this
pilot does not isolate scalar inlining as a causal benchmark.

- All 2,996 native laws compile without LLVM; 433 affected laws pass sampled
  allocation faults. Twenty-six focused laws pass full-fault mode with 33
  exhaustive sweeps and no leaks/logged errors.
- The development family passes 266 native laws / 248 guest tests in 67.9s, plus
  formatting, types and zero Zig lint findings.
- All 328 affected guests pass on the final release compiler, including the
  formerly failing allocation/principal cases and new recurrence checks.
- The full gate passes smoke/harness and 410 native laws with no failures, then
  reaches its 180s budget. **Full qualification remains pending.**

The next substantial Main lever needs source-attributed representation evidence:
creation-backed immutable `FrameAccess` records versus shared semantic shapes
and transitive field demand. Remaining local/global instructions occupy 6.54MB,
but adjacent transfers account for only 1.50MB. Reaching 1–2MB requires removing
whole representation work, beyond deleting copies. Sub-five-second and subsecond
Main compilation remain unmet.
