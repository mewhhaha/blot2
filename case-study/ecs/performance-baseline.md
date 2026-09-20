# Compiler baseline before the 3D case study

Captured from commit `318a37830a2fe84821b1c56953abf87e81198999`, before F32,
prelude, renderer, or native-session changes. These are the existing U32 ECS
workloads, not measurements of the later 3D application.

## Environment and evidence

- AMD Ryzen 7 7800X3D; Linux x86-64; Deno 2.9.6.
- Bend 2.0.5, using the repository's isolated owned-constructor extraction fix.
- Seven measured samples per series. No concurrent compiler builds or renderer
  tests during measurement; benchmarks ran sequentially from a frozen checkout.
- Raw reports: `build/case-study-baseline/native-full.json`,
  `incremental16.json`, and `incremental64.json`.
- `build/case-study-baseline/manifest.json` records hashes and commands. Its
  `inputs/` directory contains all 16 measured source revisions plus the frozen
  prelude. Every saved edit source was checked against its report's SHA-256.
- Complete checkout and generated artifacts retained at
  `/tmp/blot-case-baseline.wJGb9B`. Temporary and `build/` evidence is local,
  not committed source.

Frozen artifact SHA-256:

| Input               | SHA-256                                                            |
| ------------------- | ------------------------------------------------------------------ |
| Native compiler     | `c4f0028719ab7512a1c89f1e10aceb3136edecf4027510d409cef3654a216126` |
| JavaScript compiler | `38364f00bd927d2b504ae10539a2bfd4b4671e553d9a38a1721e78f9bc9ff979` |
| Prelude             | `c490f1ff258928f9ed87915502da5685c2c97fac5209f068e37268459c53abef` |

## Results

Median milliseconds, excluding compiler build and session startup:

| Workload                                                 | 16 systems | 64 systems |
| -------------------------------------------------------- | ---------: | ---------: |
| Full JavaScript compilation                              |      74.82 |     305.92 |
| Full native compilation, 1 thread                        |      46.35 |     198.95 |
| Full native compilation, 4 threads                       |     147.73 |   1,368.17 |
| JavaScript incremental: one helper body                  |      32.58 |     127.54 |
| JavaScript incremental: one constant                     |      32.13 |     119.75 |
| JavaScript incremental: one effect change                |      43.16 |     170.05 |
| JavaScript incremental: compatible constructor-tag shift |      40.47 |     147.89 |
| JavaScript incremental: all system bodies                |      51.94 |     188.70 |
| JavaScript incremental: trivia only                      |      15.09 |      63.45 |

Full-compilation sources are `ecsWorkload(16/64)`. Incremental sources add a
constant, a helper, and a non-storage ADT to exercise their invalidation paths.
They are related workloads, not identical inputs; do not quote their ratios as
an exact full-versus-incremental speedup.

The body edit checks one group and compiles one code entry. It reuses 44 groups
and 121 entries at 16 systems, and 92 groups and 313 entries at 64 systems. The
constant edit recompiles no code entries. Every edit sample restores the
baseline outside the timed interval; these are real alternating revisions, not
repeated-source cache hits.

For the 64-system body edit, median reported phase costs are approximately:
parse 19.79 ms, lower/context/key work 36.49 ms, check/planning/key work 23.97
ms, constant/world work 1.48 ms, codegen/preparation/key work 19.04 ms, and
link/decode 16.28 ms. Phase medians need not sum to the median total. A codegen
hit count alone therefore does not establish a fast reload.

## Reproduction and comparison rules

From the frozen checkout, invoke the existing scripts without rebuilding:

```sh
deno run --allow-read=generated,examples,std --allow-write=build --allow-run=generated/compiler/blotc compiler/native_bench.ts 7 build/native-full.json 1,4
deno run --allow-read=compiler,generated,examples,std --allow-write=build compiler/incremental_bench.ts 7 build/incremental16.json 1
deno run --allow-read=compiler,generated,examples,std --allow-write=build compiler/incremental64_bench.ts 7 build/incremental64.json 1
```

The 64-system replay is an exact copy of the original incremental benchmark,
changing only its edit baseline's first `ecsWorkload(16)` to `ecsWorkload(64)`
and the baseline's display label. It is saved with the raw evidence. The scripts
assert emitted Wasm, storage, analysis, and executed ECS behavior; incremental
type variables are compared modulo quantified alpha-renaming.

Full native timing includes source preparation, request encoding, pipes, native
lowering/checking/evaluation/codegen, and response decoding. It has two warmups.
Incremental series report compile and reload separately, use no untimed warmup
series, and exclude baseline restoration, oracle checks, seeding, and
source-file I/O. Native and JS startup are reported separately.

Future same-feature comparisons must use these frozen sources **and prelude**,
preserve correctness checks, record compiler hashes, and keep identical-source
hits separate. Measure the expanded F32/3D workload as an additional series; its
larger prelude must not silently replace this baseline.

## Native session: measurement before optimization

The first retained native cache was correct but still sent and decoded a full
syntax tree for every revision. With the same frozen source and prelude, seven
samples measured 42.79 ms for a 16-system body edit and 177.30 ms for 64
systems. Both were slower than the older JavaScript incremental path above,
despite checking just one group and compiling one code entry. The initial
evidence is retained in `build/case-study-baseline/native-session-after.json`;
its isolated checkout is `/tmp/blot-case-native-after.B0Hiwp`.

A bounded phase probe attributed approximately 90–92 ms of the 64-system native
request to decoding the 1.2 MB unchanged syntax tree, and 27–30 ms to lowering
cache keys. Group checking/keys cost about 6 ms, Wasm preparation 4 ms,
code-entry keys/compilation 4 ms, and linking 3–4 ms. These diagnostic phase
timings are not the seven-sample end-to-end series and should not be added to
its median.

The resulting change retains exact declaration trees, compares trees directly
instead of serializing source keys, and supports a patch containing ordered
retained declaration identities plus complete replacements. The host must
compute each patch against the last successfully acknowledged native revision;
failed or merely queued edits must not change that baseline. The native session
reconstructs and validates the complete source before publishing its new state.

For old U32 output comparisons, the F32 backend adds exactly three unused Wasm
function signatures (15 bytes) to the type section. The replay asserts that
exact section and verifies all function/import type indices are below two, then
removes only those unused additions before comparing the old Wasm hash. It
records both raw current and normalized hashes. Current JavaScript,
stateless-native, and retained-native bytes and storage metadata must match
exactly, without normalization; type variables may differ only by quantified
alpha-renaming. Every sample also checks preserved state and an executed ECS
transition.

`compiler/native_session_bench.ts` replays all saved edits and rejects a changed
prelude hash. Run it from an isolated current compiler checkout containing the
frozen prelude:

```sh
deno run --allow-read=generated,std,build/case-study-baseline --allow-write=build/case-study-baseline --allow-run=generated/compiler/blotc compiler/native_session_bench.ts 7 build/case-study-baseline/native-session-current.json build/case-study-baseline
```

## Production declaration-patch results

The final production path uses one typed declaration-patch request per revision,
not the scratch prototype's placeholder syntax nodes. Seven isolated samples
were captured at `2026-09-20T08:10:49Z`, after the native, protocol, session,
and background-worker tests passed. The source/prelude hashes and all output and
execution assertions above passed for every workload.

Median incremental compilation time, in milliseconds:

| Edit                         | Previous JS, 16 | Native patch, 16 | Previous JS, 64 | Native patch, 64 |
| ---------------------------- | --------------: | ---------------: | --------------: | ---------------: |
| One helper body              |           32.58 |            15.74 |          127.54 |            68.01 |
| One constant                 |           32.13 |            15.35 |          119.75 |            69.71 |
| One effect change            |           43.16 |            20.37 |          170.05 |            78.64 |
| Compatible constructor shift |           40.47 |            17.38 |          147.89 |            80.42 |
| All system bodies            |           51.94 |            33.13 |          188.70 |           146.05 |
| Trivia only                  |           15.09 |            14.29 |           63.45 |            66.55 |

The body edit still lowers one declaration, checks one group, and compiles one
code entry. It reduces latency by approximately 52% at 16 systems and 47% at 64
systems relative to the previous JavaScript cache. Against the first native
cache's 42.79/177.30 ms, it is approximately 2.7/2.6 times faster.

This is not an across-the-board speedup: trivia-only edits are essentially
unchanged, with the 64-system median slightly worse. Every revision still parses
the complete source, validates the whole declaration graph, and links the
complete artifact; the cache does not skip checking unused declarations.
Identical-source requests measured 15.58/63.71 ms and are not used as the body
edit result. The scratch probe's 58–59 ms estimate is superseded by the actual
production 68.01 ms median, not substituted for it.

For the exact same body-edit sources, current stateless native compilation
measured 46.59/209.44 ms. Wasm instantiation and immutable-world remapping added
median 0.24/0.58 ms on this three-entity fixture, producing edit-to-ready
medians 15.97/68.57 ms. These are compiler/ECS fixture results, not renderer
frame-rate or large-world measurements.

Raw samples, cache counters, current/normalized Wasm hashes, and startup values
are in `build/case-study-baseline/native-session-delta.json`. The frozen current
checkout is `/tmp/blot-case-native-delta.OH2QXY`, with the original prelude
copied into that isolated checkout only. No user installation or repository
prelude was changed for the comparison.

| Current artifact    | SHA-256                                                            |
| ------------------- | ------------------------------------------------------------------ |
| Native compiler     | `61a640d7c2828112bf07078cdae99b8159ff9f6075fb422068bfb3a1139882f6` |
| JavaScript compiler | `f071e2ddbcf63294f9d903acc3f38e7eafbcc3ee9b8f767a7ef25ec4745b4b03` |
| Parser Wasm         | `d3957b8b48a27ed134edba78d4b2e23478a4a9ee814a0295f372eea9642d4cad` |

## Native cache direction

Keep one native process and one revision RPC. Retain the prepared prelude,
declaration-local lowering results, checked dependency groups, ordered constant
results, and relocatable instruction entries in Bend. Reuse existing compiler
passes; do not duplicate inference or effect scheduling in the host.

Use stable declaration-local source identities with per-revision diagnostic
origin maps. Group keys include imported canonical type/effect interfaces and
nominal declarations. Constant keys include transitive callable bodies and the
entering evaluation budget. Code keys exclude link-time indices, tags, and
addresses; link every changed artifact against current metadata. Validate all
declarations, including unused ones, before publishing a successful state.
Failed revisions must not publish partial caches or replace the running world.
The prelude is lowered under the session-open budget; revision lowering budgets
apply to the source declarations, including retained declarations when their
previous successful lowering used a larger budget.

Driving individual jobs through Deno's existing scheduler is a useful oracle,
but would add many RPCs or transport private checked ASTs. A native session
keeps that state local. More worker threads and whole-source memoization do not
address the measured body-edit workload; neither is the first lever here.
