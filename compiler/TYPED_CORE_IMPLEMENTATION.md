# Retained checking and generic instantiation

This change keeps Blot's source language and inference rules. It introduces
one-pass generic variable renaming and reusable checking results at the boundary
of a complete dependency component (SCC).

## Current integrated result

The integrated changes include retained component checks, independently checked
field accessors, one-pass scheme renaming, indexed name membership, and an
explicit-stack type resolver. They preserve the language's inference rules and
produce the same gdev Wasm. This is an initial implementation of the proposed
checking boundaries, not the complete typed-IR/arena redesign.

Five alternating fresh-process pairs against checkpoint `827175d`, with both
binaries built using Bend 2.0.27, measured:

| Median                      | Checkpoint | Integrated |
| --------------------------- | ---------: | ---------: |
| Native compile call         |   1,636 ms |   1,481 ms |
| Native child CPU            |   1,600 ms |   1,440 ms |
| Startup + loading + compile |   1,725 ms |   1,572 ms |

The compile-call reduction is 9.4%; the full measured path improves by 8.9%. All
ten outputs have the same 192,168-byte Wasm hash. The 100–200 ms fresh
source-to-Wasm target remains unmet.

Two alternating persistent-project session pairs measured initial compilation at
3,840 → 3,580 ms, a motion body edit at 2,342 → 2,207 ms, and its revert at
2,395 → 2,271 ms. Each edit still checks one group and regenerates one code
entry. Unchanged requests take about 9–10 ms and are result-cache hits. The
project/session path has additional cache preparation work and should not be
confused with the fresh stateless compile above. All original/edited hashes
match their reference artifacts.

Validation: `bend PROOF.bend`, native ownership regressions at one/four workers,
689 compiler/transformer tests, and 24 gdev tests pass. The gdev source is
unchanged. Raw final pairs are `final-flat-original-cold.jsonl` and
`final-flat-original-warm.jsonl` under `build/type-core-implementation/`.

## Reuse boundary

The initial source check computes principal schemes in separate dependency
components. Planning resolves declaration names once to numeric identities for
both graph traversals. It preserves declaration, edge, component and member
order; unknown references remain for inference to diagnose. Each retained result
records:

- the exact component declarations, including annotations and source identities;
- its checked result, including validated coverage and reflection;
- the exact imported schemes, function/constant kinds, and effect metadata;
- the nominal and concrete operation declarations used for checking.

Before final checking, the compiler compares the catalog once per certificate.
Workers then compare the complete component and its imports. A match reuses the
checked result; a mismatch follows the ordinary checker. This is shared by fresh
source compilation and incremental sessions. Existing session cache lookup and
transactional publication remain ahead of this fallback.

The scheduler captures these results as the initial check finishes each group.
There is no second source dependency plan or scan to reconstruct checked groups.
Warm sessions retain source-ready certificates from the last successful
revision, including revisions without dispatch sites. An unchanged group can use
that evidence in the next source check; a changed group is inferred again. The
original source check precedes inlining and pruning, so a failed source check
reports its diagnostic immediately. A later failed resolution round reuses the
already checked original module. Inlining and later resolution rounds can reuse
a group with deferred requirements only as an atomic witness of its checked
result and its original `GroupNeeds`. The complete module and ordered imported
interfaces must match, including operation templates and nominal declarations.
Missing, partial, or duplicate requirement associations cannot certify a group.
Ready certificates also reach the final check behind the session's group cache.
A successful prepared module publishes the new source certificates; a failed
revision leaves the previous cache intact.

Comparison uses a bounded structural worklist. It preserves nominal identities,
float bit patterns, annotations, source offsets, and duplicate, ordered effect
labels. Exhausting the comparison budget produces a miss. Generic operations and
unresolved associated dispatch are excluded from source certificates.

## Generated field accessors

The next slice checks a generated getter or setter independently, before its
caller constrains its type. It imports the principal interface into the caller
with fresh variables and retains the checked helper for final checking.

The helper uses only the receiver's constructors and local variables. Its
independent check and retained dependency therefore contain the receiver's
nominal declaration. Import validation uses the full current catalog.
Unsupported minimal checks fall back to the existing inference path. In
particular, a generic setter must be able to change a type parameter; its
principal scheme cannot be derived by copying its first caller's receiver type.

Checking against the entire catalog per helper was too expensive. A JavaScript
probe over all 127 gdev accessors found identical exported interfaces with only
the receiver declaration. Their independent checks took about 21 ms and catalog
validation/indexing about 4 ms, versus 144 ms and 388 ms with the full catalog.
These are diagnostic costs, not a native whole-program speedup measurement.

## Generic schemes

`Infer.instance` now renames multiple quantified variables in one traversal.
Value variables and effect-row tails share a renaming map. Empty and single
binder cases keep their cheap paths. Duplicate or colliding fresh IDs use the
previous sequential algorithm. Interface parameterization also uses one
traversal and preserves first-binder behavior.

`residual_scheme.bend` provides the corresponding operation over inference
obligations, including operation/member requirements, pattern coverage and exit
identities. Its caller supplies the identity map used to clone the expression.
It does not itself eliminate inference of specialized generic bodies.

## Rejected experiment

Retaining the final solved environment from a whole specialization task was
unsound. Callers had already narrowed generic types and shared effect rows.
Projecting a function from that environment did not reproduce its principal
scheme when checked independently.

On gdev, a diagnostic replay attempted 363 such hits across 844 final groups;
190 produced different interfaces. A generated field accessor incorrectly gained
seven State effects. A small State program reproduced the same problem with both
effect rows and quantified type parameters. Restricting reuse to the exact
specialization task left only 12 hits. That implementation was removed from
certificate issuance.

The regression suite checks the State example against ordinary final inference
and requires whole-component matching. Replaying properly scoped generic
constraints is still necessary before specialization body inference can be
removed safely.

## Validation and measurement

The initial source-only candidate retained 197 original groups and reused 111 of
844 final groups. It had zero mismatches against independent checking, but three
alternating native pairs had the same 1,987 ms median compile-call wall as the
baseline. Reconstruction and validation consumed the saved work.

The final merged JavaScript compiler retains 324 certificates and reuses 238 of
844 final groups: 111 original groups and all 127 generated field helpers. All
238 complete checked groups exactly match independent ordinary checks. There are
606 fallbacks: 567 groups without certificates and 39 changed declarations.
Generated `ecs.get/set`, `Array.get`, and `component_at` still undergo body
inference; this is not a complete replacement of the generic checker.

An isolated build containing only one-pass instantiation and interface
parameterization produced the same Wasm in three alternating native pairs.
Baseline median compile-call wall was 1,889 ms versus 1,916 ms for the
candidate; individual candidate samples ranged from 1,812 to 1,922 ms. CPU
medians were 1,850 and 1,870 ms. This does not establish a full-gdev
improvement. The transformation is a scheme-instantiation primitive, not
evidence of reaching the 100–200 ms target.

Five alternating one-worker native pairs used fresh compiler processes and fresh
loads of the unchanged 16-module gdev application:

| Measurement (median)             | Saved baseline | Retained checking + field helpers |
| -------------------------------- | -------------: | --------------------------------: |
| Compile call                     |       1,659 ms |                          1,613 ms |
| Native compiler CPU              |       1,620 ms |                          1,570 ms |
| Startup + loading + compile call |       1,745 ms |                          1,696 ms |

The measured compile-call improvement is about 2.8%. All ten samples produced
identical 192,168-byte Wasm, SHA-256
`3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`. This remains
far above 100–200 ms. A separate three-pair comparison measured 1,631 ms with
direct source capture alone versus 1,590 ms including the field helper path;
different measurement windows must not be combined into a speedup.

Two alternating persistent-session pairs measured first compilation at 3,848 →
3,754 ms, a motion body edit at 2,335 → 2,313 ms, and reverting that edit at
2,411 → 2,383 ms. Both versions checked one final group and regenerated one code
entry on each edit. Unchanged requests took about 9–11 ms with zero native CPU;
those are result-cache hits. Every original/edited artifact matched its saved
hash. A separate runtime check also compared schema, create, clean and frame
behavior for both revisions.

The host benchmark process stays alive and filesystem caches are not flushed.
CPU measurements cover the native child, at 10 ms resolution; wall time also
reflects host/frontend work and system scheduling. The samples above came after
compiler builds stopped. Earlier measurements in different load windows were
slower for both versions.

Reproduce the cold comparison:

```sh
deno run --allow-all compiler/gdev_cold_bench.ts \
  build/type-core-implementation/baseline/generated/compiler/blotc \
  generated/compiler/blotc 5 1 1
```

Validation passed: full `bend PROOF.bend`, native ownership/renaming regressions
with one and four workers, all 686 compiler/transformer tests, and all 24 gdev
tests. The seven initial warm-cache count failures were fixed by skipping source
certificate collection on warm sessions; the original count assertions remain.
Raw replay, paired timings and behavior artifacts are in
`build/type-core-implementation/`. The verified compiler/source snapshot is
`build/type-core-implementation/checked-core-stage/`.

## Membership indexing

The next integrated change builds a name set once per generalization component
and shares it between outside-binding selection and member generalization.
Filtering ordinary specialization bindings likewise builds one set per pass. All
output lists keep their original order and multiplicity. State operation merge
now appends only when the concrete operation is absent; existing operation
precedence is unchanged.

A generated-JS census found 924,885 linked-list steps in `globals.outside`,
393,043 in member generalization, and 309,155 in ordinary-binding filtering on
one gdev compilation. Independent differential checks passed 4,000 cases,
including duplicate/Unicode names, full component generalization, and operation
merge order. Full gdev analysis and Wasm were exactly equal.

Five alternating fresh native pairs compared the retained-core stage with the
indexed candidate:

| Measurement (median) | Retained-core stage | + Membership indexing |
| -------------------- | ------------------: | --------------------: |
| Compile call         |            1,588 ms |              1,498 ms |
| Native compiler CPU  |            1,550 ms |              1,460 ms |

This is about a 5.7% compile-call reduction in this measurement window. All ten
Wasm hashes matched. After integration all 686 compiler/transformer tests and
all 24 gdev tests passed again. The source, generated outputs and raw pairs are
saved in `build/type-core-implementation/name-index/`.

Three additional alternating pairs directly compared the original saved baseline
with the integrated compiler: median compile-call wall 1,632 → 1,501 ms, and
native CPU 1,600 → 1,470 ms. This establishes about an 8.0% overall improvement
for the integrated changes in that window. Three pairs with the same current
binary measured one worker at 1,494 ms / 1,460 ms CPU and four workers at 1,756
ms / 2,100 ms CPU, with identical Wasm. The default remains one worker. This
still falls far short of the 100–200 ms target.

## Further experiments

### Flat type resolution

The integrated resolver now uses an explicit stack of continuation frames
instead of nested result continuations. It preserves chronological substitution
cursors, each child's structural budget, and the order of effect labels and
diagnostics. If its machine-step budget is exhausted, it restarts the original
resolver with the original inputs. The original resolver remains available as a
differential oracle; the public substitution representation is unchanged.

The candidate matched 120,004 generated and 5,171 independently constructed
cases, including self substitutions, repeated bindings, duplicate effect labels,
large types, and forced fallback. Full gdev analysis was exactly equal. Five
alternating fresh native pairs measured membership indexing alone at 1,503 ms
wall / 1,470 ms CPU and the flat resolver at 1,470 ms / 1,440 ms: about a 2.2%
additional reduction in this window. All ten Wasm hashes matched. Three tracked
regressions cover the constructor, history, and fallback boundaries; native
ownership regressions pass with one and four workers. Raw evidence is in
`build/type-core-implementation/flat-resolver/`.

After integration and rebuilding all JavaScript outputs, all 689
compiler/transformer tests and all 24 gdev tests passed. The gdev source tree
remains unchanged.

### Rejected solver and arena representations

A resolved-child equation cache certified substitution history incrementally and
skipped repeated normalization while history was unchanged. Independent review
found two correctness holes: caller-forged internal markers, and a 66,000-field
composed type whose fresh resolution should fail the structural budget. Both
were fixed; 30,221 randomized/adversarial comparisons and the large boundary
case passed. Nevertheless, five native pairs measured 1,584 ms for the retained
stage versus 1,642 ms for the candidate (CPU 1,550 versus 1,610 ms). It is
slower and is not integrated. Sources and details are in `solver-head/` under
the same investigation directory.

A persistent `TyId` arena backed by `NatIndex` was also rejected: conversion and
lookup costs outweighed tree traversal on actual gdev signatures. Bounded
roundtrip checks passed, but review additionally found that truncated packing
could hide variables. That prototype is not safe for general use and is not
integrated. A flat linear `Array` lookup microbenchmark was much faster, but it
is not an end-to-end solver measurement. A full flat arena needs ownership
threaded through inference at a dependency-component boundary. See
`type-arena/REPORT.md` in the investigation directory.

### Generic operation wrapper replay: validated, not integrated

A real Bend prototype retains independently inferred requirements for functions
whose body directly applies one generic operation to `()` or its own parameter.
It captures before constant sharing, then replays after clone placeholders have
been seeded. The entire clone must match, including annotations and identities.
Value variables, row variables, operation requirements, allocation holes and
source subjects remain connected. A replay failure uses the original checker.
Named calls, nested applications, callback invocations, captures, explicit type
arguments and staged bodies are outside this fragment.

Capture is local to one preparation run. During that run constant sharing keeps
the nominal catalog and generic templates unchanged, adding only concrete
operations. A new source revision captures new schemes. Existing cached paths
pass no schemes and take the original inference path directly.

The final prototype avoids 172 specialization body checks for gdev's two ECS
get/set wrappers. On the actual linked 16-module application, all 821 prepared
functions, 844 checked interfaces, analysis and Wasm exactly match the baseline.
The test harness now asserts these project sizes explicitly: an earlier probe
incorrectly used the single-file preparation flag and reported zero hits. The
artifact comparison detects project input automatically and was unaffected.

Nine focused sources preserve successful artifacts or exact diagnostics. Direct
oracles additionally exercise closed/open/duplicate effect rows, distinct State
types, annotation constraints and unsupported-body fallback. A focused large
chronological-substitution test found replay falling back when ordinary
inference reached its type-complexity limit. These checks cover the restricted
fragment; they do not certify general generic-body reuse.

Five alternating native pairs measured the integrated flat resolver at 1,470 ms
wall / 1,440 ms CPU and generic replay at 1,460 ms / 1,430 ms. The 0.65% median
wall difference is too small here to establish a useful improvement. Every
artifact matched, including a separate four-worker native run. The prototype is
therefore **not integrated**. Its source, final generated outputs, oracles and
`native_pairs.jsonl` remain in `build/type-core-implementation/generic-core/`
and the surrounding investigation directory. Broader typed-body composition and
an owned flat arena remain future work.

The native profile of the retained-checking stage records about 68.5 million
ownership releases, 35.2 million reference-field operations and 6.45 million
name comparisons per gdev compile. This is evidence that the remaining work
extends beyond unification. Instrumented profile percentages are not
uninstrumented latency estimates; raw profile and call-site census are in
`profile-run/`.
