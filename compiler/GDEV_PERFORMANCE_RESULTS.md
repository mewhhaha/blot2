# Gdev compiler optimization results

This records the earlier project-cache checkpoint. The subsequent
[cold-compilation results](COLD_COMPILE_RESULTS.md) supersede its performance
numbers and describe the current native build.

This implements the four approved steps from the
[investigation and plan](GDEV_PERFORMANCE_PLAN.md). The saved baseline includes
the working tree as it existed before these changes, rather than the last Git
commit. Measurements use the same application sources for both compilers.

## Measured outcome

The project session is correct on the tested game revisions, but it does not
make gdev compilation sub-second. Unchanged requests are fast; changed-body
improvements are modest and variable, and establishing the cache adds work to
the first compilation. The initial investigation's approximately three-second
baseline cannot be compared directly with this later, busier desktop run.

Five alternating one-thread samples from the final executable:

| Request                                             | Median compile-call wall time | Median native CPU time |
| --------------------------------------------------- | ----------------------------: | ---------------------: |
| Saved baseline, repeated clean compile              |                      5,447 ms |               5,300 ms |
| Current compiler, repeated clean compile            |                      5,334 ms |               5,160 ms |
| Saved baseline, clean compile adjacent to each edit |                      6,384 ms |               5,970 ms |
| Current project session, body edit                  |                      5,838 ms |               5,570 ms |
| Current project session, unchanged request          |                         23 ms |                   0 ms |

The native CPU reduction for each adjacent baseline/edit pair was 17.6%, 25.2%,
15.4%, 6.2% and -8.6%. Their median is **15.4%**; the reduction between the two
CPU medians is **6.7%**. These are different statistics, and the variation is
too large to promise a fixed speedup. The roughly 3% clean-compile CPU
difference is inconclusive. An earlier three-sample run showed a larger warm
gain; the five-sample result is the stronger evidence.

The session's initial compile took 8,613 ms wall / 7,860 ms CPU in this run. It
is a single sample taken in a different window from the clean first-compiles, so
it does not establish a precise startup regression percentage. Cache
construction and periodic process recycling remain real costs. The proposed
sub-second clean and sub-200-ms changed-edit targets are not met.

Clean compile-call times exclude project loading, while project-session calls
include it. CPU measurements count only the native child. One hundred Linux
clock ticks per second give CPU readings 10-ms resolution; an unchanged request
sends no native work. The raw report's `total_ms` also included diagnostic
`/proc` sampling, so the table uses `compile_ms`. The benchmark has since been
corrected to exclude sampling from `total_ms` and retain it separately as
`instrumented_total_ms`.

The desktop automatically demoted Deno to idle scheduling, greatly stretching
earlier wall times. This final comparison ran only its owned process tree at
`SCHED_BATCH`, nice 0, using the local
[runner](../build/gdev-checkpoint/run_normal_priority.py). Every measured native
request recorded that policy. Unrelated jobs were left running; CPU frequency,
cache contention and scheduling still vary. Baseline/candidate clean order and
adjacent clean/edit order alternate. All Wasm hashes, ABI and guest
create/clean/frame comparisons passed.

Raw [five-sample report](../build/gdev-performance-bench/final-threads1.json)
and
[earlier three-sample report](../build/gdev-checkpoint/final-paired-before-set.json).
Final executable SHA-256:
`8bf231efcd20e2734cee2314290ce6fcdc6f24d9b4e95ea089ad41ea324f2f5e`.

## Changes

- Specialization lookups stop at the first matching binding. Laws and regression
  tests preserve shadowing and missing-binding diagnostics.
- Within-compilation clone deduplication remains deferred. Expansion creates
  clones before concrete type/effect choices are solved; function-name-only
  memoization would be unsound. The implemented cache reuses complete expansion
  tasks across revisions with exact context and dependency keys.
- Project sessions retain parsed modules, declaration identities, lowering,
  specialization results, checking groups, constants and generated code. Failed
  edits preserve the last successful native revision. Gdev uses this API for
  asynchronous reloads.
- Project sessions recycle the native process after 16 transmitted compilation
  or analysis attempts by default (`maxRevisions` is configurable). Unchanged
  and trivia-only requests do not consume the limit. A restart resends all
  declarations and reports `stats.session_restarted`; failed edits still retain
  the previous successful public artifact.
- Specialization keys cover the internal language, including generic effect
  operations and dispatch choices. Each source declaration is encoded once per
  revision; cached specialization tasks track their source dependencies.
- Checking groups share one encoding of the operation catalog for each revision;
  its exact words remain part of every group and constant-dependency key.
- In native sessions, results from the initial shape check can seed final
  checking when exact body, schema and imported-interface keys match. Changed
  groups still run the normal checker, including coverage and effect-reflection
  validation. Generic effect expansion changes the catalog in gdev, so that
  conservative shortcut is skipped there. Stateless clean compilation retains
  the original checking path.
- The [ECS experiment](ECS_SCHEMA_EXPERIMENT.md) compares nested builders, fixed
  schemas with handlers, typed accessors and direct records in executable
  fixtures. Gdev's production ECS API remains the comparison workload.

## Findings during implementation

The first project-session checkpoint produced exactly matching Wasm for both the
original game and an in-memory motion edit. The edit lowered one declaration and
reused 216, checked one group and reused 843, evaluated one constant and reused
22, and compiled one code entry and reused 1,243. Despite those hit counts, the
first checkpoint did not improve edit latency.

Tracing explained why. The initial specialization cache delegated keys to a
public result serializer, which rejects unspecialized effect operations. Gdev
therefore took the ordinary specialization fallback. The serializer also omitted
dispatch information required for exact internal keys. A dedicated internal
encoding fixes both cases without changing public artifact serialization.

The final checking cache also did substantial work on a hit. A census of gdev's
844 groups found 6,089,986 U32 words in group module keys:

| Portion                    |     Words | Share |
| -------------------------- | --------: | ----: |
| Repeated operation catalog | 4,203,964 | 69.0% |
| Nominal type declarations  | 1,510,821 | 24.8% |
| Bodies and framing         |   375,201 |  6.2% |

There are only 37 distinct ordered nominal type sets; 664 groups share the same
17-type set. These counts exclude the separately encoded imported interfaces.
They measure repeated representation work, not native execution time.

After the internal-key fix, a generated-JavaScript session probe retained 529 of
534 specialization results across the motion edit. The five rebuilt results
belong to `animate`, `create`, `clean`, `frame` and `sandbox`. This establishes
selective cache reuse; task counts do not measure the work contained in each
result. The equal specialization-context key is still encoded afresh at
1,378,964 U32 words per revision. Local reproduction scripts and traces are in
[build/gdev-checkpoint](../build/gdev-checkpoint/).

## Retained memory and correctness

The unbounded diagnostic alternated 50 body edits and followed each with an
unchanged request. All 101 session artifacts were byte-identical to clean
oracles and passed guest create/clean/frame comparisons. Analysis objects use
normalized session identities, so they are not byte-for-byte equal to stateless
analysis objects. An additional
[metadata probe](../build/gdev-checkpoint/analysis_diff.json) confirmed matching
remaining const fuel (84,081 steps); its first differing fields were closure
identities, generated local names and source offsets in the retained `sandbox`
constant.

Native RSS grew from 159.0 MiB after the first compile to 333.8 MiB at edit 10
and 589.2 MiB at edit 50. The last ten edits added 66.0 MiB, with no plateau.
This is consistent with the previously isolated
[Bend allocation leak](MEMORY.md); this new RSS run is not independent
allocation site proof. Cache eviction alone cannot repair that backend defect.
The new bounded process lifetime is a mitigation, not an upstream fix or a
universal memory cap for arbitrarily large projects.

Repeating the same frozen application workload with the default revision limit
passed all 101 Wasm and guest-behavior comparisons across four native processes.
Restarts occurred at edits 16, 32 and 48, each resending 217 declarations and
checking all 844 groups. Ordinary body edits lowered one declaration and checked
one group.

| 50-edit run              | RSS after first compile | Peak observed RSS | RSS at edit 50 | Restarts |
| ------------------------ | ----------------------: | ----------------: | -------------: | -------: |
| Unbounded diagnostic     |               159.0 MiB |         589.2 MiB |      589.2 MiB |        0 |
| Default 16-request limit |               154.3 MiB |         364.5 MiB |      279.4 MiB |        3 |

RSS immediately after the three restarted compilations was 158.5, 154.4 and
158.5 MiB. The first three process generations peaked at 359.3, 364.5 and 357.2
MiB. This establishes the intended reset behavior for this workload, with a
periodic full-compilation cost. It does not fix the underlying Bend leak. These
runs also had concurrent tests; their timings are diagnostic only.

See the [unbounded report](../build/gdev-project-memory/final-unbounded.json)
and [bounded report](../build/gdev-project-memory/final-bounded.json).

## Verification

- The full compiler run passed 646 tests and found six stale assertions that
  equated first-revision checked groups with all groups. After accounting for
  seeded reuse, both affected suites passed all 11 tests, preserving exact group
  totals, one-group edit checking and failed-edit rollback assertions.
- All nine project-session tests pass, including four added lifecycle tests for
  full resend after recycling, failed-edit recovery, revision accounting, queued
  disposal and disposal during replacement-process startup.
- Gdev's 24 tests pass, including runtime reload/state preservation and the
  1,200-frame workload. Native/JavaScript key tests and native worker-count
  parity checks pass.
- `BEND_NO_TELEMETRY=1 bend PROOF.bend` completed with `All terms check.` The
  native executable and all three generated JavaScript entry points were rebuilt
  from the final Bend sources. Type checks and formatting pass for the added
  APIs and benchmark scripts.

## Next optimization decisions

Keep the language surface while testing these narrower representation changes:

1. Compare the operation catalog key once per successful revision. Invalidate
   prior checking and constant caches when it changes; remove its repeated
   suffix from individual group keys. Preserve transactional publication and the
   original-versus-specialized catalog check for shape seeding.
2. Memoize exact encodings for the 37 distinct ordered nominal type sets, then
   test the unchanged-source-name set experiment so each declaration key is
   compared once per revision. The prepared local set patch is unapplied and
   untested.
3. Retain more typed specialization results through public interface refresh and
   final validation. The safe shape-seeding implementation here does not remove
   gdev's generic-effect rechecking.
4. Use the ECS experiment to evaluate an explicit schema/staging boundary in the
   full application, preserving snapshots, queries, save/load and reload
   behavior before any production migration.

A four-request instrumented native trace confirms 529/534 specialization and
843/844 group hits on every edit, yet still records 844 group-key constructions.
The group-key/check interval consumed roughly 2.3–2.4 seconds of CPU in that
diagnostic build. These are function-entry landmarks, not inclusive function
profiles. They support investigating key representation before a broad language
or implementation-language rewrite.

The final 18-cell ECS fixtures used median native CPU times of 460 ms for the
nested builder, 370 ms for a fixed schema with handlers, 350 ms for typed direct
accessors and 90 ms for a direct record transition. This supports trying an
explicit schema boundary, but the fixtures omit most of gdev and do not measure
runtime throughput. See the [complete experiment](ECS_SCHEMA_EXPERIMENT.md).
Neither these fixtures nor key optimization alone establishes a path to 200-ms
game edits: shared-constant preparation, shape inference and interface refresh
still need retained typed boundaries.

## Reproduction

After rebuilding both compiler snapshots:

```sh
deno run --allow-all compiler/gdev_performance_bench.ts 5 1
deno run --allow-all compiler/gdev_project_memory_bench.ts 50 1
deno run --allow-all compiler/ecs_schema_experiment.ts 3 2,8,18 1
```

The paired benchmark alternates compiler order and compares Wasm hashes, guest
ABI, initial state, cleaned state and frame packets against clean compilation.
The source edit is an in-memory replacement in `motion.blot`; no benchmark
changes application files. The memory test follows each body edit with an
unchanged request and records the retained native child's RSS.

Hardware: AMD Ryzen 7 7800X3D, eight physical cores / sixteen logical CPUs; Bend
2.0.24 and Deno 2.9.7. This is a shared desktop, so small timing differences
require caution even with alternating samples.
