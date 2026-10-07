# Zig compiler status

The latest ownership work is qualified in the
[2026-10-07 runtime report](../std/PERFORMANCE.md#closed-shared-and-cyclic-allocation-groups).
Proven private allocations with shared children and cycles now release together
without tracing or reference counting. This extends the existing branch/loop
lifetimes, borrowed calls and fresh-result transfers. The shared-record benchmark
uses 17.30 → 4.46 MB, including a retained million-element startup List.
The full compiler gate passes, including 526 guest/client tests and the existing
cycle/async/retained checks. On the frozen 394 KB gdev workload, paired cold
compilation is 805 → 803 ms; retained edits remain around 500 ms. Both remain
above the targets. Tracing remains for dynamic/unproved graphs. Shared RC,
general effect cleanup and dynamic cycle reclamation without tracing are open.

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
