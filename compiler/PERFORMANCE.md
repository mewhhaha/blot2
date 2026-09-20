# Compiler performance

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
