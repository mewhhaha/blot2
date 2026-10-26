# Runtime representation, attribution and collection

This batch implements #28, #32, #33, #35 and #36 on top of the `fdfaa89` runtime
repairs. The final release passes correctness and performance qualification. The
earlier batch's measurements remain in
[its historical report](RUNTIME_BOUNDARIES_QUALIFICATION.md).

## Representation and fusion

Numeric collection rows now admit closed, public, reference-free sums with up to
four constructors, sixteen physical words, thirty-two storage nodes, sixty-four
leaves and thirty-two guards. The representation contains a tag and the largest
arm's payload. Inactive words are zeroed; floating-point words keep their exact
bits. Recursive, opaque, reference-bearing, usage-qualified and over-budget
shapes retain their previous representation. Arrays, Lists, static data and the
guest cleanup decoder use the same geometry.

Known bounded producers write these rows directly. Proved scalar consumers
borrow a row and its selected payload; escaping values reconstruct ordinary
owned values. Empty constructors use their immortal representation. This is not
a general unboxed function ABI: frequent owned extraction can increase
allocation traffic, even when the collection itself is smaller. The application
comparison below must be read together with the favorable local kernel costs.

Reconstruction initializes an allocation through its own local before publishing
aliases. Unguarded rows retain that direct local; only conditional arms require
merge locals. The selected-reader regression budget checks this ordering's
effect on existing scalar replacement as well as checking values.

A bounded structural proof recognizes single-use rectangular
generate-record/map-field/flatten pipelines, including forwarding helpers. It
checks resolved operations and consulted bodies, rather than names. Removed work
must be total and non-trapping; a pure call alone is insufficient. Known
constant inner widths are capped at 4,096. Unknown calls, observed
intermediates, ragged shapes, trapping discarded work and exhausted proof
budgets retain the original eager computation. The fused loop preserves lane and
F32 operation order, allocates one final buffer, and falls back on size-overflow
cases.

`array.flatten` now forwards to a checked `@array.flatten` operation using the
existing intrinsic grammar. Ordinary non-fused flattening counts and copies into
one final buffer. The public library signature and immutable snapshot semantics
are unchanged. Retained compilation records every consulted helper body; body
edits, reverts, fresh builds and restarted sessions are compared.

## Executed memory attribution

`--profile-memory` adds counters at final encoding, after semantic optimization.
Ordinary builds contain neither diagnostic counters nor diagnostic storage.
Eight-byte runtime instructions carry compact origin IDs; a detached view owns
the source mapping before transformations. Optimized archive version 42
invalidates old artifacts. Diagnostic builds regenerate fragments where an old
source mapping could otherwise be reused, including trivia-only edits.

Reports contain 23 metrics: allocation count, requested/rounded bytes, frees,
freed requested/rounded bytes, current/peak requested live bytes, retains,
releases, retired objects, copied/filled/read/written bytes, cycle passes,
vertices, edges, reclaimed bytes, admitted candidates, copy operations, reused
allocator blocks and fresh blocks. Allocator block reuse is distinct from
in-place collection reuse. Birth sites own live/freed bytes and visited object
work; the executing context owns copy and ownership operations.

Each row includes UTF-8 source coordinates, a source BLAKE3 pin and up to four
source-emission inline callers. Deeper contexts are explicitly truncated. Later
machine-inlined copies of an origin aggregate; this is not a dynamic call-stack
profiler. Metadata version 2 interns source paths/digests by compilation unit
and writes only present inline frames. The report API expands that compact
encoding back into source rows. Standard Wasm names identify final functions and
runtime helpers.

Source rows plus an explicit unknown row reconcile with totals. Six helper
categories independently reconcile with the same totals; they must not be added
to source totals. Per-site peaks cannot be summed. A 262,144-slot diagnostic
address table tracks allocation births across address reuse. Exhaustion, missing
births and counter overflow mark a report incomplete. Diagnostic reserved bytes
and committed Wasm memory are reported separately.

An exported 256-bit instance fingerprint binds metadata to the prepared IR,
static data and source mapping before counter addresses are read. Reports also
pin the final Wasm SHA-256. The reader can require an expected hash. Traps,
reentry rejection and JSPI resolve/reject paths are tested; suspended calls
retain their attribution context. No host callback runs per counter event.

Use [the scalar runner](../scripts/bench/profile_memory.ts) for import-free
entries, or `memoryProfileReport(bytes, instance.exports)` from
[`compiler/memory_profile.ts`](../compiler/memory_profile.ts) in an application
host. These are diagnostic executions; overhead is measured separately from the
uninstrumented release comparisons.

Direct CLI and dependency-bundle builds forward the same compiler identity and
diagnostic policy. Scalar-only modules publish a valid zero-source-allocation
report. Artifact replay owns inline-context records across generator teardown;
the native replay law exercises an inlined allocating helper under exhaustive
allocation failures.

## Cycle admission and the checked contract

Application attribution exposed a missing propagation step: copied immutable
record payloads, nominal wrappers and Array buffers could lose their proved
acyclic-layout mark. The fix applies the existing whole-layout proof before
publishing a copy. It changes neither the graph algorithm nor collection
thresholds. The
[standalone reduction](../benchmarks/runtime-boundaries/acyclic-updates.blot)
keeps old versions alive while updating 4,096 values four times. It checks both
versions, bounded memory and zero remaining roots/leases. Both codegen tiers
execute zero cycle passes after the fix.

Cycle candidates mean owning objects without a lifetime-stable acyclic proof;
they do not establish a cycle. Zero reclaimed bytes is not authority to skip
collection. Fewer admitted vertices can change the existing scheduler's
threshold and increase pass count while reducing total traversal work. Report
passes, vertices, edges and CPU separately.

Every module carries `blot:collector-contract` metadata. The first certificate,
`no_owning_user_heap_fields_v1`, checks all final emitted non-helper functions,
including initialization and recursive direct-call components. It admits scalar
allocation and literal zero-mask typed allocation, and relies on existing
ownership contracts for a bounded list of administrative helpers. Incoming owned
references, public raw allocation, host imports, mutable static storage,
indirect calls, owning allocation, unknown helpers and exhausted proof budgets
decline. A numeric Array returned through the public heap ABI therefore declines
this first conservative certificate; a local numeric Array folded to a scalar
can qualify.

`--require-collector-free` (client `requireCollectorFree: true`) rejects an
unproved module with the reason and source location. Accepted modules omit
cycle-collection work while retaining reference counting and destruction.
Strict/profile certificates include exact source pins; ordinary certificates
remain embedded in their exact Wasm without preventing harmless trivia reuse.
Strict trivia edits regenerate their source evidence.

Only checked production assembly can omit collector helpers. Unchecked runtime
fixtures retain collection and carry an explicit `unchecked_module` decline; the
real-cycle cohort fixture remains a required counterexample. Replay comparisons
of checked source use checked assembly as well.

The certificate applies to the complete module arena under the documented
ownership ABI: hosts must not mutate raw memory/tables/globals or invoke private
helpers. It does not promise allocation freedom, bounded destruction latency or
constant memory. Ordinary compilation preserves legal State/closure/strong-memo
cycles, suspension and cancellation, with trial-deletion collection. No new
syntax or cycle/memo policy is imposed.

## Qualification and measurements

The full gate passes: 2,606 native tests with exhaustive allocation failures,
1,687 executed release-Wasm tests, 48 protocol smoke tests and 57 tooling tests.
Native compilation uses Zig 0.17.0, Safe and `-Dllvm=false`; the measured
release uses LLVM. The native runner records 1,700 full fault sweeps. Zig lint
checks 531 source files and its fixture with zero findings. The bundled CLI also
builds and executes a scalar program with both strict collection and profiling
enabled.

Final candidate SHA-256:
`fd2119f5528cb164131e1156d35ba97c434393647f1b326ae5aa154db137d923`. The baseline
is `fdfaa89`, compiler SHA-256
`b127325a76a2990b04aed39434c8a692483888af4c1b69dc07d62d645a9aeabf`. The cycle
control disables only the two copy-mark propagation steps, with compiler SHA-256
`7ae44f3228cfb453d062400bf791274592bc78aae0e1e0d9a5da1842d5cc5bb6`.

### Public release kernels

All 28 checksum and ownership budgets pass in Deno 2.9.7/V8 15.0.245.2-rusty,
Wasmtime 50.0.1 and Firefox 157.0. The same pinned Wasm runs in each engine.
Results below are median milliseconds per invocation, before → after, with 31
alternating samples. Deno and Wasmtime batch five invocations; Firefox
calibrates equal batches for both sides to avoid clock quantization. Wasmtime
includes Python host-call overhead, so absolute times are not an engine-only
comparison. No external Wasm optimizer is applied.

| Kernel                            |        Deno/V8 ms |       Wasmtime ms |        Firefox ms | Retirements |
| --------------------------------- | ----------------: | ----------------: | ----------------: | ----------: |
| Optional numeric rows, 2,000      | 0.22375 → 0.00344 | 0.24602 → 0.03685 | 0.18405 → 0.00503 |   6,001 → 1 |
| Record/map/flatten, 2,000 × 24    | 0.74875 → 0.27780 | 0.80861 → 0.44006 | 0.60040 → 0.23560 |   6,005 → 1 |
| Selected reader, 2,000 rows × 100 | 1.10894 → 1.11234 | 2.15436 → 2.15424 | 1.18364 → 1.17455 |       1 → 1 |

Three alternating fresh builds take median 13.29 → 13.38 ms including native
process startup and opening. Combined Wasm size is 24,160 → 27,850 bytes
(+15.3%). This is a local compile-cost screen, not an ordinary-edit latency
claim. The baseline uses its original standard library. Both codegen tiers have
separate semantic tests for mixed/inactive variants, snapshots, F32 bits,
effects/traps and retained/restarted compilation.

The standalone retained-copy reduction executes 65 passes and visits 47,559
vertices with either the baseline or the cycle control, versus zero in the
candidate. Median Deno time is 8.316 ms baseline, 8.364 ms control and 7.601 ms
candidate: the isolated copy-proof change reduces time by 9.1%. All three have
identical retain/release/retirement traffic and stable 196,608-byte Wasm
capacity, with no roots or leases remaining after calls.

### Application runtime and the cycle control

Two frozen gdev scenes run in Node 24.12.0/V8 13.6.233.17-node.37, with 600
warmup and 600 measured frames per process, across three counterbalanced rounds.
All eighteen replays preserve the exact 1,200-frame witness and final save. Raw
optimized Wasm has no diagnostic instrumentation and no external `wasm-opt`
pass. The same 1 kHz inspector sampler runs on all sides.

The following medians are over three process runs. Guest time is the mean of 600
measured frames; process CPU includes startup, restore, all 1,200 frames, host
validation, witness hashing and inspector overhead. They have different scopes
and should not be subtracted from each other.

| Scene and measure          | Baseline | Candidate | Candidate without copy-proof fix |
| -------------------------- | -------: | --------: | -------------------------------: |
| Colony guest ms/frame      |   13.687 |    13.598 |                           15.860 |
| Colony process CPU seconds |   17.555 |    17.670 |                           20.203 |
| Piles guest ms/frame       |   19.055 |    18.280 |                           21.615 |
| Piles process CPU seconds  |   25.389 |    24.311 |                           28.472 |

The isolated copy-proof repair lowers process CPU by 12.5% and 14.6%, with
identical allocation/ownership traffic to its control. In the measured 600-frame
windows, visited vertices fall 37,598,485 → 2,133,036 (94.3%) and 60,569,923 →
2,310,721 (96.2%). Edges fall 50,693,548 → 3,234,785 and 91,863,124 → 3,501,409.
Passes fall 63,265 → 56,554 in the colony but increase 52,251 → 59,085 in the
piles scene because the unchanged scheduler responds to the smaller admitted
population. Both still perform much less traversal work.

The combined batch has a smaller effect against the prior compiler: colony CPU
is effectively flat (+0.7% in this screen), while piles CPU falls 4.2%. Guest
means fall 0.6% and 4.1%. Optional values crossing owned result boundaries
increase retirements from 69,463,416 → 99,943,537 and 71,918,352 → 102,492,881.
The profiler identifies that residual representation cost; the local
optional-array benchmark is not a universal Maybe speedup. Three runs are a
local screen, not a confidence bound or a claim about shipping external-O3
output.

All sides have zero committed-memory growth over their last 100 measured frames.
Candidate maximum Wasm capacity is 6,029,312 bytes for the colony and 8,388,608
for piles, versus baseline 6,225,920 and 8,585,216. Real-cycle, strong-memo,
suspension, trap and cancellation laws also pass the full gate. Zero reclaimed
bytes in these scenes is not used as authority to suppress collection.

### Application compilation cost

Three alternating fresh processes compile the same frozen gdev source and native
assets with retained/restart caches disabled and no profiling. The screen uses
240 modules, so it is not the older 189-module compile fixture. Filesystem
caches are warm. Median costs are:

| Measure                           |        Baseline |       Candidate |
| --------------------------------- | --------------: | --------------: |
| Native build wall time            |        10.072 s |        10.100 s |
| Project open plus build           |        10.077 s |        10.105 s |
| Compiler process CPU during build |        11.040 s |        11.080 s |
| Compiler peak RSS                 |     778,364 KiB |     778,736 KiB |
| Raw optimized Wasm                | 7,207,519 bytes | 7,497,884 bytes |

The 0.3% wall difference is below what this small shared-host screen can
establish as a meaningful change. Wasm grows 4.0%. CPU covers compiler threads
but excludes process startup/project opening; peak RSS covers the native
compiler, not its Deno client. This batch does not claim a faster ordinary edit
or a sub-second application build.

### Diagnostic overhead

Profiling is deliberately separate from the scored release measurements. Four
public kernels, measured in alternating 31 × 5 batches, retain identical
production counters and exact results. Profiled/unprofiled runtime ratios are
4.75× for selected reads, 3.86× for reference scratch, 4.21× for optional
generation and 2.79× for the pipeline. The combined module grows from 27,850 to
148,481 bytes with instrumentation. These figures are workload-specific; they do
not predict full-game profiling overhead.

### Executed application attribution

The final diagnostic compiler reports complete/status-zero accounting for two
frozen gdev scenes, each replayed for 20 frames (four warmup and sixteen
measured). These totals cover initialization, restore, all twenty frames and
teardown. Timing from these instrumented runs is not scored.

| Scene       | Allocations | Requested bytes, cumulative | Peak live requested bytes | Copied bytes |
| ----------- | ----------: | --------------------------: | ------------------------: | -----------: |
| Busy colony |   2,553,397 |                 135,686,340 |                   830,388 |   17,258,092 |
| 2,000 piles |   3,313,395 |               1,073,019,520 |                 1,998,320 |  940,132,912 |

Both reports finish at 4,076 live requested bytes, attributed to administrative
runtime storage. Diagnostic reservations (about 10.3 MB) and total committed
Wasm capacity are separate from these program live-byte counts. Requested bytes
exclude allocator headers and fragmentation.

`ink/spatial/point_grid.blot:32` accounts for 6,037,680 copied bytes in the
colony and 880,384,952 in the piles scene. Remaining collection visits
concentrate in `ink/map.blot:73` and `:62`. The largest allocation site is
`ink/ecs.blot:264` (433,793 allocations): extracting a packed optional component
through an owned function result reconstructs its value. The new collection
representation does not remove that ABI boundary. This is a concrete remaining
cost, not evidence of a memory leak.

Disabling only the two acyclic-copy propagation steps yields identical
allocation, copy and peak-live totals, but visits 411,317 rather than 40,076
vertices in the colony and 1,948,430 rather than 56,140 in the piles scene.
Before the fix, the largest visit sites include `game/salt.blot:1774`,
`ink/render.blot:211`, `game/kites.blot:196` and `game/robots.blot:510`. The
uninstrumented CPU comparison below separately tests this causal reduction.

The public selected-reader (#29) profile attributes its single final allocation
to `std/array.blot` generation. The reference-scratch (#34) profile identifies
512 captured closures, their array and the constructing callback; it executes
zero copy bytes. Optional generation and the fused pipeline likewise allocate
one final program array. Each report separately records the administrative root
allocation, and source rows plus unknown traffic reconcile with runtime totals.

## Evidence and reproduction

[The complete result JSON](../benchmarks/results/runtime-memory-2026-10-26.json)
contains all public timing samples, compiler/source/Wasm pins, application frame
samples and process CPU, compile screens, source-attribution summaries, and
separate instrumentation overhead.

[The portable evidence archive](measurements/runtime-memory-2026-10-26.tar.gz)
contains 115 files: exact public Wasm, source fixtures, runners, application
configs, all nonzero diagnostic source rows, native inventory/shards, release
logs and reproduction instructions. Its 114 payload hashes were verified.
Archive SHA-256:
`edf4e42b81eea0c2b6c897c40b36561cf5d108ef400b94fa2c717e2cf179b3b6`. The private
application sources/assets and large application Wasm are not redistributed;
their required input locations and hashes are recorded.
