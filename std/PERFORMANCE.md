# Standard library API and performance audit

The October 2026 audit covers `std/prelude`, `std/array`, `std/list`,
`std/vector`, their compiler lowering, and the Deno compiler/guest boundary.
The changes remove avoidable demand objects, repeated collection copying and
vector intermediates. They preserve immutable values, callback order, numeric
behavior and fresh-versus-retained compilation parity.

The first measurements compare `775d370` with `86a527b`. The
[runtime follow-up](#runtime-follow-up) compares `86a527b` with the next working
revision and adds staged-construction measurements.

## API behavior

Collection transformations keep their collection argument last for pipelines.
`List a` and `Array a` remain distinct. Lists support traversal and construction;
only arrays expose indexing, checked `get`/`set`, and trapping `at`/`replace`.
Conversions are explicit. Numeric arrays cross the guest ABI by copying, so
host mutation cannot alter retained guest values.

List `fold_left` now propagates reducer effects, matching the array fold.
The added list `any` and `all` propagate effects and stop at the first deciding
element. Empty inputs return false and true respectively without invoking the
callback. List `filter` retains effectful predicates and visits each element
once in order. Array construction and collection `map`/`generate` retain their
pure callback contracts.

`Result.unwrap_or_else` now matches the existing Maybe operation: its fallback
is deferred until failure. `unwrap_or` remains eager. `@demand` is the preferred
spelling for evaluating a deferred argument; `@force` remains an alias. A
successful demand is shared, whereas an ordinary callback runs each time it is
called. See the [demand design](../zig-native/DEMANDS.md) for the full contract
and remaining control-flow questions.

The public compiler API remains asynchronous. Keep a `createCompiler` instance
open across edits to retain work, and dispose it when finished. The reference
now documents `prelude: null`, directory aliases and source validation using the
Zig API. Guest lifetime, host exceptions and queued project requests remain
covered by their existing regression suites.

## Implementation changes

| Area | Change and cost boundary |
| --- | --- |
| `&&`, `||`, simple demand combinators | Known, fully applied bodies use branches and locals. Admission examines at most 96 expression/pattern nodes and never matches operator names. Repeated demands share a local result, reset per call. |
| `prefix_sums` | Recursive pair sums replace full-array doubling passes. Total work and intermediate array storage are linear, including constant evaluation. U32 wrapping behavior is unchanged. |
| `indices`, `filter`, `filter_map` | One runtime traversal collects into a private chunked list, followed by one array conversion. Predicates/transforms run once per input element. |
| Conditional list construction | Ownership flows through `if let` branches when no previous version remains live. Surviving aliases and closure captures still prevent mutation. |
| `list.append`, `list.prepend`, `array.replace` | Direct wrappers and their aliases preserve the intrinsic's ownership optimization. A fully applied wrapper must use each parameter exactly once as an intrinsic operand. Actual arguments still evaluate in written order. Exclusive replacement, including direct `@array.set`, updates the existing allocation. |
| Array `push`, `concat`, `flatten` | `push` uses the append primitive. `concat` avoids intermediate chunk arrays. `flatten` counts lengths without allocating prefix-sum arrays. Both check length overflow before filling the result. Runtime array append still copies. |
| Staged append/prepend | Session-owned buffers reserve slack at both ends. The latest span grows into unused slots; older spans remain immutable. Geometric growth replaces repeated prefix copies. Forks from older versions and indexed replacements still copy. |
| `Result.iterate` | Pattern branches update the state or return directly, removing the tuple/Maybe scaffolding from each iteration. State, result and error types may differ; callback effects and early termination are preserved. |
| Vector `lerp` | Vec2/Vec3 construct one result from scalar interpolation, preserving the existing F32 operation order. |
| `F32.tan` | Sine and cosine share one angle reduction. The documented finite domain and nonfinite behavior remain unchanged. |

Inlining now records each consumed declaration in the caller's code artifact.
Retained compilation checks its exact executable projection and transitive
source dependencies, including when a dependency seed is rebuilt. Changed
callee bodies invalidate emitted callers even when their types are unchanged.
Unrelated declaration edits may retain them; moved IDs and catalog changes
remain conservative.

## Reproducing library measurements

The baseline is commit
`775d3707d27c5c5d64504206c6b3824a458d8929`. The paired harness pins both native
executables and all four standard-library files, checks guest results, and saves
every sample and compilation record:

```sh
deno run --allow-read --allow-write --allow-run scripts/bench_stdlib.ts \
  zig-native/zig-out/bin/blotc std build/stdlib-bench \
  /path/to/baseline/blotc /path/to/baseline/std
```

Use a separately built baseline; changing only library files would miss the
ownership and demand improvements. The executable's build identity rejects
incompatible dependency bundles.

Runtime samples include guest ABI copies. Each variant receives 1,000 warmups,
then 31 alternating samples of 16 calls. Inputs contain 8,193 elements or loop
iterations, except list append, which uses 1,025. Reported memory is committed
guest pages after repeated calls, not total allocated bytes or compiler RSS.
The harness's individual compilation records use a warm filesystem and are not
a cold compilation distribution.

The first audit used Zig 0.17.0, Deno 2.9.7 and V8 15.0.245.2-rusty.
Its resulting compiler identity was
`c827798cae5e6276badeaf83bc8abd341634741c29f5047855e62ea688508377`;
the baseline identity was
`2d8050d273b5baa98107c2a38d4144b92885bbe16d0e510e5b2b41b23968c850`.

| Runtime probe | Before ms | After ms | Guest memory before KiB | After KiB |
| --- | ---: | ---: | ---: | ---: |
| Inclusive prefix sums | 0.259 | 0.064 | 1,088 | 384 |
| Selected indices, including the input flag map | 0.564 | 0.054 | 1,280 | 320 |
| Array filter | 0.367 | 0.040 | 1,280 | 256 |
| Array filter_map | 0.502 | 0.065 | 1,600 | 512 |
| Array concat | 0.026 | 0.026 | 320 | 256 |
| Array flatten | 0.025 | 0.024 | 320 | 320 |
| Array push | 0.017 | 0.003 | 256 | 192 |
| List append loop, 1,025 elements | 2.184 | 0.008 | 5,312 | 128 |
| Vec3 interpolation loop | 0.369 | 0.193 | 3,200 | 2,176 |
| Result iteration loop | 0.172 | 0.184 | 128 | 128 |
| Array of F32 tangents | 0.115 | 0.093 | 256 | 256 |

Filtering is about nine times faster in this probe, filter_map about eight,
prefix sums about four, and vector interpolation about two. The list builder
previously copied its growing contents on each library call; it now uses the
same exclusive chunk reuse as spread syntax. That particular cost change
accounts for its much larger gain. Concat and flatten have similar runtime.
Result iteration has byte-identical Wasm; its differing measured medians do
not indicate an implementation change.

The scalar Boolean probes shrink from 1,579 to 101 Wasm bytes, with two emitted
functions and no memory or function table. Explicit `if` remains 95 bytes.
Source and compiled-dependency builds produce identical output for all four
conjunction/disjunction probes. These module sizes include shared helper code;
they are not a per-operator byte cost in a larger application.

Raw samples, hashes, generated Wasm and full compilation records are retained
locally in `build/stdlib-review/paired/report.json` and
`build/stdlib-review/demands/`. Build artifacts are ignored by Git; the harness
above reproduces the comparison from the two source/compiler versions.

## Game compilation

Compilation uses one pinned gdev snapshot for both variants: 27 loaded source
files including the prelude, about 193 KB total. The source manifest is
`build/stdlib-review/gdev-snapshot/sources.json`, SHA-256
`57d4f3b36a270290472132339c59a9b29158fa04a35306f9b1e4d7ab88fc8a4c`.
Game sources continued changing during the audit; this comparison excludes the
later rock/grid additions exercised by the final integration tests.

| Compilation boundary | Before median ms | After median ms |
| --- | ---: | ---: |
| Fresh CLI, source dependencies | 350.8 | 348.6 |
| Fresh CLI, precompiled dependencies | 316.6 | 312.7 |
| First retained edit, source dependencies | 122.6 | 118.2 |
| Later retained edit, source dependencies | 117.7 | 122.6 |
| First retained edit, precompiled dependencies | 121.0 | 118.4 |
| Later retained edit, precompiled dependencies | 116.8 | 115.4 |

These results show similar compiler latency. Fresh source builds ranged from
345.0 to 354.2 ms after the changes; dependency builds ranged from 311.3 to
323.1 ms. Peak process RSS was about 44 MiB in both variants. Generated game
Wasm fell from 249,128 to 245,282 bytes.

Each cold lane has five alternating fresh process runs, including output writing
and teardown. Executable, Blot source and used bundle pages were evicted and
checked nonresident before launch; system libraries and filesystem metadata were
not controlled. Bundle creation is excluded and measured separately in its
compilation log. Full samples, CPU time and RSS are in
`build/stdlib-review/game-bench/report.json`.

Retained timings are public build-request round trips, measured in three
sessions per lane with warm filesystem caches. Every edited output is checked
against a fresh build. Process/session population is recorded separately, not
hidden in edit times. Adding Wasm validation, hashing and output writing gives
current edit medians of about 133–143 ms; no-op request medians are 1.3–1.7 ms
before those output costs. The 500 ms cold target is met on this snapshot;
**the under-100 ms incremental target is still unmet**. Full records are in
`build/stdlib-review/game-bench/incremental.json`.

## Runtime follow-up

The follow-up baseline is
`86a527b97c32331993c4a006da2c982a7336c365`, with compiler identity
`c827798cae5e6276badeaf83bc8abd341634741c29f5047855e62ea688508377`.
The resulting compiler identity is
`364e41839ea2575176f92ce897a7652f187e7f50dedac97570093d40e1162989`.
Tool versions and runtime sampling boundaries match the first audit. The added
replacement probe performs 1,025 updates to a 1,025-element array.

| Runtime probe | Before ms | After ms | Guest memory before KiB | After KiB |
| --- | ---: | ---: | ---: | ---: |
| Array replacement loop | 0.0831 | 0.00160 | 8,320 | 128 |
| Result iteration loop | 0.1809 | 0.1245 | 128 | 128 |
| Array of F32 tangents | 0.1031 | 0.0905 | 256 | 256 |
| Array flatten | 0.0266 | 0.0259 | 320 | 320 |

Replacement is about 52 times faster in this probe because it no longer copies
the whole array on every update. Result iteration takes about 31% less time;
the array-returning benchmark retains its guest memory footprint. A scalar-only
iteration probe emits no guest memory. Flatten removes temporary metadata, with
similar timing and committed pages on this input. The other paired probes have
similar time and memory to the baseline; no speedup is claimed for them.

The current harness also runs seven alternating fresh CLI processes for each
staged-builder size. Filesystem caches are warm. Wall time includes process
launch, compilation, output writing and teardown; it excludes executing the
result, which is checked separately. Default evaluator limits apply.

| Staged appends | Before wall ms | After wall ms | Before peak compiler bytes | After peak compiler bytes |
| --- | ---: | ---: | ---: | ---: |
| 256 | 3.89 | 3.84 | 951,978 | 940,186 |
| 1,024 | 5.04 | 4.25 | 2,769,868 | 940,188 |
| 4,096 | Failed: storage budget | 5.95 | 19,231,012 | 969,628 |
| 8,193 | Failed: storage budget | 8.58 | 19,231,012 | 1,601,956 |

These are requested compiler bytes, not process RSS or guest memory. The failed
baseline runs are not timings for equivalent completed work. Growth reserves
space geometrically in the existing child arena, and every reserved slot counts
against its storage limit. It never overwrites a published element, even when
an older version survives in a closure or cached value. Small builds retain the
fixed cost of loading and checking the prelude.

Reproduce this comparison with the harness above and the `86a527b` baseline.
Raw samples, source/binary hashes, compilation records and generated Wasm are
retained locally in `build/runtime-review/paired/`. The harness records cumulative
allocation bytes and counts as well as peak requested bytes.

Public examples now use demand parameters and `@demand`, array indexing and
updates, tuple patterns, and `if let` where appropriate. Boolean decisions in
the prelude use `if`; F32 comparison order, right-biased ties and NaN behavior
remain unchanged. Underlying intrinsic definitions and compatibility tests retain
their purpose-specific spellings.

## Earlier verification

`deno task test:compiler` passes: native production tests, packaged compiler,
and all 464 guest/client tests. The new execution tests cover wrapping sums,
empty/chunk-boundary collections, alias snapshots, effects, early exits,
repeated demands, loop memo reset, F32 behavior and retained-body edits. The
follow-up adds direct/wrapped replacements, iterator borrows, staged growth,
branched/captured values and allocation-failure cleanup. All modified public
examples compile and execute with their expected results.
Storage bounds detect growing-copy regressions without timing assertions.

The current gdev integration suite passes all 60 tests. Game sources continued
changing independently; no gdev source edits were made by this audit. Zig
Analyzer now reports zero errors and 121 existing warnings,
with none in the new optimization files. Formatting, type checking for the
benchmark harness and `git diff --check` pass.

## Remaining costs

- Partially applied, escaping, forwarded and callee-loop demands still use
  runtime cells. Bounded expression matches now qualify for local demand reuse.
- Unknown callbacks retain indirect calls. Small known typed functions and
  callbacks use ordinary source inlining/direct calls with bounded expansion.
- Scalar replacement covers small, fully initialized, nonescaping aggregates;
  values crossing calls/ABI/GC roots and mutation through aliases remain boxed.
- Contiguous array append copies; shared list edits now detach a logarithmic
  path and one leaf. Exclusive list edits reuse their tree path.
- Staged indexed regions admit finite nested loops with one collection and
  scalar carries. Observed intermediate versions, arbitrary control flow and
  multiple collection carries keep immutable evaluation. This is independent
  of runtime ownership.
- Code caching remains conservative for moved IDs, changed catalogs and
  unsupported capture/provider/generative domains. Incremental compile latency
  must be measured separately from guest runtime.

## The ten optimization targets

The table below preserves the starting measurements and acceptance goals for
this pass. All implementations are generic compiler/runtime mechanisms; this
pass makes no changes to prelude definitions and recognizes none of their spellings.

The following measurements use the follow-up compiler above, before the ten
changes. Results for the new implementation follow the table.

| Priority | Target | Evidence and acceptance goal |
| --- | --- | --- |
| 1 | Carry ownership through checked updates and nested fields | At 1,025 elements, `values.set(i)(x)` takes 0.0823 ms and 8,448 KiB; `world.values[i] := x` takes 0.0710 ms and 8,384 KiB. Direct replacement takes 0.00148 ms and 128 KiB. Propagate exclusive ownership through the successful Maybe branch and each uniquely owned field, while retaining old aliases and failure behavior. |
| 2 | Preserve ownership across early loop exits | Adding a possible `break` changes the same 1,025-element list builder from 0.00678 ms / 128 KiB to 1.898 ms / 5,312 KiB, even when the break is not taken. The proof currently marks all carries as escaped for a loop that can exit. Model exit values explicitly; executed and untaken exits must preserve snapshots. |
| 3 | Make staged indexed construction linear | A 1,024-element indexed builder peaks at 4,814,238 requested compiler bytes; 4,096 elements exceed the child-slot budget. Introduce unpublished builder storage or a bulk construction path, then freeze surviving values. Published evaluator spans must remain immutable. This should also remove the staged `concat`/`flatten` copying problem. |
| 4 | Keep small records and tuples in scalar locals | The 8,193-step Vec3 loop still commits 2,176 KiB and takes 0.192 ms. Lower unescaped Vec2/Vec3/product fields to locals and loop carries instead of repeatedly allocating record payloads and nominal wrappers. Preserve F32 operation order and existing public ABI behavior. |
| 5 | Specialize known collection callbacks | `array.map (fn x => x + 1)` takes 0.0211 ms / 256 KiB for 8,193 elements; an explicit update loop takes 0.0118 ms / 192 KiB. `arrayFill` emits `call_indirect` for every generated element. Inline or directly call proven callback targets, capturing their arguments once. Unknown callbacks retain the general path. |
| 6 | Eliminate demand cells through matches | The 8,193-step successful `Maybe.unwrap_or_else` loop takes 0.0793 ms / 896 KiB; the equivalent explicit match takes 0.0205 ms / 384 KiB. Extend bounded demand admission to constructor matches while preserving skipped effects, trap order and once-only evaluation. |
| 7 | Right-size small lists and full chunks | Retaining 1,025 singleton lists commits 2,240 KiB, versus 128 KiB for singleton arrays. Every nonempty list gets a 256-slot chunk. A full chunk requests 1,040 bytes; with the allocator header it enters a 2,048-byte size class. Evaluate inline/smaller first chunks and capacities aligned with allocator classes; measure both singleton-heavy and long-list workloads. |
| 8 | Share structure between list versions | Retaining all 1,025 list prefixes costs 1.924 ms and 5,312 KiB. A shared edit currently copies the entire chain. Use immutable shared chunks with copied paths, or another persistent representation, to make branching construction subquadratic while keeping exclusive builders fast. List indexing is not required. |
| 9 | Cache code containing static captures | `requireFreshCode` deliberately excludes code jobs whose static captures are missing from their keys. Give retained captures complete value/evidence identities so unrelated edits can reuse these jobs; changed staged values, providers and nominal identities must still invalidate them. This target comes from code inspection, not a measured speedup. |
| 10 | Track inlined bodies individually | `readInlineBody` records whole owning modules, and fragment admission blocks callers when any recorded module changes. Record the consumed body and its semantic dependencies, with early cutoff when those results are unchanged. An unrelated helper edit should retain caller code; a consumed body edit must rebuild it. Measure bookkeeping cost as well as reuse. |

The runtime probes are in
[runtime_costs.blot](../scripts/fixtures/runtime_costs.blot). Reproduce them with:

```sh
deno run --allow-read --allow-write --allow-run scripts/bench_runtime_costs.ts \
  zig-native/zig-out/bin/blotc std build/runtime-costs
```

Each probe has an independent guest instance of the same module, 1,000 warmups
and 31 alternating samples of 16 calls. Results are checked before timing. The
report includes all samples, compiler/source hashes and compilation counters.
Guest memory means committed Wasm pages, including temporary capacity; it is
not cumulative allocation or compiler RSS. The staged-builder figures above
are separate individual compiler runs, not a timing distribution. Local evidence
is retained in `build/reinstall/runtime-costs/` and
`build/reinstall/staged-updates-{1024,4096}.*`.

Relevant implementation boundaries are
[ownership analysis](../zig-native/src/owned_arrays.zig),
[Wasm emission](../zig-native/src/core_backend.zig),
[constant evaluation](../zig-native/src/core_eval.zig),
[demand admission](../zig-native/src/demand_inline.zig),
[list layout](../zig-native/src/list_runtime.zig),
[code keys](../zig-native/src/code_artifacts.zig) and
[fragment admission](../zig-native/src/artifact_fragment.zig).

## Results of the ten general optimizations

The baseline is the frozen working compiler with identity
`364e41839ea2575176f92ce897a7652f187e7f50dedac97570093d40e1162989`.
The resulting compiler identity is
`b3056fea5d681f7b05afc915104c1a1e4aebf577ddde994aa9408a823031e6b0`.
Every standard-library `.blot` file is byte-identical between these two inputs.
The improvements follow typed structure, intrinsic operations, ownership and
complete dependency evidence; no prelude names select an optimization.

| Target | Implemented behavior |
| --- | --- |
| 1–2: ownership | Checked wrappers with arbitrary success/failure constructors, nested uniquely owned paths, and explicit loop exit edges retain ownership. Extracted inner arrays, surviving aliases and closure captures prevent mutation of their snapshots. |
| 3: staged construction | A proven private indexed region copies its input once, updates scratch through finite nested loops and scalar carries, then freezes once. Observed intermediate versions use immutable evaluation. |
| 4: small aggregates | Fully initialized, nonescaping records, tuples and nominal wrappers use scalar locals, including separate loop versions. Calls, public ABI values, unknown offsets and GC roots stay boxed. |
| 5–6: calls and demands | Known callbacks use direct calls with captured arguments; bounded inlining exposes aggregate results inside loops. Constructor matches and guards qualify for local demand memoization, preserving skipped effects and once-only evaluation. |
| 7–8: lists | Persistent balanced trees use right-sized leaves of at most 248 words. Shared edits copy a path and one leaf; exclusive edits reuse their nodes. Both old and new versions can subsequently be consumed independently. |
| 9–10: retained code | Static captures require complete value/evidence graph equality. Inlined dependencies name consumed declarations. Unrelated body edits can retain code; changed executable bodies or capture values invalidate it. |

| Runtime probe | Before ms | After ms | Guest memory before KiB | After KiB |
| --- | ---: | ---: | ---: | ---: |
| Checked array updates | 0.08188 | 0.00171 | 8,448 | 128 |
| Nested field updates | 0.07097 | 0.00196 | 8,384 | 128 |
| List append with a possible break | 1.86551 | 0.00884 | 5,312 | 128 |
| Retaining every list prefix | 1.87403 | 0.04459 | 5,312 | 960 |
| Retaining singleton lists | 0.03133 | 0.01475 | 2,240 | 256 |
| Successful constructor demand match | 0.07811 | 0.00180 | 896 | 64 |
| Known callback array map | 0.02118 | 0.00749 | 256 | 256 |
| Vec3 interpolation loop | 0.19222 | 0.03437 | 2,176 | 128 |
| Exclusive list append | 0.00667 | 0.00882 | 128 | 128 |

These use the probe sizes and sampling boundary documented above. Probe order
alternates within each compiler run; compiler variants run separately. Ratios
are specific to these inputs. Checked updates are about 48 times faster,
shared-prefix construction 42, known callback map 2.8, and vector interpolation
5.6. Exclusive list append is about 32% slower: maintaining the persistent tree
adds work even when no snapshot survives. Its committed memory remains 128 KiB.
Direct replacement and explicit array loops have similar time and memory.

Staged indexed construction now completes at 4,096 elements under the default
limits. Five alternating fresh CLI runs per variant/size use warm filesystem
caches and include process startup, writing and teardown. Generated answers are
executed and checked separately from timing.

| Indexed elements | Before wall ms | After wall ms | Before peak compiler bytes | After peak compiler bytes |
| --- | ---: | ---: | ---: | ---: |
| 1,024 | 7.49 | 6.01 | 4,814,774 | 1,301,255 |
| 4,096 | Failed: storage budget | 10.37 | 17,883,062 | 1,301,255 |

Requested compiler bytes are distinct from process RSS and guest memory. A
failed baseline is not equivalent completed work. Executed regressions also
cover nested loops, staged concat/flatten, preserved input aliases and repeated
updates to the same index.

Ordinary source inlining uses a four-node budget, expanded to 64 for aggregate
results inside loops or known callback arguments. Expansion is limited to three
nested calls and stops beyond 4,096 emitted instructions. This keeps source
helpers general while limiting code growth and repeated refinement. Within one
compile, the code, principal and query paths share semantic validation only for
the exact same source owners and admission options. Executable body and captured
value validation remain additional requirements.

The final game comparison uses the same pinned snapshot and measurement
boundaries as the earlier game audit. Filesystem eviction, public request timing,
population costs and fresh/retained Wasm equality are recorded separately.

| Compilation boundary | Before median ms | After median ms |
| --- | ---: | ---: |
| Fresh CLI, source dependencies | 300.6 | 315.0 |
| Fresh CLI, precompiled dependencies | 267.8 | 283.3 |
| First retained edit, source dependencies | 96.2 | 106.0 |
| Later retained edit, source dependencies | 93.1 | 101.0 |
| First retained edit, precompiled dependencies | 95.6 | 106.7 |
| Later retained edit, precompiled dependencies | 93.8 | 102.2 |

Peak RSS stays about 44 MiB; Wasm grows from 244,033 to 280,907 bytes. No-op
requests take about 1.3 ms, excluding validation, hashing and writing the
returned bytes. Runtime optimization adds roughly 5–6% to fresh compilation and
8–12% to these edits. **The 500 ms cold target is met on this snapshot; the
under-100 ms edit target is not.** Static-capture and per-body cache tests prove
actual reuse and invalidation, but this game result does not establish a net
compiler speedup from the ten changes.

The frozen baseline and final raw reports are retained locally under
`build/general-optimizations/before/`, `runtime-before/`, `final-runtime/` and
`final-game-bench/` and `final-staged/`. Reports contain all samples, binary/source hashes, output
hashes and work counters. They exclude unrelated later changes to live gdev.

`deno task test:compiler` passes all 1,023 native tests and 471 guest/client
tests, including allocation-failure sweeps, alias/effect/exit laws and exact
fresh-versus-retained output checks. Zig Analyzer reports zero errors and the
same 121 warnings as the starting tree. All 73 live gdev tests are covered and
passing: the restricted run passed 64; nine renderer tests failed because its
graphics adapter lacked `VIEW_FORMATS`, then all 13 renderer tests passed with
normal GPU access. No gdev source changes were made in this pass.

The packaged native compiler matches the verified release binary. The standalone
CLI was rebuilt, checked by compiling and executing the 4,096-element staged
builder, and installed at `~/.local/bin/blot`. New gdev compiler sessions use
the updated workspace package. Logs are in `build/general-optimizations/`.
