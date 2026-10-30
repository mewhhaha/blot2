# CT96: prepare spawn capability data once per compilation

23 October 2026. The qualified CT96 candidate reduces fresh game compilation CPU
by **28.6%** and devtools CPU by **29.0%** in seven alternating release pairs.
Median game build wall time changes from **17.240 to 12.156 seconds**; devtools
changes from **0.967 to 0.678 seconds**. Every emitted Wasm file matches the
baseline. Peak game RSS remains about 476 MiB.

## Implementation and ownership

`prepareSpawnApplication` previously scanned every binding in every module at
each call-preparation site. `Generator.init` now scans once. When a spawn
contract exists, the generator owns one array of pointers to its immutable Core
modules; otherwise it keeps an empty view without allocating that array. The
view is freed with the generator and rebuilt for every compilation attempt.

The presence check grants no task authority. Positive applications still call
the same `task_core.spawnApplication` validator with the same modules, so
wrapper validation, aliases, actual arguments and capture checks remain intact.
The view never crosses a retained revision, speculative retry or process
restart.

The change is confined to [core_backend.zig](src/backend/core_backend.zig) and
[backend_emission.zig](src/backend/backend_emission.zig). A new
[executed-Wasm regression](tests/task_surface_execution.test.ts) alternates
ordinary modules with imported/renamed spawn helpers, removes and reintroduces
them, compares each retained output to a fresh control, then exports and
restores a checkpoint. It executes both code-generation tiers and
synchronous/JSPI guests. Existing native task laws exercise forged contracts,
capture ownership and every allocation failure, including the new
generator-owned allocation.

## Fresh release comparison

Both variants use the same 554-file frozen gdev/Ink/std/assets workload and
unchanged 200-million-step budget from
[the baseline](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILE_MEASUREMENTS.md). Persistent caching and profiling are
disabled. Each sample starts a new compiler process; wall/CPU measure its build
request after project open. CPU includes exited worker threads at Linux's 10 ms
tick resolution. OS page caches are not flushed. Input and compiler hashes are
checked before and after the run.

| Workload | Baseline wall median (range) | Candidate wall median (range) | Baseline / candidate CPU median | Median paired CPU ratio |
| -------- | ---------------------------: | ----------------------------: | ------------------------------: | ----------------------: |
| Game     |     17.240 s (16.668–18.063) |      12.156 s (11.721–12.964) |               17.170 / 12.250 s |                 0.71387 |
| Devtools |        0.967 s (0.931–0.990) |         0.678 s (0.647–0.703) |                 1.000 / 0.700 s |                 0.71000 |

Game pair ratios range from 0.70435 to 0.72821. All seven pairs exceed CT96's
20% CPU-reduction target. Use these same-run pairs for the comparison; the
earlier standalone 16.292 s baseline came from a different interval. There is no
application source migration or output change.

Baseline release SHA-256:

```text
fec30aece1dccd18f4709a06a96d70f42e9cd0682f843bc53fa8e3f99fa0ab31
```

Candidate release SHA-256:

```text
fa75772f21cf9bce6a4c0cbfa60acef55bbd9a550a54336c426f9bee5a8fcb35
```

## Retained edits and remaining costs

One unprofiled retained pair checks fresh, cached restart, population, no-op,
trivia, literal-in-body and body-change builds. Each edit matches a fresh
control; each revert restores the original bytes; both compilers agree
throughout. This is a diagnostic screen, not a seven-pair retained speedup
claim.

| Action                 |     Baseline wall |    Candidate wall |
| ---------------------- | ----------------: | ----------------: |
| Cached process restart |           25.0 ms |           25.9 ms |
| No-op                  |           18.2 ms |           19.0 ms |
| Trivia edit            |           17.4 ms |           18.8 ms |
| Literal edit / revert  | 16.720 / 15.660 s | 11.355 / 10.646 s |
| Body edit / revert     | 15.311 / 15.530 s | 10.764 / 11.057 s |

Code edits still offer zero backend candidates and rebuild 4,266 named functions
and 1,424 closures. CT96 reduces their fresh backend cost; it does not implement
retained backend reuse. CT98 remains open.

Two CPU-weighted GDB profiles cover 99.29% of measured CPU across 1,011 complete
sampling intervals, with no missing or truncated stacks in those intervals.
`prepareSpawnApplication` has **no self-CPU samples**, compared with 27.6%
before the change; the observed result meets the below-5% target. Sampling is
not a claim of literally zero execution cost.

The next hotspots are `effects.Store.node` (15.88%), `effects.Store.replacement`
(11.55%) and `types.Store.resolveOperationRow` (5.10%). Backend inference
occupies 10.36–10.62 s in these sampled builds; constant preparation occupies
only 0.324–0.338 s. These diagnostic wall clocks include debugger interruptions
and must not be used as throughput comparisons against the earlier unsampled
phase run. The seven unprofiled pairs above are the speedup evidence.

Proceed with **CT97**: measure effect-row visits and chronological version-chain
lengths by inference region, then select a bounded optimization that preserves
rollback and row identity. **Defer CT99**: remaining constant preparation is
below its 10% eligibility threshold. The fresh-game median is still 12.25 s CPU,
so CT101's absolute below-12 s and below-8 s targets remain open.

## Qualification and build turnaround

The candidate is isolated from the concurrent text-capability repair. Its source
is `63c931f` plus CT96's two implementation files and guest regression, with the
measurement tooling copied into the snapshot. It does not qualify unrelated
working-tree changes or replace the installed compiler.

- Zig 0.17.0; Safe/noLLVM for all development/native test compilation.
- **2,539 native laws**, exhaustive allocation failures, four complete shards.
- **1,648 guest/client checks**, **48 smoke checks**, **57 tooling checks**.
- Zero Zig analyzer findings across 518 source files plus the fixture module.
- The edited task development cycle passes in **14.54 s**: complete native
  compilation, 17 selected native laws and 27 guest checks, plus local checks.

The first full gate reached its 600 s native-phase allowance after 2,366 laws
passed. It was cancelled and is preserved as incomplete evidence. The complete
rerun uses `--phase-seconds 900 --budget-seconds 1200`; every native law
executes again. Native compilation is reused only after its evidence is
verified. The original LLVM build takes 204.19 s; its repeated build takes 0.57
s. The successful gate takes 761.75 s overall, including 665.13 s native
execution and 29.45 s guest execution. These are qualification costs, not a
paired claim about compiler-build performance. No fault cases or quality checks
were removed.

## Evidence and reproduction

The [evidence archive](measurements/ct96-spawn-scan-2026-10-23.tar.gz) preserves
the candidate sources and hashes, raw paired samples, retained checks, CPU
stacks, complete gate logs and the incomplete timeout. Each payload has a
SHA-256 entry. Private application sources, compiler binaries, caches and
qualification keys are excluded.

Local artifacts are under `build/bench/ct96-20261023`; the qualified release is
`candidate/blotc` there. The original snapshot and baseline binary remain under
`build/bench/compile-cost-20261023`. The archive's `measurement-commands.json`
records the exact commands. For a new fresh comparison, use the baseline's
manifest/output pins with `bench:compile --runs 7 --no-retained --guard-cpu`.
Measure retained changes and collect a CPU profile separately.

Follow [the current hills](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILE_HILLS.md) for the next experiment.
