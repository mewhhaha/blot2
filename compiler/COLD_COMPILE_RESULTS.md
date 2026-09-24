# Cold compilation results

The 500 ms target is **not met**. The implemented changes reduce native CPU work
substantially, but cold compilation and body edits still take seconds. The next
architecture and the evidence behind it are in
[the cold-compilation plan](COLD_COMPILE_PLAN.md).

## Final production candidate

Three alternating pairs used fresh native compiler processes, fresh project
loads, one native worker, and the same 16-module gdev source. The runner
attempted to keep only its own processes at normal batch scheduling; automatic
desktop priority changes and unrelated work continued. The benchmark host
process remained alive and filesystem caches were not flushed. The table
separates compiler CPU from wall time.

| Fresh stateless request   | Median native CPU | Median compile-call wall |
| ------------------------- | ----------------: | -----------------------: |
| Saved pre-change compiler |          6,270 ms |                11,048 ms |
| Current compiler          |          3,410 ms |                 8,122 ms |

The reduction between CPU medians is 45.6%. Earlier, less contended windows
measured approximately 2.8–3.0 seconds of current compiler CPU. These windows
must not be combined into a wall-time speedup claim. Compile-call wall excludes
the separately recorded project load and native/frontend initialization; CPU
counts only the native child, at 10 ms resolution. Even native CPU alone is far
above the target.

Every result is the same 192,168-byte Wasm artifact, SHA-256
`3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`. Raw samples:
[final cold pairs](../build/gdev-cold-investigation/final-cold-pairs.jsonl).

A separate one-worker phase trace of the current compiler produced the same
artifact in 3,230 ms of native CPU (the adjacent uninstrumented control used
3,330 ms). Its coarse CPU intervals were:

| Interval                                       | Native CPU |
| ---------------------------------------------- | ---------: |
| Decode, lowering and template graph            |     122 ms |
| Initial source-shape checking                  |     205 ms |
| Shared specialization preparation              |     501 ms |
| Remaining specialization                       |   1,055 ms |
| Final dependency planning and checking         |   1,019 ms |
| Constant evaluation                            |      80 ms |
| Wasm preparation, code generation and response |     241 ms |

These are boundary-to-boundary diagnostic intervals, not independent function
self times; frontend project loading is outside them. Type work and
specialization dominate. Ordinary constant evaluation is about 2.5% of this
traced native request. Raw events and paired control:
[phase events](../build/gdev-cold-investigation/third-phase-events.jsonl),
[phase pair](../build/gdev-cold-investigation/third-phase-pair.jsonl).

Implemented changes:

- Validate shared type/operation catalogs once per checking plan.
- Defer public-export refresh until final checking on the stateless source path,
  avoiding an intermediate inference pass. Programs without deferred dispatch
  also skip the initial shape-inference pass.
- Short-circuit dependency membership and avoid repeated full-string prefixes
  during indexed lookup.
- Compare native immutable strings while borrowing their nodes and retaining
  both roots. The generated-C transform checks the Bend 2.0.24 ownership and
  runtime contracts before applying it.
- Use numeric keys for substitution histories while retaining their exact
  chronological semantics. Its isolated lookup benchmark improved, but its
  whole-gdev cold benefit was within the observed variation.
- Use exact, monotonic nominal-version tokens in persistent group keys and
  compare the operation catalog once per revision. Failed edits publish no cache
  state.

## Persistent project requests

The project session still uses the existing cached specialization pipeline; the
stateless export-refresh change does not apply to that path. Establishing the
cache remains expensive. Two alternating session pairs measured the latest
compact-key/numeric-index changes against the preceding optimized candidate:

| Request               | Previous native CPU median | Current native CPU median |
| --------------------- | -------------------------: | ------------------------: |
| First project request |                   7,260 ms |                  7,580 ms |
| Motion body edit      |                   4,920 ms |                  4,580 ms |
| Revert that edit      |                   5,250 ms |                  5,075 ms |

The edit improvement is modest; the first request did not improve. The edit
reuses 843 of 844 final checking groups and 1,243 of 1,244 code entries, yet
still pays for substantial earlier work. Unchanged requests used no native CPU
and took 43–72 ms wall in the current candidate. These are result-cache hits,
not cold compilation. Both original and edited Wasm hashes matched the saved
oracles. Raw samples:
[project pairs](../build/gdev-cold-investigation/third-project-pairs.jsonl).

## Gdev runtime

Gdev now retains parsed source and an exact unchanged-source artifact cache, but
uses a fresh stateless compiler for changed source. Two alternating pairs of
actual `createBlotRuntime` calls used the same current compiler and application:

| Runtime path                  | Median native CPU | Median startup wall | Unchanged reload wall |
| ----------------------------- | ----------------: | ------------------: | --------------------: |
| Previous persistent session   |          7,250 ms |            9,806 ms |              43–55 ms |
| Current stateless compilation |          3,155 ms |            4,329 ms |               5–15 ms |

These startup calls include source loading, compilation, guest instantiation,
contract checks and the first validated frame. They exclude Deno host startup;
filesystem caches were not flushed, and unrelated desktop load continued. This
is a runtime-path comparison using one compiler, separate from the compiler
version comparison above. The stateless path uses 56.5% less native CPU between
these medians. Unchanged reloads are artifact reuse, not inference. The runtime
keeps the current guest and state while compiling and on failed edits. Raw data:
[runtime pairs](../build/gdev-cold-investigation/runtime-pairs.jsonl).

## Reuse experiments and validation

An isolated inference-evidence experiment reused 103 of 844 final groups with
exact checked-module equality in a conservatively filtered JavaScript probe. It
is not enabled in production: it covers too little of gdev to close the gap, and
extending it requires retaining body provenance, solved choices, type/effect
obligations and imported interfaces together.

A second isolated experiment caches the initial source-shape check across edits.
It reuses 259 of 260 groups for the motion edit with exact analysis parity. The
subsequent native test found no benefit: across six alternating body edits,
median native CPU was 5,140 ms for C3 and 5,225 ms for the prototype. The first
request was also slower (6,920 vs 7,290 ms), and RSS after the sixth edit was
about 12 MiB higher. Full artifacts matched on all seven revisions. This cache
remains isolated; a high reuse count did not reduce elapsed work. See the
[shape-cache report](../build/gdev-shape-cache/README.md).

An isolated iterative native string-index lookup reduced cold native CPU from
median 3,400 to 3,120 ms (8.2%) in three alternating pairs. All six gdev
artifacts matched exactly, as did focused long-prefix, Unicode module-path and
four-thread checks. It remains an experiment: its modest benefit does not close
the cold gap or justify extending the pinned generated-C contract in this pass.
Automatic priority demotion prevents a reliable wall-speedup comparison. Raw
data: [index pairs](../build/gdev-cold-investigation/index_cold_pairs.jsonl).

The larger lead is repeated specialization: 492 retained clones have 151
distinct per-origin signatures. Identical signatures alone do not establish
identical behavior. The plan therefore keys saved constraint instantiations by
source version, concrete type/effect arguments, selected implementations and
captured-value dependencies before generating clones.

`bend PROOF.bend` passes. All 668 compiler tests and all 24 gdev tests pass,
including state preservation through 1,200 frames and recompilation. The native
ownership, Unicode, parallel, rollback, substitution and cache tests are
recorded in
[the compiler test log](../build/gdev-cold-investigation/third-compiler-tests.log).
The 24 gdev tests also pass after switching its runtime compilation path:
[runtime test log](../build/gdev-cold-investigation/stateless-gdev-tests.log).

Final native executable SHA-256:
`eb3a04d0fffb31b389de21d6f65b24198c11d68956bd9d29c79349f68cc467a5`.

Reproduce the cold pairs from the repository root:

```sh
python3 build/gdev-checkpoint/run_normal_priority.py deno run --allow-all \
  build/gdev-cold-investigation/native_pair.ts \
  build/gdev-cold500-baseline/generated/compiler/blotc \
  generated/compiler/blotc 3
```

The saved baseline, isolated experiments and raw logs are local investigation
artifacts under `build/`; they are not required by production compilation.
