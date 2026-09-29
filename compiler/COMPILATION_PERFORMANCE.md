# Blot compilation work reduction

Baseline: main `ac59fb68f98780e168ce01fa39410b1a6ef54efd`.
This is separate from the generated-runtime optimizations in PR #4.

## Closed generalization

Previously every let generalization resolved and scanned all environment and
annotation bindings, even when the resolved type and residual predicates had
no free variables. In a chain of scalar lets this repeatedly traversed a growing
environment just to subtract its free variables from an empty set.

The candidate computes the union of type and predicate variables first. An empty
union needs no environment exclusion. Nonempty candidates use the same complete
environment, annotation, blocked-variable and ambient-effect-row checks as before.
Type and predicate resolution, predicate canonicalization, covariant row closing
and the final binding construction remain unchanged. There is no global memo,
mutable inference cache, or relaxation of polymorphism/effect rules.

The regression oracle implements the previous algorithm through ordinary exported
Bend functions and compares 900 combinations of types, contexts, substitutions,
residual predicates and blocked variables. A constructor-level law checks the
empty-candidate branch. This is not a formal equivalence proof for malformed
internal environments, nor a proof of the full inference engine.

## Annotation traversal fusion

Lowering previously copied a syntax subtree while erasing children of nested
let bindings, then scanned that copy for annotation variables. The new scanner
handles the scope boundary directly. A root binding retains its children; a
nested binding owns a separate annotation scope. Ordinary whole-tree callers
retain their original traversal. Variable and diagnostic ordering are unchanged
on the tested source and internal-tree corpus.

The old pruning helper remains available as the differential test oracle but is
not called by production annotation-scope lowering. Tests compare root/nested
bindings, effect rows, malformed rows, kind conflicts, 4,096 siblings, a deep
subtree and real parsed declarations. The variable scanner retains its bounded
work limit; the removed copying pass no longer spends its separate fuel budget.

## Reproduction

Use the same Bend release, Base, official loader, Bun, clang and Deno for both
checkouts. Generated Bend C and JavaScript must not be rewritten.

```sh
# Build native binaries in each checkout.
deno task generate:parser
deno task build:compiler

# In the candidate checkout; paths may be absolute or relative.
deno run --allow-all compiler/compile_time_bench.ts \
  /path/to/baseline/generated/compiler/blotc \
  generated/compiler/blotc build/compile-time.json 7 1,4
```

The benchmark performs two unrecorded paired warmups, then alternates which
implementation runs first. Every full request gets a fresh native process and
frontend. Incremental measurements use a separate fresh session, compile the
original source, make a real body edit, repeat it unchanged, and revert it.
Changed edits must enter the native compiler; unchanged results must report a
cache hit. Startup and first-session costs are reported separately.

Compilation timers cover source parsing, IPC, inference, specialization, const
evaluation, Wasm emission and response decoding, with `analysis: false`. The
Deno host and filesystem stay warm; these are not cold operating-system/CLI
startup measurements. Source reading for the two checked-in examples happens
before timing. Wasm byte equality and executable results are checked outside
timed regions. Compiler executable hashes, source/artifact hashes, CPU identity,
raw timings and cache statistics are retained in JSON. Ratios are diagnostic,
not CI timing thresholds.

CI builds both source versions and checks the complete candidate compiler suite,
including native/reference parity and existing invalid-program tests. The
sequential reference-build helper uses the matching official Bend loader without
modification; sequential builds bound peak memory, not program compilation time.
Native caching is keyed by exact Bend input contents, build script, toolchain
version, platform and clang identity. A cache hit still runs the proof checker
and all compiler tests.

## Scope

These changes remove work from lowering and generalization. They do not solve
all specialization costs, change the emitted Wasm runtime, add guest concurrency,
or make an unchanged artifact-cache hit a measure of compiler throughput.
