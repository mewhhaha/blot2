# Addressed private inputs — 2026-11-04

Wide private arguments can now travel as immutable bundles. Nested helpers may
forward a checked input range by address instead of unpacking and repacking its
leaves. Results have separate storage. The semantic Value tree, owner graph,
callback/type evidence and ordered access replay remain complete. ABI 8/session
protocol 2 and sibling sources/assets remain unchanged.

[Machine-readable evidence](2026-11-04-addressed-inputs.json) pins compiler,
source, workload, samples, controls and incomplete qualification. The source
baseline is Blot `b69ecfe`, Gdev `38af070`, with the same Ink/Pen checkouts.

## Admission and lifetime

A borrowed-input preference has its own private cache alternative. Keys never
contain runtime addresses or caller local IDs. Ordinary callers retain the new
transport only when completed input plus required result-pointer demand exceeds
512 words, or at least 16 input words forward to nested helpers. Sparse calls
rebuild with the ordinary ABI. A bounded negative memo avoids repeated optional
probes after executable rollback.

Complete-body proofs reject writes to bundle words/pointers, hidden identities
and instruction coordinates. One/two actual reads load at use; frequent reads
retain one entry snapshot. Logical input/result alias ordinals remain complete.
Exact contiguous input-local ranges propagate the nested helper's physical
demand back to the caller before publication.

Other arguments serialize snapshots. Reuse requires the complete ordered local
list and a stored-demand superset. Local writes, every control boundary, runtime
close/rewind and successful outlining invalidate the cache. Retained snapshots
precede result scratch marks and stay under ordinary enclosing-scope cleanup.
Each generated function retains at most eight packets/32 KiB including headers;
later snapshots are reclaimed after their call. Array payload writes remain
visible through their descriptors; rebinding preserves old record snapshots.

## Controls and rejected rollout

The broad rollout used bundles for every argument of at least 64 logical words.
It grew Main **10,241,074 → 10,374,921B**, with essentially flat paired compile
medians **5.420 → 5.401s** in that separate host round. It generated 13,965
snapshot stores, 4,443 input loads and no snapshot-cache hits. This policy is
rejected; its binary and three raw pairs remain pinned.

The adaptive policy reduces Main to 1,079 snapshot stores, 1,410 input loads,
1,177 forwarded words and zero cache hits. It publishes 38 addressed helpers at
42 call sites. These are compiler work counts, not runtime invocation counts.
The world/editor binary returns exactly to its baseline bytes. Main's remaining
size/latency tradeoff is reported below; the capture result is not extrapolated
to the game.

Main already made **zero packed helper calls** at the preceding checkpoint. The
old diagnosis that private packet serialization dominated Main was incorrect:
the capture regression exposed its own interface costs. Most game transport is
already direct, so its remaining local/global copying needs a different lever.

## Final measurements

Three fresh uncached pairs use seeded side order with startup included and no
other deliberate benchmark work. Only the compiler changes.

| Metric                    |     Before |      After |
| ------------------------- | ---------: | ---------: |
| Compile median            |     6.334s |     6.235s |
| Median absolute deviation |     0.092s |     0.016s |
| Main Wasm bytes           | 10,241,074 | 10,253,029 |
| Declared locals           |    352,383 |    355,179 |
| Wasm functions            |      9,437 |      9,440 |

Main grows **11,955B (0.12%)**. Individual pairs change by -115, +8 and -300ms:
this is effectively flat latency, not a robust speedup claim. The previous
round's 5.28s is not this round's baseline; do not compare different shared-host
rounds. Sub-five-second, subsecond and 1–2MB goals remain unmet.

A separate same-artifact profile records backend **4.645s**, checking
**0.516s**, lowering **0.131s** and validation **0.107s**. Backend allocation
requests total **5.29GB cumulatively**; maximum process RSS is **1,104,988KiB**.
Do not add overlapping timing families or treat requested bytes as peak memory.
Local/global instructions still occupy **6,697,626B**.

The 32-shape capture matrix uses three fresh repetitions and executes 384 U32
checks per compiler. Its compiler, harness, source and Wasm hashes are pinned;
actual Wasm artifacts are now retained by the benchmark runner.

| Capture control                                        | Before bytes | After bytes |
| ------------------------------------------------------ | -----------: | ----------: |
| Shared width128/four captures/eight calls/all fields   |       50,307 |      36,141 |
| Distinct width128/four captures/eight calls/all fields |      263,521 |      97,002 |
| Shared width128/four captures/eight calls/one field    |       17,607 |      17,607 |
| Distinct width128/four captures/eight calls/one field  |       63,300 |      63,300 |
| Width32/one capture/one call/all fields                |        9,564 |      10,245 |

The worst repeated distinct case shrinks **63.2%**; repeated shared captures
shrink **28.2%**. Two of 32 shapes grow **7.1%**: shared/distinct labels of the
same single-capture, single-call width32 workload. Retain that single-use
regression; the policy does not yet count caller reuse before choosing
transport. Micro compile timings are descriptive, not a randomized paired speed
claim.

All five numeric Blot kernels are byte-identical to the preceding checkpoint.
Fresh README charts rerun the same Goose/V8 profiles and checksums; no numeric
runtime improvement is claimed. Two recursive Blot sorts and original F64 remain
unsupported. The world/editor, hand and renderer binaries are byte-identical;
seven editor assertions, 160 hand assertions and seven renderer streams match.
The exact final Main passes the original budgets in a headless NVIDIA frame; its
inspected PNG and guest trace match the baseline byte for byte. See
[frame evidence](../../../../tasks/storage-handoff-evidence/2026-11-04-addressed-inputs-frame.json).
Broader gameplay/software-adapter coverage and the normal Pen source bridge's
missing inferenceBudget setting remain pending.

## Qualification and next lever

The new executed witnesses cover exact/distinct captures, partial masks followed
by wider masks, branch-only initialization, zero/changing loops, old closure
snapshots, owner payload mutation, capped retention, scratch rewind, fresh/input
results, exact F32 bits, repeated exports and borrowed escape rejection. The
same helper is reached through direct and borrowed callers in both construction
orders; parent economic rejection rolls back a completed borrowed child.

All 2,976 native laws compile without LLVM. The affected union passes 412 native
laws with sampled faults. Eight focused laws pass full-fault mode, including
three exhaustive allocation sweeps. The final development family passes 245
native laws and its guest suite, formatting, type checks and zero Zig lint
findings. Release guests pass 300/302; both failures reproduce on the frozen
compiler: summary-job ECS export and optimized iter.take(0) allocation. Full
qualification remains pending. The full gate passes 49 smoke checks and the
harness, then stops at its 180s total budget after 101 native passes with zero
failures/leaks/logged errors. It is incomplete, not a pass.

The next Main experiment is copy coalescing across structured control.
`wasm_copy_coalesce.zig` currently discards every alias at every
block/branch/end. Measure copies rejected solely for crossing control, then
preserve dominating immutable aliases across blocks/branches while retaining
source-version checks, branch-local exclusion, default-zero behavior and
loop/jump barriers. The existing private outline capture/replay gives short
iterations. Memory-backed banks remain a larger, unproven alternative:
individual loads/stores grow and frequency-sorted bank slots disrupt contiguous
bulk copies.
