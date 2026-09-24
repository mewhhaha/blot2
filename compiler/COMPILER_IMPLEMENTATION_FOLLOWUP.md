# Compiler implementation follow-up

2026-09-24. Baseline: `97e85036ed4f5dab805098d49f933c111735de8c`. Three
`gpt-6-sol` agents at `xhigh` implemented and reviewed the changes with
coordinator integration and independent comparisons. Native builds use Bend
2.0.27 and Clang 22.1.8 on an AMD Ryzen 7 7800X3D.

## Measured native work reduction

The native NatIndex lookup now uses a consuming loop with Bend's existing
constructor ownership operations. It preserves shared snapshots, nested values,
zero and non-power-of-two branch masks, and all 48-bit Nat keys. The transformer
checks Bend 2.0.27, the original generated case, source contracts, runtime
ownership helpers and the replacement asset before changing generated C.

Dependency and state-operation membership now use direct short-circuit work
loops. Type-variable membership stops after its first match. These remove the
source-level closure calls from the measured hot membership paths.

Five alternating pairs, each using a fresh native process and freshly loaded
16-module gdev project, gave:

| Median       |   Baseline | Lookup and membership candidate |
| ------------ | ---------: | ------------------------------: |
| Compile call | 1,205.0 ms |                      1,078.0 ms |
| Native CPU   |   1,170 ms |                        1,040 ms |
| Peak RSS     | 49,552 KiB |                      50,436 KiB |

This is a **10.5% wall-time reduction**. Every pair improved (101–158 ms). The
filesystem was warm; the compile call includes frontend preparation, transport,
native compilation and response decoding. Native process startup and source
loading are measured separately. CPU samples have 10 ms resolution. This is not
a 100–200 ms full compile.

All ten runs produced the same 192,168-byte Wasm artifact, SHA-256
`3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`. The
candidate also matched the frozen compiler in 176 native API operations across
one and four workers, including error recovery across source revisions, nominal
type witnesses, shared monomorphic helpers and distinct provider rows.
NatIndex's standalone probes passed at one and four workers, with ASan/UBSan,
shared values, high keys and matching overflow errors.

Artifacts: `build/next-lever-implementation/loops/paired.jsonl`,
`loops/api-oracle.log`, and the NatIndex probe outputs.

## Ordered binding index

A name index retains every binding, including duplicate names, and returns
selected bindings in original source order. It is shared inside one inference
component. Missing or small-component indexes use the original ordered filter.
Declaration lookup also stops at its first match.

The isolated index candidate was performance-neutral: 1,171.5 versus 1,173.5 ms
in five alternating pairs, with exact Wasm preserved. Its role in the combined
candidate is sharing selection work with the parallel read guard; the census of
333,371 binding visits does not by itself establish a native speedup.

## Guarded parallel inference

Contiguous eligible declarations infer against the same immutable snapshot,
using disjoint fresh-variable windows. The guard closes each job's read set over
raw and resolved binding variables and substitution history. After inference it
checks actual substitution writes against other jobs' reads and writes. Shared
reads are permitted. Conflicts, failed inference, invalid variable ownership or
window exhaustion replay the entire run in its original serial order.

Successful outcomes are rebased to the serial fresh counter and their
substitution deltas appended chronologically. The final solve/generalization
boundary is unchanged. Duplicate declaration names retain first-lookup behavior.
The alias traversal skips visited nodes, and staged segments share the immutable
catalog guard.

The read guard now queries existing substitution indexes instead of rebuilding
an adjacency index from the complete history for every group. It merges all type
and row versions for each reached variable in descending position order; using
only the latest version would be unsound. The isolated gdev comparison matched
all 262 read sets and the full output. It replaced 87,995 history visits with
5,538 index lookups and 2,276 visited versions. An unreachable replacement that
exceeds the structural budget no longer forces a serial replay; failures on
reached replacements still do.

The first read-disjoint prototype admitted 24 batches / 59 jobs in gdev. The
actual-write guard admits 79 batches / 262 jobs in the isolated JS experiment,
with no conflicts or replay and exactly identical output. These are job counts,
not speedups. Twelve direct regressions cover shared reads, conflicting type and
effect-row writes, aliases, duplicate names, speculative failures and ordered
diagnostics. Native regression cases cover the same admission/fallback boundary.

Guard preparation, result rebasing and repeated body-reference walks add work.
Native timing is required before treating additional parallelism as a
performance improvement.

## Independent typed-body replay

The first supported body is the import-free `Type.eq` implementation. Its source
is inferred independently, retaining unresolved type choices and match coverage.
Each use verifies the complete expanded clone and exact nominal catalog, maps
all fresh type/row variables and expression identities, preserves source
subjects and the original allocation count, and unifies with the caller's seeded
binding. Unsupported bodies, changed catalogs, failed guards and exhausted
48-bit allocation space use ordinary inference.

The initial integration missed selection-time clones. Threading retained schemes
through the solver fixes that: all **28 gdev Type.eq clones** replay
successfully, with zero misses and exactly unchanged full checked output. Five
focused tests compare resolved inference, deferred obligations, source subjects
and next counters with ordinary inference; they also cover repeated differently
typed uses, altered bodies, catalog changes and overflow fallback.

This removes 28 selection-time body-inference calls. It does **not** remove the
28 emitted clones or their final checking pass. `Entry.contains` symbolic
expansion can be inferred independently while retaining `eq` and `contains`
obligations, but step-dependent identity mapping is still a separate experiment.
No production Entry replay or complete early builder evaluator is claimed.

## Integrated native measurements

The final indexed-guard build was measured in two separate five-pair runs while
an unrelated eight-worker CPU workload was active. Each sample used a fresh
native process and loaded gdev project; ordering alternated within pairs.

| Comparison                         | Reference wall | Final wall | Reference CPU | Final CPU |
| ---------------------------------- | -------------: | ---------: | ------------: | --------: |
| Baseline vs final, one worker each |     1,627.5 ms | 1,520.6 ms |      1,550 ms |  1,430 ms |
| Final, one vs four workers         |     1,446.0 ms | 1,278.8 ms |      1,360 ms |  1,750 ms |

The integrated build reduced the one-worker median by **6.6%** in this loaded
run (four pairs improved; one differed by -3.3 ms). Four workers reduced the
median by **11.6%** in the separate worker comparison, and improved every pair
by 72–262 ms. Four workers used more CPU and memory: median peak RSS was 70,028
KiB versus 50,768 KiB. The process API still defaults to one worker; callers can
select four with its existing `threads: 4` option.

All 20 samples produced the exact baseline Wasm hash. These loaded absolute
times cannot be compared directly with the earlier quiet 1,078 ms minimal
candidate. They establish neither a quiet latency for the integrated compiler
nor the 100–200 ms target.

Artifacts: `build/next-lever-implementation/final_index/baseline-paired.jsonl`
and `final_index/threads-paired.jsonl`.

## Final integration gates

The final indexed-guard build passed **721 compiler and transformer tests**,
**24 gdev tests**, the Bend proof, native ownership regressions at one and four
workers, and **176 native API comparisons**. TypeScript checks, editor and
study-source tests passed. The native kernel probes passed their direct
differential, ownership, overflow, ASan and UBSan checks. Native and all three
JS artifacts were built from frozen sources, with source fingerprints checked
before installation.

The final indexed build's complete checked gdev result remains exactly
identical: 3,360,009 JSON bytes, SHA-256
`dae40eb1448855bc156f9c9bb043a68329a33c8782adeef71ca1520d71015c32`.

An independent final source review found no concrete soundness, identity
rebasing, ownership, fallback or public API regression. Substitution history and
indexes must remain consistent, as maintained by the existing constructor and
append paths.
