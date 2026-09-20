# Compiler performance

The latest [concurrency review and 1–8-core report](CONCURRENCY.md) records the
stock-Bend CPU implementation, physical-core-pinned comparisons,
retained-process controls and remaining bottlenecks. Its baseline includes the
earlier follow-up work after `f55334d`. The sections below preserve the older
measurements.

## Concurrency-compatible lowering and wider forks (2026-09-20)

The compiler now lowers independent declarations in balanced batches, after name
collection. Leaves contain at most four declarations. Structural validation
precedes the forks, semantic failures keep the original tail-first priority, and
successful declarations retain source order. Inference and codegen retain their
cost-balanced plans and grain cutoffs of 128 and 512.

All three executors expose up to eight branches at once. Stock Bend 2.0.21's CPU
runtime drains contiguous groups of 16 task lanes; a small binary fork tree can
leave its runnable leaves concentrated in only a few worker chunks. Matching
three tree levels before forking spreads those branches without changing task
boundaries or join order. Native protocol word counting and CST scanning now use
flat tail loops: recursive `Result.bind` continuations, diagnostic formatting
and retained cursor projections are outside the hot scan loops. Request word
counts remain an exact traversal bound, proved equal to `List.length`.

### Full JS versus native builds

Bend 2.0.21, Deno 2.9.6, clang 22.1.8, Ryzen 7 7800X3D (8 physical cores, 16
logical CPUs), Linux. Seven samples after two warmups, sequential configurations
in reusable processes, after builds and tests completed. The desktop also had
other applications running; small differences are not strong scaling evidence.
Times include the single-threaded Deno frontend, transport, Bend compilation and
artifact decoding. Startup, verification and Wasm execution are excluded. JS is
the single-threaded generated compiler, not the worker pool.

Median milliseconds:

| Workload    |     JS | Native 1 | Native 2 | Native 4 | Native 8 | 1→8 speedup |
| ----------- | -----: | -------: | -------: | -------: | -------: | ----------: |
| Reader 8    |  17.04 |     4.80 |     5.61 |     4.39 |     4.49 |       1.07× |
| Reader 64   |  90.83 |    35.48 |    40.74 |    38.60 |    39.17 |       0.91× |
| Uneven 64   | 182.09 |   104.52 |   104.25 |    94.47 |    88.77 |       1.18× |
| Balanced 64 | 790.95 |   522.63 |   506.91 |   450.67 |   418.26 |       1.25× |
| Chain 64    |  28.44 |    10.59 |    14.88 |    14.44 |    14.21 |       0.75× |

The new balanced fixture has 64 independent functions with 64 arithmetic let
bindings each. Other fixtures are described in the historical section below. All
omit the prelude. Eight native threads are 1.89× faster than JS on Balanced 64,
but only 1.25× faster than one native thread. This is real, modest end-to-end
scaling, not linear scaling. Reader 64 and the dependency chain still lose with
more threads; one thread remains the API default. Native's advantage over JS is
not solely parallelism: its single-threaded backend is already faster here.

The remaining serial work includes parsing/layout and request encoding in Deno,
dependency and cache-key preparation, shared-budget constant evaluation, Wasm
linking and transport. Isolated parallel-phase gains must not be presented as
whole-compiler gains.

### Isolated parallel phases

The grain sweep now includes matching single-threaded JS jobs and native
1/2/4/8-thread runs. Three samples of 32 iterations compile 64 independent jobs,
alternating eight/64-binding bodies. Fixture creation, serial-reference warmup,
complete ordered result comparisons and startup are untimed. Native uses
monotonic millisecond intervals, JS uses `performance.now()`. Each backend is
checked against its own serial reference; the full-build benchmark above checks
cross-backend artifacts. No frontend, transport or Wasm linking is measured.

Median milliseconds per batch, at the production cutoffs:

| Phase     | Cutoff |     JS | Native 1 | Native 2 | Native 4 | Native 8 | 1→8 speedup | JS→8 speedup |
| --------- | -----: | -----: | -------: | -------: | -------: | -------: | ----------: | -----------: |
| Inference |    128 | 52.487 |   16.750 |    9.344 |    4.938 |    3.594 |       4.66× |       14.61× |
| Codegen   |    512 | 10.847 |    2.313 |    1.719 |    1.000 |    0.875 |       2.64× |       12.40× |

Both phases improve from four to eight threads; their gains are not linear. At
eight threads, disabling forks takes 25.188 ms for inference and 2.938 ms for
codegen. Those are useful scheduling controls, but are not the one-thread
baseline used for the speedups in the table. The sweep also covers tiny bodies
and cutoffs 0, 128, 512, 1024, 2048 and 8192. Sub-millisecond codegen intervals
are quantized; zero intervals in the tiny runs mean below timer resolution, not
zero work. Results and compiler hashes are in
[the grain report](../build/concurrency-grains.json).

A separate diagnostic run of the balanced source measured lowering at
77/43/23/15 ms for 1/2/4/8 threads (three runs, median). It places IO timestamps
between native phases and excludes host frontend work, so its phase timings must
not be summed or substituted for the production full-build measurements. The
local diagnostic source and output are in `build/concurrency-phases.bend`,
`build/concurrency-phases.ts` and `build/concurrency-phases.log`.

### Verification and reproduction

All 20 workload/thread configurations match complete JS artifacts; the emitted
Wasm executes, incremental edits match clean builds, and unchanged requests
reuse their results. All 435 compiler tests pass, including parallel lowering
order, error selection and Unicode-decoder recovery at 1/2/4/8 threads. Bend
proofs, native ownership checks at 1/4 threads, TypeScript checking and
changed-file formatting pass.

Raw samples, p95 values, compiler hashes, cache counters and explicit JS/native
speedup ratios are in [the full-build report](../build/concurrency-wide.json).
These generated reports are ignored by Git. Reproduce with:

```sh
just bench-native 7 build/concurrency-wide.json 1,2,4,8 2
just bench-grains 32 3
```

The earlier measurements below describe prior implementations, not the current
compiler.

## Dependency batches and edit reuse (2026-09-20)

Clean builds and native incremental sessions now share dependency-ready
inference batches. Recursive groups stay together; independent groups run in
cost-balanced Bend fork trees. Independent Wasm cache misses use the same coarse
task approach. Tiny scalar/name operations no longer fork. Grain cutoffs are 128
estimated work units for inference and 512 for codegen, selected with the
isolated sweep below, not elapsed-time thresholds.

The incremental frontend still lexes and validates layout across changed source,
but only reparses changed declaration islands when their boundaries are safe.
Successful identical revisions reuse a private result without native IPC;
trivia-only edits can also reuse it after frontend validation. Failed revisions
never publish a result cache. Returned results are independent copies.

### Matched before/after

Both snapshots were built with stock Bend **2.0.21**, Deno 2.9.6 and clang
22.1.8 on the Ryzen 7 7800X3D/Linux host. The baseline freezes the compiler
before this optimization pass, with only the native C bridge adjustment needed
by the new Bend runtime. This comparison does not attribute a toolchain upgrade
to these optimizations; earlier 2.0.5 measurements below are separate history.

Seven samples after two warmups per configuration, run sequentially after
compiler builds/tests finished. Full builds use no semantic cache; body edits
use a persistent declaration-cache session, restoring the original source
outside each timed sample. All fixtures omit the prelude. Times include parsing,
native transport, compilation and returned artifact construction, but exclude
compiler bootstrap, process startup, file IO, verification and Wasm execution.
First incremental builds and startup are separately recorded single
observations, not medians.

These are compiler-core fixtures, not the source ECS or a live game:

- Reader 8/64: independent effectful functions, one scoped provider, and one
  pure exported wrapper per function.
- Uneven 64: independent arithmetic functions, eight with 64 let bindings and
  the other 56 with eight; an edit changes one addition in the first function.
- Chain 64: a dependency chain of 64 arithmetic functions and an exported
  wrapper; an edit changes the first function without changing its interface.

One native thread, medians in milliseconds; each cell is **before → after**:

| Workload  |       Full build | One body edit |     Unchanged |
| --------- | ---------------: | ------------: | ------------: |
| Reader 8  |      6.93 → 7.35 |   3.02 → 2.38 |  4.22 → 0.056 |
| Reader 64 |    84.13 → 57.24 | 21.59 → 16.61 | 21.14 → 0.390 |
| Uneven 64 | 1353.84 → 169.47 | 59.87 → 44.03 | 55.27 → 0.152 |
| Chain 64  |    20.73 → 16.82 |   7.45 → 7.18 |  7.27 → 0.123 |

Reader 64 uses 32% less full-build time and 23% less body-edit time; its new
full-build/body-edit p95 values are 58.11/17.11 ms. Uneven 64's full build is
about 8× faster. This is not exclusively a parallelism win: clean builds now
check dependency groups instead of solving unrelated functions together, and the
JS reference improves on the same large fixture from 3096.34 to 199.29 ms. The
tiny Reader full build regresses slightly; dependency-chain body edits gain
little at one thread and regress at multiple threads. These are not
across-the-board speedups.

Reader 64 body edits parse one island and reuse 129, check one inference group
and reuse 128, and compile one code entry and reuse 129. Unchanged requests skip
the native compiler, but copying the public artifact still has a cost. The
`parsed_ms` counter now covers normalization and origin remapping as well as
parsing, so it is not a like-for-like phase comparison with the old counter.

### End-to-end native concurrency

After this pass, full-build medians in milliseconds:

| Workload  |     JS | Native 1 | Native 2 | Native 4 | Native 8 |
| --------- | -----: | -------: | -------: | -------: | -------: |
| Reader 8  |  18.66 |     7.35 |    12.89 |    12.36 |    12.77 |
| Reader 64 |  96.15 |    57.24 |    97.22 |    96.19 |    99.02 |
| Uneven 64 | 199.29 |   169.47 |   270.25 |   272.62 |   287.75 |
| Chain 64  |  31.97 |    16.82 |    32.37 |    31.51 |    31.57 |

One thread remains the default: more threads still lose end-to-end on these
fixtures. Parsing/layout, lowering, dependency/cache-key preparation, ordered
const evaluation, linking and pipe transport remain outside the parallel
inference/codegen batches. These totals do not isolate the runtime overhead
responsible for the multithreaded slowdown.

### Isolated grain calibration

The native harness runs 64 independent jobs with either tiny literal bodies or
alternating eight/64-binding bodies. Its uneven mix deliberately differs from
the end-to-end fixture. Three samples of 32 iterations use native monotonic
millisecond intervals; fixture creation, serial-reference warmup, full output
comparison and process startup are outside timing. No frontend, transport or
linking is included. Every result matches the complete ordered serial output.

Uneven jobs, median milliseconds per batch at the selected production cutoffs:

| Phase     | Cutoff | 1 thread | 4 threads | 4 threads, forks disabled |
| --------- | -----: | -------: | --------: | ------------------------: |
| Inference |    128 |   19.125 |     5.719 |                    29.031 |
| Codegen   |    512 |    2.875 |     1.625 |                     3.188 |

This demonstrates actual parallel speedups inside both batches, not a claim that
the whole compiler scales by the same ratio. The sweep includes cutoffs 0, 128,
512, 1024, 2048, 8192 and a sequential reference. Inference cutoff 128 beats
1024 on the uneven fixture. Codegen cutoff 512 keeps the tiny batch sequential
while retaining a large-batch gain; forcing every split improves the uneven
batch further but penalizes the tiny one. Tiny codegen timings approach clock
resolution and must not be interpreted as zero-cost compilation. These are
measured defaults, not universal optimal cutoffs.

### Verification and reproduction

All 16 before/after workload/thread pairs have identical source and Wasm hashes.
Every native full artifact equals the JS reference, incremental bytes equal
clean rebuilds, and original/edited Wasm returns the expected values without
imports. The final build passes 429 compiler tests, Bend proofs, the native
ownership regression at 1/4 threads, 13 editor/case-study static checks,
TypeScript checking and formatting. The array CLI build and host-capability demo
also pass.

Raw samples, p95 values, compiler hashes and cache counters are in the ignored
[before](../build/parallel-before.json), [after](../build/parallel-after.json)
and [grain sweep](../build/parallel-grains.json) reports. Reproduce current
runs:

```sh
just bench-native 7 build/parallel-after.json 1,2,4,8 2
just bench-grains 32 3
```

## Earlier generic effect core (2026-09-20, Bend 2.0.5)

Earlier workload: independent source-defined Reader functions, one scoped
provider, and one pure exported wrapper per function. This is a compiler-core
fixture, not an ECS implementation or the 3D sandbox.

Measured sequentially on the Ryzen 7 7800X3D/Linux host, with Deno 2.9.6, Bend
2.0.5 and clang 22.1.8, after builds and tests completed. Full-build and
body-edit times are medians of five samples in reusable sessions. Unchanged
times are single observations. Timings include parsing, native transport and
Wasm emission; they exclude the Bend bootstrap, process startup, file IO and
Wasm instantiation/execution.

| Effectful functions | Native threads | JS full   | Native full | One body edit | Unchanged |
| ------------------- | -------------- | --------- | ----------- | ------------- | --------- |
| 8                   | 1              | 18.44 ms  | 6.88 ms     | 2.80 ms       | 3.57 ms   |
| 8                   | 4              | 18.44 ms  | 12.34 ms    | 4.03 ms       | 3.42 ms   |
| 64                  | 1              | 135.26 ms | 83.59 ms    | 19.19 ms      | 18.39 ms  |
| 64                  | 4              | 135.26 ms | 137.77 ms   | 28.36 ms      | 29.57 ms  |

Each body edit rechecks one group and regenerates one Wasm entry. The
64-function fixture reuses 128 groups and 129 code entries; unchanged revisions
recheck and regenerate none. The remaining unchanged cost includes parsing,
exact cache-key construction and relinking. Four native threads are slower here;
one remains the default. These measurements do not establish a parallel speedup
or a like-for-like improvement over the retired ECS backend.

Every native full artifact matched JS analysis and bytes; incremental bytes
matched a clean rebuild, and the resulting Wasm executed correctly without
imports. Startup observations and cache counters are in the ignored report
`build/generic-effects-bench.json`. Reproduce with:

```sh
just bench-native 5 build/generic-effects-bench.json 1,4
```

### Capability-boundary recheck

After adding sealed `Foreign` annotations, callback wrappers and `blot:abi`
manifests, the same five-sample protocol at one native thread measured:

| Reader functions | JS full   | Native full | One body edit | Unchanged (single) |
| ---------------- | --------- | ----------- | ------------- | ------------------ |
| 8                | 17.83 ms  | 7.57 ms     | 2.97 ms       | 2.62 ms            |
| 64               | 139.62 ms | 81.58 ms    | 19.92 ms      | 21.05 ms           |

These are still the Reader fixture, not a host-callback or ECS benchmark. Body
edits still recheck/regenerate exactly one group/entry; the 64-function case
reuses 128 groups and 129 entries. Native artifacts match the JS reference,
incremental bytes match clean builds, and execution checks pass. No speedup is
claimed from the small differences between runs. The report is
`build/capability-boundary-bench.json`; reproduce with
`just bench-native 5 build/capability-boundary-bench.json 1`.

## Historical ECS measurements

The ECS-specific compiler backend measured here has been retired. These numbers
are historical reference, not timings for the generic effect core. Run
`just bench-native` for current non-ECS full-build, body-edit, and
unchanged-cache measurements.

## Native subprocess (2026-09-20)

Measured on the same AMD Ryzen 7 7800X3D / Linux x86_64 host, Deno 2.9.6, Bend
2.0.5, clang 22.1.8. The native compiler is an ELF executable launched by Deno,
not the Bend-generated JS module. Deno still handles Baba parsing. Runs were
sequential, after builds, tests, and other compiler probes finished.

Seven samples after two warmups per workload, in reusable sessions. These are
**full source-to-Wasm compilations**, with no semantic cache. Native times
include CST encoding, pipe transport, native decoding, lowering, checking, const
evaluation, code generation, and response decoding. Both paths include source
parsing and checking the prelude. Builds, session startup, source file I/O,
artifact comparisons, and Wasm instantiation/execution are outside the timed
samples.

| Workload             | JS median | Native 1 thread | Native 2 threads | Native 4 threads | Native 8 threads |
| -------------------- | --------: | --------------: | ---------------: | ---------------: | ---------------: |
| 7-system scalar port |  38.98 ms |        21.60 ms |         36.00 ms |         35.23 ms |         36.11 ms |
| 16 systems           |  83.83 ms |        53.53 ms |        178.79 ms |        168.62 ms |        181.87 ms |
| 64 systems           | 342.52 ms |       230.48 ms |       1680.77 ms |       1576.88 ms |       1776.82 ms |

One native thread reduces the 64-system median by **33% (1.49× faster)** versus
the freshly measured JS reference. Its 64-system p95 is 236.18 ms versus 351.26
ms for JS. This has not reached 100 ms. Additional native threads are
substantially slower on these fixtures; one remains the default. This matrix
does not isolate the runtime cost causing that slowdown and does not justify
claiming a native parallel speedup.

Session startup (frontend/prelude setup plus the native startup handshake) was
16.89 / 9.78 / 8.86 / 9.12 ms for native 1/2/4/8 threads, measured once per
configuration. JS frontend setup was 22.09 ms, excluding its earlier module
load. Startup order/JIT state differ, so these are observations, not a
cold-start comparison. First-compilation times and all raw samples are in
[the report](../build/native-bench.json).

Every native configuration exactly matched JS public analysis, storage metadata,
and Wasm bytes for all three workloads; emitted ECS Wasm also executed. The
native binary SHA-256 was
`c4f0028719ab7512a1c89f1e10aceb3136edecf4027510d409cef3654a216126`; the report
also records JS/source/Wasm hashes. The native build uses the
[guarded build-local ownership fix](README.md#run-it) for a reproduced Bend
2.0.5 native bug. It is not an unmodified-stock-Bend measurement; the installed
Bend remains unchanged.

The declaration-cache/job/reload pipeline below still uses JS. A persistent
native process does not yet reuse semantic work between revisions; these
measurements must not be substituted for incremental edit/reload timings.

Reproduce with `just bench-native 7 build/native-bench.json 1,2,4,8`.
Verification: `just check` passed 244 compiler tests, 6 editor-configuration
tests, and all 28 Bend laws. The native backend regression passed at 1/4
threads, and CLI checking/building plus both demos worked with `compiler.js`
temporarily absent, verifying that user-facing execution does not depend on the
JS compiler.

## JavaScript optimization pass (2026-09-19)

Measured 2026-09-19 on an AMD Ryzen 7 7800X3D, Linux x86_64, Deno 2.9.6, with
the Bend 2.0.5 JS bootstrap. Before/after timing runs were sequential, after
builds and tests finished, using identical benchmark scripts and sources. These
are the U32 scalar ECS port and generated movement systems, not the full gdev
library or the proposed Blot ECS language.

### Changes measured

- Dependency planning builds nominal SCC closures once and propagates summaries
  through inference jobs, instead of repeating whole-graph searches per job.
- Source scopes, checker descriptor/effect graphs, duplicate validation, and ECS
  scheduling use shared persistent indexes. Scheduling accumulates access masks
  instead of repeatedly unioning and comparing growing effect rows.
- Read-only index lookup avoids rebuilding Bend's map and search key. Remaining
  inference/type metadata scans stop at the first match.
- Backend preparation shares constructor, lambda, and nominal-type catalogs. ECS
  storage bindings are computed once and reused by the host and linker.
- Linking carries measured byte chunks through body/section sizing, then
  flattens code/data once. Symbolic code-entry cache boundaries are unchanged.
- Full source compilation keeps the lowered module inside Bend, eliminating the
  AST decode-to-TypeScript/encode-to-Bend round trip. The external core API
  still validates its inputs. No checking or effect inference was removed.

### Full rebuilds

Fifteen samples after two warmups per workload, with a reusable source compiler.
Every sample reparses, lowers and checks the prelude/program, evaluates consts,
plans the world, and emits Wasm. No incremental cache is used. Compiler/frontend
initialization and Wasm instantiation are excluded.

| Workload             | Before median | After median | Before p95 | After p95 |
| -------------------- | ------------: | -----------: | ---------: | --------: |
| 7-system scalar port |      39.62 ms |     36.19 ms |   50.17 ms |  48.74 ms |
| 16 systems           |      89.65 ms |     78.30 ms |   96.81 ms |  81.10 ms |
| 64 systems           |     457.63 ms |    323.95 ms |  471.90 ms | 335.66 ms |

The 64-system median uses **29% less time**, a 1.41× speedup. This is a real
reduction from the roughly 450 ms result, not a claim to have reached 100 ms.
The small example's improvement is modest relative to its variability.

Wasm bytes and public analysis/storage are unchanged. The three workloads emit
4,525 / 10,148 / 32,119 bytes with identical SHA-256 hashes. Exact baseline
comparison also covered the 128-system artifact and 30 example outcomes:
analyze/compile/compileEcs with and without the prelude, including diagnostics
for unsupported design syntax.

Raw reports: [before](../build/ecs-levers-before.json),
[after](../build/ecs-levers-after.json).

### Fresh incremental pipeline

A new session per sample, five samples, one inline lane. These builds have no
previous user revision to reuse; they include first-use worker/JIT costs but
exclude separately reported session startup. They use the declaration/group
pipeline, unlike the monolithic full-build entry point above.

| Workload             | Before median | After median |
| -------------------- | ------------: | -----------: |
| 7-system scalar port |      33.77 ms |     29.69 ms |
| 16 systems           |      91.85 ms |     76.08 ms |
| 64 systems           |     394.07 ms |    272.48 ms |

The 64-system pipeline uses **31% less time**. Its phase medians show where the
work disappeared:

| Phase                        |    Before |     After |
| ---------------------------- | --------: | --------: |
| Parsing                      |  21.11 ms |  20.37 ms |
| Scope preparation/lowering   |  81.75 ms |  73.89 ms |
| Planning/checking/cache keys | 157.24 ms | 102.06 ms |
| Const/world planning         |  29.41 ms |   8.12 ms |
| Backend preparation/codegen  |  43.52 ms |  37.37 ms |
| Linking/storage/output       |  50.12 ms |  19.39 ms |

Phase medians need not sum to the total median; orchestration and cloning add
other work. This fixture has no const initializers, so its `constants_ms` is
principally world planning. All 91 inference jobs and 312 code entries still
compile. The gain does not come from silently reusing a previous revision.

### Edit to reloaded world

Five samples per edit in a persistent one-lane session. The 16-system fixture
also contains a const, pure helper, and non-storage ADT. Each sample restores
the baseline outside timing, then compiles the edit and reloads an immutable
baseline world. Times include parsing/checking, consts, codegen/linking, Wasm
compile/instantiate, and state-preserving reload; startup is excluded.

| Edit                          | Before median | After median | After p95 |
| ----------------------------- | ------------: | -----------: | --------: |
| Identical source              |       0.63 ms |      0.66 ms |   0.86 ms |
| Trivia only                   |      16.53 ms |     17.99 ms |  22.09 ms |
| Same-interface helper body    |      39.54 ms |     38.04 ms |  39.27 ms |
| Helper effect change          |      60.63 ms |     48.93 ms |  51.07 ms |
| Constructor-tag layout change |      47.82 ms |     45.32 ms |  45.72 ms |
| Const value change            |      39.30 ms |     34.28 ms |  36.32 ms |
| All 16 system bodies          |      58.47 ms |     56.77 ms |  57.84 ms |

This pass chiefly improves fresh builds and metadata-invalidating edits.
Single-body/all-body changes improve only modestly; trivia-only edits are
slightly slower in this run. It is not an across-the-board hot-reload speedup.

Cache counts are unchanged: the body edit checks 1/45 groups and compiles 1/122
entries; the all-body edit checks 16/45 and compiles 16/122. The effect edit
checks the helper and caller together and updates the query. The layout edit
shifts constructor tags without changing the stored U32 wrapper layout; it does
not test arbitrary record-layout migration. Const edits reevaluate the value and
relink consumers without regenerating their instructions.

Every artifact is checked against a clean build: exact bytes/storage, types
modulo quantified-variable renaming, effects, const values, and world plans. The
benchmark executes both standalone and state-preserving reloaded worlds.

### Concurrency

One lane runs inline; additional lanes use persistent Deno workers for
independent inference groups and code entries. Recursive and shared
monomorphic-effect constraints stay together. Const evaluation retains its
source-ordered shared budget.

| Lanes | Fresh 64 before | Fresh 64 after | Session startup after | All-body edit/reload after, 16 systems |
| ----: | --------------: | -------------: | --------------------: | -------------------------------------: |
|     1 |       394.07 ms |      272.48 ms |              11.42 ms |                               56.77 ms |
|     2 |       435.43 ms |      315.19 ms |              24.54 ms |                               62.69 ms |
|     4 |       399.16 ms |      284.36 ms |              38.54 ms |                               54.05 ms |
|     8 |       389.53 ms |      269.02 ms |              65.16 ms |                               52.25 ms |

Eight lanes are only about 1% faster than one for fresh 64-system compilation,
with much higher startup cost. They improve the all-body edit by about 8%. One
lane remains the default. Five samples on these fixtures are not a universal
worker-count recommendation or evidence of native Bend speedup.

Complete raw samples, phase/cache counts, hashes, startup/reload measurements,
and all worker/edit combinations:
[before](../build/incremental-levers-before.json),
[after](../build/incremental-levers-after.json).

### Remaining large costs

Parsing/lowering and planning/checking still account for roughly 196 ms in the
one-lane fresh 64-system pipeline. Adding more codegen workers cannot remove
that work. A separate eight-compile CPU profile of full rebuilds puts
`types.resolve` at about 24% inclusive sampled time; ordered substitution
resolution is now the leading identifiable inference cost. The profile is
[saved locally](../build/ecs-levers-after.cpuprofile); sampling is not used for
the timing tables.

The next inference optimization is a shared substitution index that preserves
assignment order and suffix semantics. Simply clearing substitutions at an SCC
boundary is unsafe: effectful monotypes and deferred access/purity/coverage
requirements still need the final state. That lifecycle change was not mixed
into this pass.

For small edits, the remaining frontend and preparation costs matter more. The
body-edit phase medians are about 15.5 ms parsing/lowering, 7.3 ms
planning/checking/keys, 6.0 ms backend preparation/codegen, and 5.8 ms linking.
Non-identical source still reparses the whole file; backend catalogs are rebuilt
for each nontrivial revision. Incremental parsing and reusing unchanged
preparation metadata are more promising than extra workers for this case.

### Reproduce and verify

```sh
deno task build:compiler:js
deno run --allow-read=generated/wasm,examples,std --allow-write=build compiler/ecs_bench.ts 15 build/ecs-levers-after.json
deno run --allow-read=compiler,generated,examples,std --allow-write=build compiler/incremental_bench.ts 5 build/incremental-levers-after.json 1,2,4,8
```

Or use `just bench-ecs` and `just bench-incremental`; their Bend build step is
outside timed regions. Reports/profiles live in ignored `build/`.

The local before snapshot is `/tmp/blot-levers-baseline.w1xJJM`, taken before
this pass; it is not a versioned release. Its compiler SHA-256 is
`81953c6d11034cf78a845d609e2a7cb186ee245cb752636bb0410452eeb2fdd7`. The measured
current compiler is
`38364f00bd927d2b504ae10539a2bfd4b4671e553d9a38a1721e78f9bc9ff979`.

Verification: `just check` passed 225 compiler tests, 6 editor-configuration
tests, and all 26 Bend laws. New regressions cover randomized graph/effect
oracles, diagnostic priority, exact Unicode/nominal identities, source scope
precedence, shared backend metadata, and byte-length encoding boundaries.
