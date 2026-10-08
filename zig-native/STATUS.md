# Zig compiler status

The next ten compiler-performance tracks have bounded implementations. The
default path deduplicates complete refinement queries in fresh and retained
builds, shares closed source type imports, preserves eligible caller type
answers across runtime-body edits, retains validation certificates, and reuses
optimized bodies across direct-call index changes. Completed scalar constants
can participate in enclosing code-fragment reuse. Explicit dependency
checkpoints now include eligible nonempty principal type/row results.

On five alternating frozen-gdev pairs, median native CPU is **1,196 → 1,182 ms
cold**, **350 → 310 ms first edit**, and **330 → 290 ms revert**. Cold CPU is
nearly unchanged; edit CPU improves about 11–12%. Allocation traffic falls
**433.6 → 425.4 MB**, with less than 1% change in peak requested live storage.
Population refinement regions fall **8,539 → 1,490**, but the largest remaining
inference region still contains 267,068 nodes. Severe host contention makes the
wall samples unsuitable for claiming a target latency. The 500 ms cold / 100 ms
edit goals remain unestablished.

Independent first-order inference partitions, scalar SSA branches/joins, and
parallel semantic jobs remain opt-in. General higher-order/SCC summaries, full
revision metadata deltas, aggregate evaluation retention, resolved calls/loops/
heap ownership and an adaptive semantic scheduler remain open. These are
general language optimizations, with no prelude-name rules.

The release build and **1,095 native tests** pass. All **548 guest/client tests**
pass across the full run and focused retries after temporary-disk exhaustion
and artificial-peer startup timeouts. Fresh/retained gdev bytes agree exactly.
Lint reports 120 existing warnings and no errors across 285 files. The
[semantic performance report](../std/PERFORMANCE.md#semantic-compilation-performance)
records the ten scopes, raw measurements, qualification details and binary pin.
This batch has not been installed locally.

## Compile budgets and benchmark harness

`zig-native/tests/compile_budget.test.ts` compiles a synthetic corpus
(`scripts/bench/corpus.ts`: monomorphic and generic chains, a generic diamond, a
generic fanout) and asserts budgets on deterministic work counters and allocator
bytes, never wall time. Budgets are 1.5x the values measured when set; later
summary-based instantiation hills should lower the counters, and the `today`
tables should then be tightened. Ignored probes record two cliffs: a
monomorphic chain of 300 links is rejected with `constant_fuel` (collect depth
256) and a generic diamond of 16 levels is exponential.

`deno task bench:compile --baseline OLD/blotc --candidate NEW/blotc [--runs 5]`
replaces the per-batch harnesses. It alternates fresh-process pairs and
retained-session phases (population, first edit, subsequent edit, no-op),
reports median child CPU (user + system), verifies Wasm SHA-256 equality between
binaries and between fresh and retained builds, and writes results under
`build/tmp/bench/<timestamp>/`. The private gdev snapshot lives in
`build/bench/gdev-snapshot` (gitignored; never commit it) and is verified
against `scripts/bench/gdev-manifest.json`; without it the synthetic corpus
still runs. Pass `--profile` to `blotc build` for detailed backend clocks.

## Previous packed-row checkpoint

The production packed-row transfer is implemented and tested. Lists and Arrays
store flat scalar tuples/records inline, with preserved snapshots, field order,
floating-point bits and logical lengths. Packed cursors and direct loops reuse
leaf spans. A bounded general inlining pass exposes allocation producers to
scalar replacement; it has no prelude-name rules.

On 100,000-row fixtures, generation/folding uses about **6.4× less CPU** and
List/Array conversion about **4× less**. Retained List storage falls **61%** and
Array storage **43%**. Performance is mixed: read-only List folds use about
**1.9× as much CPU**, cursors **1.5×**, and the comprehension fixture uses one
extra Wasm page. Broader fusion/SIMD and generic iterator allocation remain open.

Paired frozen-gdev results are **1,466 → 1,606 ms cold**, **389 → 399 ms first
edit**, and **353 → 370 ms revert**. Cold CPU increases about 2.4%; this batch
does not establish a compiler-speed improvement. Fresh/retained output parity
and Wasm validation pass. The 500 ms cold / 100 ms edit targets remain unmet.

The full native suite and **546 guest/client tests** pass. Zig-analyzer reports
120 existing warnings and no errors across 280 files. The
[packed-row report](../std/PERFORMANCE.md#production-packed-scalar-rows) contains
the raw sample locations, limitations and exact binary pin. These changes are
not installed locally.

## Previous compiler-performance checkpoint

The current [compiler-performance program](../PLAN.md) is in progress. Its
qualified default path retains optimized bodies, keys anonymous static closures
by captured values, shares bounded inference scratch and closed evidence imports,
and replays projected principal queries across scalar literal edits. Prepared
graph importers avoid repeatedly validating already admitted principal queries.
These are general compiler optimizations, with bounded reuse admission.

The final five alternating pairs on the frozen 394 KB gdev workload show
median first edit **984 → 378 ms**, subsequent edit **982 → 376 ms**, and fresh
CLI compilation **1,354 → 1,294 ms**. Requested allocation bytes fall **503 → 433
MB**; cold peak RSS is about 74 MiB and retained peak RSS about 158 MiB. Peak
tracked live storage is unchanged. Earlier quieter runs measured 773/184/171 ms
for the candidate; absolute times cannot be compared across batches. Both
latency targets remain unmet. Every Wasm hash matches the original compiler.
The native suite and **539 guest/client tests** pass; the
[final measurement report](../std/PERFORMANCE.md#compiler-performance-program-final-default-path-check)
records boundaries, raw samples and the exact binary. That measurement preceded
the later packed-row checkpoint; neither candidate was installed locally.

Opt-in development tiers, exact private machine-body sharing and coarse parallel
optimizer jobs pass 1,077 native and 537 guest/client tests. Sharing reduces
gdev Wasm size by 7.8%; four workers reduce the measured cold assembly phase
from about 30 ms to 18 ms, without an established total compilation speedup.
All three remain opt-in. Explicit portable backend checkpoints now restore
empty-result principal-query proofs and optimized bodies after process death.
The full gdev restore produces identical Wasm and reuses 1,438 call proofs and
1,536 optimized bodies. The checkpoint release gate passes with 538 guest/client
tests. Five paired restarts use about 30% less child CPU work; heavily contended
wall-clock samples are not a target-latency result. Evaluated values and arbitrary
specializations are not persisted.

Resolved scalar SSA now has a default-off native prototype. It emits without
source/solver owners but admits only two gdev bodies; no useful compilation
speedup is established. A stateless scalar live-patch prototype redirects
unchanged and recursive callers while preserving exported function objects,
with stale/corrupt patch rejection and transactional table publication. It is
an internal experiment and cannot patch gdev's heap/effect state. The final
release build, native suite and 539 guest/client tests pass. Lint reports 120
existing warnings and no errors across 279 files. General body-level checking,
complete ownership-aware SSA, arbitrary specialization persistence and stateful
live patches remain open.

## Previous list transfer qualification

The [list transfer batch](../std/PERFORMANCE.md#list-transfer-batch) is qualified
and installed locally. Independent cursor leaf positions, small scalar
collection elimination, exact-size rectangular builders and reusable function
facts use general compiler proofs. The focused runtime probes improve by about
2.7×, 85× and 96× respectively; these are not whole-application speedups.

At that checkpoint, packed scalar rows were an isolated layout/emission
prototype. Its 100,000-row fixture was about 4.3× faster and used 44% less heap,
with raw F32 bits preserved. It had not changed production List/Array storage.
Lists retain their existing AVL backing.

The native suite and **534 guest/client tests** pass. Zig-analyzer checks 258
files with 122 existing warnings and no errors. The standalone compiler builds
the frozen 394 KB gdev workload into the same 629,240 valid Wasm bytes as the
native binary. Qualification pins are in
`build/list-transfer-review/qualification.json`.

Paired native-process cold compilation is 1,338 → 1,323 ms, with about 73 MiB
peak RSS. Retained edits are around 830–853 ms, with mixed changes against the
baseline. This does not establish a compilation speedup, and the 500 ms cold /
100 ms edit targets remain unmet. Historical timings below used earlier runs
and cannot be compared directly with this batch.

## Architecture cleanup qualification

The seven architecture cleanups are qualified in the
[2026-10-07 report](../std/PERFORMANCE.md#compiler-architecture-cleanup).
The compiler now shares a typed runtime IR, a pass pipeline, heap layouts and
session policies; specialization has its own semantic service. Mutable global
switches are gone, semantic validation shares immutable storage, and conversion
boundaries distinguish numeric handle domains.

Private handler frames and cells have explicit cleanup on scope exits and
cancellation. After 10,000 raw effect calls without collection or host resets,
guest memory stays at 128 KiB; the committed compiler grew to 1 MiB. Escaping
payloads retain their own lifetime, covered by an executed survival test.
The full compiler gate passes: **1,055 native and 528 guest/client tests**.
Zig-analyzer reports 122 existing warnings and no errors across 253 files.

On the frozen 394 KB gdev workload, paired cold compilation is 808 → 813 ms,
with about 74 MiB peak process RSS; retained edits remain around 500 ms.
The cleanup does not establish a compilation speedup. Both latency targets
remain unmet. Tracing remains for dynamic/unproved graphs; shared RC, escaping
and suspended-effect ownership, and dynamic cycle reclamation are still open.

The packaged standalone also builds and validates the frozen game (620,017 Wasm
bytes). The live gdev working tree has since added generated
`src/crystal_spots.blot`; its annotations/expressions fail with identical
diagnostics on both compiler versions. That live build is not a passing smoke
test. Logs and binary pins are saved in
`build/architecture-cleanup-review/qualification.json`.

The migration qualification below records its earlier, smaller workload and
compiler revision.

## Zig-only migration qualification

The Zig-only migration is complete, including `../gdev`'s host, tests, profiling
scripts and desktop packaging. The compiler uses Zig **0.17.0** and the
asynchronous [project API](PROJECT_CLIENT.md). The retired synchronous Bend API,
analysis objects and exact Bend step budgets are outside the supported contract.

Release compiler identity:
`2d8050d273b5baa98107c2a38d4144b92885bbe16d0e510e5b2b41b23968c850`. Built for
Linux x86-64 baseline with `-Doptimize=fast` and LLVM/LLD.

## Measured gdev compilation

| Measurement                                        |   Median | Observed range |
| -------------------------------------------------- | -------: | -------------: |
| Fresh CLI, source dependencies                     | 296.6 ms | 292.2–336.8 ms |
| Fresh CLI, compiled dependencies                   | 270.4 ms | 266.1–273.6 ms |
| Packaged API population, including extraction/open | 388.3 ms | 386.4–453.4 ms |
| First imported edit, source-populated session      |  91.9 ms |   90.3–93.9 ms |
| First imported edit, bundle-populated session      |  90.5 ms |   89.2–91.2 ms |
| Subsequent imported edit, source-populated session |  88.2 ms |   86.1–88.4 ms |
| No-op, source-populated session                    |  14.6 ms |   14.2–16.1 ms |

Cold measurements use five fresh native processes per lane, alternating source
and bundle runs. Executable, 26 source files and used bundle pages were verified
nonresident before each launch. Timing includes process launch, output writing
and teardown. Shared libraries and filesystem metadata remain uncontrolled;
bundle creation is measured separately (123.4 ms, 25 modules, 8,946,330 bytes).

Retained measurements use three independent sessions per lane. Each session
performs population, an unsaved `robots.blot` edit, revert, second edit and
no-op. Timing includes the public API round trip, Wasm validation, hashing and
output writing. Population additionally includes session opening. Packaged
population uses five fresh compiler instances with warm filesystem caches and
includes binary extraction; it excludes starting Deno and closing the compiler.
These are measurements of this workload, not latency guarantees for every edit.

Peak native-process RSS was **43.7 MiB** for the cold builds and **48.2 MiB**
for the retained packaged compiler. Maximum requested allocator storage in the
cold runs was **24.8 MiB**, with zero live requested bytes after teardown. Zig's
own compiler-build memory is separate from these Blot compilation measurements.

The game remains **237,692 Wasm bytes**, SHA-256
`f139c19842a3bf069e1be8ddfb6523f53a0113e5b46bddda28c36138d6ab3e5f`, identical to
the previous validated output. Every retained edit was compared with a fresh
build; reverting restored the original bytes. All 25 game/package `.blot` files
were unchanged during this migration.

[Raw samples, source/binary pins and qualification report](../build/zig-only-migration/REPORT.json).

## Validation

- **1,014/1,014 native tests**, including allocation-failure and ownership
  checks.
- **447/447 Wasm, transport, public API and formatter tests**.
- **57/57 gdev tests**, including GPU rendering, the 10,000-robot game,
  save/load, reload, error recovery and compiler restart.
- Six editor-helper tests, Tree-sitter grammar/highlight checks and 13 source
  example checks passed.
- Deno types/formatting, package dry run, compiler bootstrap check and Zig's
  incremental development build passed.
- A standalone Deno executable compiled and instantiated the real game using its
  embedded compiler/prelude. The gdev desktop bundle built successfully; the
  desktop UI was not launched for this qualification.
- The migrated swarm profiler ran its editor/play allocation scenarios.
- `zig-analyzer 0.17.0-1` checked 226 files: **zero errors, 129 warnings**.
  Warnings remain for deprecated APIs and conservative ownership/overflow
  findings; the analyzer exits 1 when warnings remain.

## Changes completing the migration

The public API, CLI, build/test tasks, package and CI use the native compiler.
Bend compiler sources, generated runtime, old adapters, obsolete test drivers,
benchmarks and the compiler-coupled ECS prototype were removed. Deno standalone
hosts extract their embedded standard library so the native child can read it,
and dispose of those files with the compiler.

Gdev now retains one native compiler across builds, shares concurrent requests,
and uses native source snapshots in its fixtures and profilers. Embedded array
literals use `#[]`, while array indexing remains `[index]`. Its game sources and
asset work were preserved.

Integration exposed and fixed curried callback effect-row closure, constant
records containing unused generic functions, partial application with static
records, and mixed static/dynamic captures. Constant collection callbacks may
fill unobserved interface slots only from an independently inferred concrete
proof. Existing unresolved-type diagnostics and failed-revision recovery remain
covered by tests.

Code jobs with static captures currently rebuild after edits because their
request keys do not yet contain the captured values. Complete emission-journal
replay and unrelated semantic/code reuse remain available. This conservative
policy is explicit in the [architecture](ARCHITECTURE.md).

## Preservation and remaining limits

The pre-migration working trees, including uncommitted changes, are archived in
`build/zig-only-migration/before-migration.tar.gz` and `gdev-before.tar.gz`,
with manifests and a removal inventory beside them. Old generated output is
preserved unchanged in `legacy-generated-compiler/`; the prior status history is
archived as `status-history.md`. These local archives are outside the active
compiler and package. Nothing was published by the qualification commands.

The packaged binary targets Linux x86-64; other platforms require an explicit
native executable. Lists use shared immutable chunk chains with exclusive end
edits; editing a shared list can still copy the chain. Future performance work
should follow measured costs and preserve the current validity and ownership
checks. See [the compiler direction](../PLAN.md).
