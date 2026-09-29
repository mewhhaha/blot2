# Redesign progress: recoverable native core and verified type graph

## Source and publication boundary

This work continues `redesign/typed-compiler-core`, PR #7, from the exact remote
commit `457b7963a96bd1e48d62d83e59b7d4371279e761`. The recovered archive's Git
tree is `ae9ed76806796f77e25c980e20eb4e2c37015cca`. All new local commits
descend from that commit; no history is rewritten and no change to `main` is
made.

The working session's GitHub connection exposes reads but no publishing actions.
These new commits have **not** been pushed. Each checkpoint is therefore saved
as a source/executable/evidence ZIP plus an incremental Git bundle. The supplied
bundle can be fetched into a checkout containing the base and merged with
`git merge --ff-only FETCH_HEAD`; a later remote change is never
force-overwritten. The new native CI workflow is committed, but these results
are local validation, not a claim that the new commits passed hosted CI.

## Completed implementation checkpoints

- `057b370`: restore a clean build of the recovered 72-module native semantic
  bridge, incremental build integrity, no-JavaScript-compiler smoke tests, exact
  build manifests and source/executable checkpoint packaging.
- `a6eab1b`: add a task-local type-variable arena with union by rank, trailed
  path compression, nested rollback, kind/occurs checks, lexical levels,
  duplicate-preserving effect rows and immutable DAG schemes.
- `789f8c5`: integrate graph verification into real source and native-session
  unification. The compatibility solver still supplies substitutions, results
  and diagnostics. Disagreements are independent hard failures. Counters are
  saved before publishing native responses, including sessions later disposed by
  SIGTERM. Quiet EOF and the framed stdout protocol are preserved.

The following checkpoint adds isolated archive recovery tests, a shared
build/package lock, raw commit objects and committed-input verification. Source,
native generated modules and executable hashes are checked together. Failed
builds/tests are not converted into successful checkpoint status.

## Reproduced validation

Executable from `789f8c5`, unchanged by the packaging/documentation checkpoint:

`9d77d114201116ff62d2157904d2253ad0ebb446e2c9d5c1ed04cb537f2ffc9e`

Toolchain: 64-bit OCaml 5.3.0, Deno 2.9.7, unchanged merged-main Bend 2.0.34
reference. No Bend C or JavaScript output is patched. The default Bend compiler
and the existing compiler tests are unchanged.

| Gate                                         | Observed result                                                                                     |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Full normal native/reference suite           | 985 passed, 0 failed, 2 privileged scheduling skips, 176 test files                                 |
| Full suite with graph verification           | The same 985/0/2 result                                                                             |
| Source mirror in each full suite             | 901 operations, 875 native requests, 549 successes, 352 expected diagnostics, 0 mismatches          |
| All native graph reports                     | 1,342,504 attempts: 1,342,150 accepted, 330 rejected, 24 mixed-kind cases not checked, 0 mismatches |
| Source-mirror subset of graph reports        | 600,020 attempts, all checked, 0 mismatches                                                         |
| Four-worker source corpus                    | 333 literals with both prelude settings: 362 matching artifacts and 304 matching diagnostics        |
| Native storage                               | 55,957 assertions passed                                                                            |
| Type-variable graph                          | 287,805 assertions passed                                                                           |
| Graph versus semantic-model solvers          | 26,006 assertions passed                                                                            |
| Fork/join                                    | 177 assertions plus concurrent-domain synchronization/exception checks passed                       |
| Framing                                      | 6 checks passed                                                                                     |
| Clean/incremental/failed/concurrent builds   | 19 checks passed                                                                                    |
| Source compilation with no JS compiler files | 25 checks passed                                                                                    |

Repeated suites, graph calls and assertion counts are not added into a unique
source-test count. Most low-level IR tests still exercise the reference; the
reports enumerate the actual native/source-mirror operations and all native
constraint comparisons. A successful graph comparison means acceptance agrees
for normalized constraints, not a proof that complete inferred substitutions,
principal schemes or whole-program semantics may now be replaced.

The independent graph unit oracle includes randomized equation sequences,
failed-unification rollback, scope escape protection, weak and generalized
variables, a 20,000-node deep type, shared DAGs, duplicate row labels, stale
handles after rollback/clear and concurrent independent arenas.

## Failures found and corrected

An initial full graph run was killed by the container's memory limit while
another heavyweight run was active; it executed no tests and is not a pass. The
sequential rerun passed. An initial all-native verification run exposed summary
output on stderr at quiet EOF; that run failed an unchanged regression.
File-based reports are now silent, with stderr summaries explicitly requested
only by the source-mirror harness. The final full suites above reproduce the
fix.

The paired source-compilation control compares this native executable with the
recovered native core from `057b370`, **with verification disabled**. It is an
instrumentation-regression check, not a claim that the new graph accelerated
compilation or a repeat of the earlier Bend-versus-native comparison. Raw
samples and every workload, including slower cases, remain in the checkpoint
evidence.

## Not complete

The graph is compiled, independently tested and integrated as a verifier; it is
**not yet the source compiler's authoritative solver**. Source inference still
uses the existing chronological substitutions and full semantic checking path.
The complete migration must still carry covariance/generalization restrictions,
blocked and predicate variables, effect obligations, exact diagnostic precedence
and speculative-resolution state through the new graph.

Retained typed expression bodies, pre-expansion semantic-instance
specialization, and the new dependency-sensitive query/linking engine remain
unimplemented. This checkpoint does not claim a finished compiler redesign, a
new language, parallel guest execution or a new source-to-Wasm performance
improvement.

## Production-path continuation check

A subsequent native-generator change dispatches the verification flag before the
solver call. Disabled verification no longer keeps the solver's original inputs
alive for an unused post-call continuation. The six additional native
regressions check unchanged accepted/rejected results and independent accounting
when verification is enabled or disabled. Its native storage/kernel/model tests
pass (26,012 model assertions); full-suite and paired timing results are
recorded separately for that new executable, not inferred from the earlier
checkpoint.
