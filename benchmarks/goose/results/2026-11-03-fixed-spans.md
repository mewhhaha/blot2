# Fixed spans and aggregate transport

Private helpers now validate fixed scalar-array descriptors at first use and
retain their checked length and stride. Each access still checks unsigned
bounds. Fresh arrays refresh their length snapshot on every creation; local
grow/freeze arrays, merged descriptors and host boundaries retain the ordinary
path. Owner, borrow, escape, variant and effect checks remain.

Five fresh matched pairs compare the preceding release with this candidate.
Workloads, checksums and Node 24.22.1 / V8 13.6.233.17-node.58 are unchanged.
Preparation and warmup stay outside the kernel clock. All samples pass.
[Exact observations and fingerprints](2026-11-03-fixed-spans.json) accompany the
[preceding checkpoint](2026-11-03-runtime-hills.md).

| Kernel                 | Previous (ms) | Current (ms) | Median paired speedup |
| ---------------------- | ------------: | -----------: | --------------------: |
| Fannkuch               |        179.50 |        14.37 |                12.49x |
| CRC32                  |        129.94 |       109.97 |                 1.19x |
| Custom eight-lane hash |        955.26 |       101.75 |                 9.40x |

A separate five-pair comparison uses the original frozen Goose direct backend.
Its compiler, source corpus and every emitted Goose artifact match the preceding
comparison exactly. Compilation uses five fresh uncached builds per cell, with
profiling disabled. Times include driver startup.

| Kernel                 | Cold build Blot / Goose (ms) | Wasm Blot / Goose (bytes) | Kernel Blot / Goose (ms) |
| ---------------------- | ---------------------------: | ------------------------: | -----------------------: |
| Fannkuch               |                70.66 / 88.04 |             5,973 / 4,067 |            14.74 / 15.58 |
| CRC32                  |                47.93 / 73.73 |             5,145 / 3,309 |           110.79 / 14.64 |
| Custom eight-lane hash |                50.85 / 86.87 |             6,092 / 6,788 |           105.88 / 15.35 |

Fannkuch now runs about as fast as Goose in this workload. CRC32 and custom hash
still have substantial gaps. The README chart uses matched before/after Blot
medians and Goose from the separate comparison, with a linear zero-based axis.

This covers three of seven adapted tasks and the 50-task catalog is not fully
ported. V8 is the only measured engine. Hash buffers contain identical byte
values stored as Blot U32 versus Goose U8, with four times the element payload.
ABI costs also differ. The eight-lane hash is not cryptographic SHA-256.

All unchanged official production workloads complete within the 30-second
process cap with their official checksums. These single completion runs are not
a production performance ranking.

| Production case        | Whole process | Kernel |
| ---------------------- | ------------: | -----: |
| Fannkuch               |         1.64s |  1.23s |
| CRC32                  |         5.28s |  4.15s |
| Custom eight-lane hash |         2.53s |  1.93s |

The size changes share invariant fixed-array descriptors and unchanged named
nested record fields across loops. The existing all-exit identity proof and
storage checks remain. Private outline banks also give frequently encoded slots
shorter ULEB indices, retaining deterministic order for equal frequencies. A
replay of the preceding captured IR saves 83,407 bytes through index ordering
alone. The final Main saves 85,891 operand bytes through that ordering; this
count overlaps the complete size result below.

Actual Gdev Main shrinks **12,550,610 → 12,476,667 bytes**, a reduction of
73,943B (0.59%). Local/global instructions still occupy **8,254,281 bytes**.
Declared locals fall 413,749 → 413,352; mutable globals fall 56,176 → 56,144.
The representation remains the dominant size problem.

Three fresh matched compilation pairs have medians **5.987 → 6.140 seconds**
(previous/current), an observed 2.6% increase. Pair differences are +111, -68
and +175ms. This batch improves runtime and slightly reduces Main size; it does
not improve Gdev compile latency. The five-second, subsecond and 1–2MB targets
remain unmet. Every repeated Wasm artifact matches its pinned candidate hash.

World/editor checks pass 7/0 and hand checks 160/0 in both sync and async modes.
Seven renderer streams remain exactly equal. Their output sizes regress: 480,499
→ 488,909B, 197,999 → 198,167B and 91,157 → 91,406B respectively. Their profiled
compile times were collected during qualification and establish no latency
comparison.

The rebuilt, unchanged Pen source accepts ABI 8. The final candidate passes all
one-frame runner checks on the NVIDIA headless path; its inspected PNG and guest
trace are byte-identical to baseline. See the
[frame evidence](../../evidence/integration/2026-11-03-fixed-spans-frame.json)
and
[PNG](../../evidence/integration/2026-11-03-fixed-spans-frame.png).
The default software adapter is unavailable and a SwiftShader attempt timed out;
those paths remain unqualified. An initially blank image preview was resolved by
original-detail inspection and byte comparison. No rendering defect was found.

Qualification:

- All 2,937 native laws compile without LLVM. The affected family passes 201
  laws and 192 guests in 60.04s, including sampled allocation faults and zero
  Zig lint findings. Final LLVM passes all 192 affected guests.
- Nine focused laws pass exhaustive allocation-failure checks without leaks.
  Regressions cover fresh lengths, repeated helper calls, empty/conditional
  reads, loop-created arrays, bounds-before-RHS order and nested carry exits.
- Explicit Array-from-List conversion now applies the existing guarded private
  append proof to the consumed block. The prior List/chunk failure passes
  source, dependency-bundle and retained-edit checks. Owner checks are intact.
- The full gate passes 49 smoke and 57 harness tests. A generated TypeScript
  fixture's invalid `and`/`or` operators were repaired; its seven scheduler
  regressions pass.
- Broad exhaustive native execution was stopped after 355.79s to bound this
  iteration: 445 completed laws, 298 full sweeps, zero failures/leaks/logged
  errors. This is **incomplete**, and remaining native laws and the whole guest
  suite are not qualified.

CRC32 already uses fixed spans. Source-only controls show that primitive
inlining gives no gain; unrolling alone gives little. A branchless recurrence
improves roughly 3x, and independent basis columns approach Goose. These are
experiments using the native development compiler, with full checksums and
10,259 scalar equivalence controls. No tracked benchmark algorithm changed. A
bounded, proved unsigned shift/XOR recurrence fold is a useful next hill.

For Main, Astra's review found that the 512-word selector already chooses a
one-pointer buffered ABI for wide calls; machine and outline-key declines are
zero. Widening those limits is not useful. Classify the **2,009 completed-plan
rollbacks and 181,762 discarded emitted expressions** next. Fresh fixed-array
returns currently force caller expansion and offer a concrete boundary to
measure before changing the larger aggregate representation.
