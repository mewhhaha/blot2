# Blot source compilation latency

Baseline: main `ac59fb68f98780e168ce01fa39410b1a6ef54efd`.

This work measures compilation of Blot source to Wasm. It is separate from
building the compiler executable and from executing the generated program. The
runtime-performance PR is not included in this branch.

## Changes under measurement

Persistent symbol insertion now descends once while keeping a cursor in the
qualified name. A path of sibling nodes rebuilds only the visited branches. The
first differing character determines where a new leaf is spliced. Existing
Base.Map tree shape, traversal order, replacement behavior and persistent
snapshots are preserved. The old insertion remains as a differential oracle.
Compiler string-map insertion sites use this implementation; numeric maps and
lookup semantics are unchanged.

Identical scalar unification and empty closed effect rows can return the
existing substitution history and fresh-identity counter without allocating a
constraint worklist. Resolving ground leaves similarly needs no traversal.
Variables, compound types, mismatches and open rows retain the existing solver.

Generalization first resolves the type and residual predicates. When neither
contains a free inference variable, there is nothing to generalize: the compiler
no longer scans every earlier scope binding to exclude variables from an empty
set. Open types and predicates still perform all environment, annotation,
ambient-row and blocked-variable exclusions and the existing covariance rules.
This is not a relaxation of polymorphism or effect requirements.

## Validation

The tests compare full Patricia trees with Base.Map, retain old snapshots across
updates, and exercise empty, prefix, Unicode and long qualified names. A native
regression checks nested payload ownership at one and four workers. Inference
tests compare results and diagnostics with the retained slow routines, including
chronological substitutions, residual predicates, open rows and annotations.
Four constructor-level laws guard simple fast paths; they are not a formal
proof of the entire inference engine or persistent map.

The CI builds baseline and candidate with the same verified Bend release, Base,
official JavaScript loader and clang toolchain. Generated Bend C and JavaScript
are not patched. Native caches are keyed by compiler inputs, proof/law files,
platform and clang version; cache hits still run proofs and ownership checks.

## Reproduce

Build the baseline and candidate separately with the same toolchain. Then run
from the candidate checkout:

```sh
deno run --allow-all compiler/compile_time_bench.ts \
  /path/to/baseline/generated/compiler/blotc \
  generated/compiler/blotc 5 1,4 build/compile-time.json
```

The report separates fresh native-process compilation, persistent-session body
edits and unchanged artifact reuse. Startup and project loading are recorded
separately. The Deno host stays alive and filesystem caches are not flushed.
One warmup pair precedes five alternating measured pairs. Exact Wasm comparisons
and execution checks run outside the timer. Native CPU has Linux clock-tick
resolution and excludes frontend/host work; small samples may round to zero.

The public compiler workloads cover lexical depth, nominal types, effect
providers, dependency chains/diamonds and uneven checking groups. The existing
ECS example supplies an imported-project cold case. These are not measurements
of the separate application's current source or a claim that all projects share
one speedup. No worker-count default, language feature, guest ABI or emitted
runtime is changed. Timing ratios are diagnostic, not noisy CI thresholds.
