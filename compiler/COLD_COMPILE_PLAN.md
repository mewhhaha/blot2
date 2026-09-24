# Cold compilation toward 500 ms

The target is a fresh gdev project compilation, with project loading, frontend,
checking, specialization, constant evaluation and Wasm output counted. An
unchanged-result cache hit is a separate measurement. The target is not yet met.
The [latest verified results](COLD_COMPILE_RESULTS.md) distinguish stateless
cold requests, first project-cache requests and edits.

## Evidence from this investigation

The pre-change executable and source snapshot are in
`build/gdev-cold500-baseline/`. The workload has 16 modules, 55,988 source
characters and a 192,168-byte Wasm result. It has 844 final checking groups.

A fresh-process CPU profile of the baseline counted 271,349,288 term drops,
222,032,760 shared-constructor cleanup calls, and 14,226,167 string comparisons.
String comparison accounted for about 48% of the instrumented inclusive time; it
caused 174.3 million of the constructor cleanup calls. These percentages come
from an instrumented `-pg` build, not the production latency benchmark. The raw
profile and reproducer live in `build/gdev-cold-investigation/`.

Two algorithmic changes have been measured together:

- Validate the shared declaration catalog once per validated checking plan,
  keeping per-group inference, imported-interface, coverage, reflection and
  uniqueness checks.
- Let final checking resolve exports, removing the intermediate public
  signature-refresh inference pass. A function-valued constant's export wrapper
  calls its stored value and retains its checked signature.

One adjacent baseline/candidate pair used 5,490/4,180 ms of native CPU (24%
less), with byte-identical Wasm. Wall times were 7,377/7,583 ms under concurrent
desktop load; those wall times do not demonstrate a speedup. The initial focused
suite passed 57 tests; a new oracle test had a JS Boolean representation error,
which was corrected and then passed its five source cases.

An isolated native-backend experiment compares immutable strings by borrowing
their contents while retaining both input roots, then releasing each root once.
It preserves ownership rather than omitting cleanup. Two alternating pairs used
4,120/2,770 and 4,030/2,790 ms of native CPU, with identical Wasm. A guarded
Bend 2.0.24 C transform and ownership/concurrency regressions are now in the
build. The combined candidate passes all 668 compiler tests, all 24 gdev tests,
and `bend PROOF.bend`; see the latest results for the final paired measurements.

The combined candidate, which also short-circuits dependency scans and keeps a
cursor during string-map lookup, took about 2.74–2.97 seconds of native CPU for
fresh one-thread gdev requests in the current benchmark window. Its separate
`-O3 -pg` run produced the exact baseline Wasm and counted 73.5 million
`term_drop`, 37.8 million `span_fade`, 6.82 million borrowed string comparisons,
and 5.40 million `Index.find_work` calls. Reference handling and repeated
string-key lookup remain material, but gprof samples cannot be read as exact
production phase times.

A persistent Nat48 Patricia index for the type substitution histories passed the
existing chronological and randomized substitution/effect-row oracles and Nat48
boundary/snapshot tests. On a matched standalone workload of 81,920 updates and
400,000 reads, it used median 273 ms of native CPU versus 551 ms for the old
decimal-string-key map. This is a data-structure result; its whole-gdev benefit
is not yet substantial in the small paired candidate window: the combined
candidate used 2,990/2,960 ms of native CPU versus 2,990/2,860 ms with the Nat
index, with exact Wasm parity. The differences are within run variation; retain
the change only if broader correctness and scaling results justify it.

These are different measurement windows. Do not combine their times into an
end-to-end speedup claim. No result here is below 500 ms.

A later coarse native trace of C3 uses 3,230 ms CPU with exact Wasm parity: 205
ms for the initial shape check, 501 ms for shared specialization preparation,
1,055 ms for remaining specialization, and 1,019 ms for final dependency
planning/checking. Constant evaluation takes 80 ms; Wasm preparation through
output takes 241 ms; decoding/lowering/template-graph work takes 122 ms. These
intervals include their nested work and exclude frontend project loading. The
adjacent uninstrumented control uses 3,330 ms CPU. This places roughly 2.8
seconds in checking and specialization and rules out ordinary constant
evaluation as the primary cold bottleneck. See
[phase data and conditions](COLD_COMPILE_RESULTS.md).

## Work that scales

Inference should produce reusable evidence, not just a type subsequently thrown
away. The intended unit is a declaration or recursive declaration group:

1. Infer a source body once into a type scheme and deferred type/effect
   requirements. Retain coverage and reflection obligations as part of that
   result.
2. Instantiate a requirement only when a use supplies its type/effect arguments.
   Key the result by the declaration version and canonical argument identities.
   Retain the selected operation/member and typed result together.
3. Publish a checked interface for downstream groups. Revisit a dependent group
   only when an interface or another dependency actually changes.
4. Generate code from those checked results; final validation consumes evidence
   instead of inferring every expanded body again.

Cycles must be inferred and published as a group. Cache publication stays
transactional: a failed edit must not publish dependency versions or partial
inference results. Diagnostics must remain deterministic. Source declarations
still require validation; laziness must not accidentally hide an invalid unused
type or operation declaration.

A read-only census found that all 844 final singleton groups originate in one of
534 specialization tasks. Of these, 429 have concrete closed signatures, 316
also lack the associated-call rewrite marker, and 256 of the 429 have no
external group dependencies. Those are structural upper bounds, not evidence
that the tasks inferred those bodies or that their solved types can be reused.

### Tested typed-evidence boundary

An isolated prototype retained each task's solved environment and obligations
alongside its expanded declarations. On gdev, only 54 of the 534 tasks produced
such certificates: they held 452 declarations, and 431 had an actual inferred
definition. Every certificate's _whole-task_ choice map was nonempty. A safe
per-member probe excluded declarations without a definition, with their own
associated/operation selection need, or with nested annotated lambdas. This left
134 members. Of the 438 final groups with no external dependencies, 118 matched
those members; 103 passed the pure-body and `Check.finish`/closed interface
gates. The resulting checked module was deeply equal to ordinary checking on the
same prepared program: **103/844 groups reused**, not 844/844.

These counts came from a JS-filtered harness over the isolated prototype in
`build/gdev-typed-certificates/`, not an integrated compiler or native timing
result. The isolated Bend eligibility now requires a member's own inferred
definition with no selection need and checks nested lambda annotations; it
passes `--check-only` but has not been regenerated and retested. The prototype
is deliberately not enabled. Its zero-dependency, pure restriction can save at
most a small fraction of cold checking and cannot support a below-500-ms claim.
An independent initial-shape cache prototype reuses 259 of 260 source groups
after the motion edit with exact analysis equality. It remains isolated under
`build/gdev-shape-cache/`: caching that earlier pass can address warm work, but
adds first-compile cache construction and cannot improve cold compilation. Its
native follow-up found no net benefit: six paired edits used median 5,140 ms CPU
for C3 versus 5,225 ms for the prototype, with about 12 MiB more RSS after the
sixth edit. First compilation was also slower. Do not promote this cache without
changing how its keys and planning work are maintained.

To reuse the remaining bodies, specialization must retain a typed expression and
a proof for each selected associated call or operation: the selected callee's
instantiated type and effect row must match the solved requirement, while
coverage/reflection obligations and exact dependent interfaces remain attached
to that member. The final checker can then consume these witnesses and fall back
only for a changed or unproved member. This requires an explicit nominal-catalog
version and member-body provenance, not a whole-module encoded key or a
declaration-name match.

Scheme instantiation has a smaller repeated traversal: `Infer.instance` calls
`Types.replace` once per quantified variable. A C3 generated-JS census of gdev
finds 18,280 instantiations, of which 16,250 have no variables; the remainder
perform 4,891 substitutions (maximum 16 variables). They visit an estimated
96,786 type nodes versus 19,343 for one simultaneous renaming traversal. A
right-to-left composition of the variable-renaming map can preserve the current
chronological semantics, including repeated variables and replacement-index
collisions. The type and effect-row traversal must retain the existing fuel and
diagnostic behavior. This is a bounded scaling improvement, but the absolute
work is too small to treat its fivefold node-count reduction as a whole-compiler
speedup. Raw counts: `build/gdev-cold-investigation/instance-census.jsonl`.

### First residual-inference migration

Retain the initial shape check's `I.Definition` obligations alongside each type
scheme; `Mono.shape_bindings` currently discards them. Canonical instantiation
must rename type variables, effect-row variables, dispatch identities, coverage
requirements, exits and reflection obligations together. Instantiating only the
outer function type is insufficient.

The first executable slice should retain the direct generic-operation obligation
of `ecs.get/set`, keyed by the exact State operation and ambient effect row. It
is a small semantic test, not the main speedup. Next compose callee evidence so
a caller retains a generic callee's deferred requirements: the source
`Array.get` calls generic `lt`, and its own shape result does not yet contain
the eventual `U32.lt` selection. Only after this composition is proven should
the parametric `Array.get` body and its `ecs.component_at` caller be shared. A
conservative post-solve body/dependency comparison groups each family of 25
clones into one class, totaling 2,600 duplicated body nodes. Only nine clones
per family actually underwent specialization inference; the other copies were
checked at the final pass. Thus this slice can remove at most 16 repeated
specialization inferences and 48 final clone checks. It validates reusable
evidence, but cannot close the 500 ms gap by itself. Verify the backend's
uniform generic array/`Maybe` representation before sharing generated bodies.

Then target measured repeated inference in larger families: `ecs.at` (1,632 body
nodes across 12 inferred clones), `protocol.integer` (1,184 across 16),
`math.vec_scale` (1,032 across 12), and `ecs.components` (976 across eight).
`ecs.get` and `ecs.set` have many clones but only eight body nodes each, so
their clone counts exaggerate their inference weight. Negative reuse tests must
vary nominal dispatch, selected State operation, captured constants, effect
rows, annotations and reflection; failing programs must preserve diagnostic
order. The detailed isolated investigation is
`build/gdev-typed-certificates/RESIDUAL_MIGRATION.md`.

For persistent edits, exact catalog snapshots can assign monotonic version
tokens to nominal types. Compare each declaration and the operation catalog once
per revision; group keys then refer to small tokens. The current repeated keys
contain about 4.2 million operation words and 1.5 million nominal-type words per
gdev revision. Removing this repeated serialization is necessary even when most
inference tasks already hit their caches. Hash equality alone is not proof of
unchanged input.

## Measured specialization diversity

A fresh one-thread gdev compile retains 821 analyzed functions. Of these, 492
are `$mono[...]` clones from only 67 distinct source names. Alpha-normalizing
type and effect-row variable indices, while retaining exact nominal identities,
leaves 151 distinct concrete input/result/effect signatures across those 492
clones. The largest families are:

| Source declaration   | Retained clones | Distinct signatures | Largest same-signature class |
| -------------------- | --------------: | ------------------: | ---------------------------: |
| `ecs.get`            |              90 |                  15 |                           17 |
| `ecs.set`            |              82 |                  21 |                           24 |
| `ecs.Entry.contains` |              28 |                   7 |                            7 |
| `Type.eq`            |              28 |                   1 |                           28 |
| `ecs.component_at`   |              25 |                   1 |                           25 |
| `Array.get`          |              25 |                   1 |                           25 |

The 341 clones beyond one clone per signature are an **upper bound on a
memoization opportunity, not interchangeable implementations**. In particular,
`Type.eq` or `component_at` can choose a different nominal implementation while
exposing the same runtime signature. Captured constants and selected associated
members are also absent from that signature census. A sound reusable unit is a
source declaration inferred once into residual type/effect, coverage and
reflection constraints. Instantiate and check that evidence using an exact key
of source version, canonical concrete type/effect arguments, selected
member/operation choices and captured-value dependencies. Generate a clone only
after those values are known; do not clone and infer the same source AST at each
call site. This is an architecture target, not a measured 69% compilation gain.

An independent pre-specialization graph census found 237 functions and 23
constants in the lowered 16-module source. Three exported functions and two
exported/runtime-initialization constants reach 195 of its 260 nodes directly.
Adding the 63 declarations containing deferred syntax to those roots reaches 202
nodes. `Mono.template_closure` expands those seeds to 149 reverse dependents;
including the dependents before the same direct-reference walk reaches 216 nodes
and leaves 44 (17%) outside. This graph walk does not yet include dynamically
selected associated-method targets or constructor-derived edges, so 44 is an
upper bound on safely skippable source nodes. The 534 later specialization tasks
arise after shared expansion and do not map one-to-one to these source nodes.
This rules out discarding most work by pruning unused source roots alone. The
probes are in `build/gdev-compact-cache/reach_census.ts` and `lower_census.ts`.

## Exact-key scaling evidence

The old gdev group-key census counted 6,089,986 words per revision: 4,203,964
repeated operation words (4,981 for each of 844 groups), 1,510,821 nominal-type
words, and 375,201 body/framing words. The compact key stores one exact
operation encoding, one exact encoding per nominal declaration, and ordered
nominal-version tokens in each group key. A generated-JS word-count probe gives
18,829 versus 2,607 total words for 32 types across 32 groups (86% less), and
7,187 versus 1,075 for 8 types across 32 groups (85% less). Upfront catalog
encoding can cost more for tiny workloads: 32 types across two groups use 346
old versus 1,115 compact words. These are exact synthetic counts, not measured
gdev compact words. The probe is `build/gdev-compact-cache/key_size_probe.ts`.

Matched one-thread gdev native CPU pairs used 4,930/4,910 ms for ordinary edits
before compact keys and 4,600/4,560 ms after them. Revert edits used 5,240/5,260
versus 5,060/5,090 ms. First session compiles used 7,400/7,120 versus
7,620/7,540 ms. These small paired samples show a modest warm benefit and no
cold improvement despite the much larger reduction in key words; serialized word
counts do not translate linearly into CPU time. The fresh process cold target
remains unmet.

## Remaining cold gap

For a one-thread path at roughly 2.8 seconds of native CPU, the current
candidate needs at least a 5.6-fold reduction to put the _entire_ cold path
below 500 ms; project loading and frontend work make the required compiler-core
reduction larger. Eight threads have not yet shown a clear wall-time gain. A
planning budget, not a measured breakdown, is at most 300 ms for checking and
specialization together and 200 ms for loading, lowering, constant evaluation,
code generation, Wasm serialization and process overhead. A faster string
comparator or substitution map alone cannot plausibly close this gap: even
zeroing the three largest profiled self-time categories (`term_drop`,
`span_fade`, borrowed comparison) would remove only about 46% of that
instrumented run, and it would leave all other work.

Proceed in measured stages:

1. Benchmark the combined native candidate and the typed-evidence reuse
   prototype on original gdev, with phase CPU, equality/index call counts, exact
   Wasm and diagnostics. Reject a reuse design that merely moves work to final
   validation or hides an invalid unused declaration. If cold checking remains
   above the 300 ms planning budget, more local map/RC fixes are insufficient as
   the primary strategy.
2. Build a compact typed core with stable integer IDs for declarations, nominal
   types, operations, type variables and effect rows. Intern canonical shapes
   once per project revision; retain constraints and resolved selections by ID.
   This changes repeated recursive String/Type traversal into indexed access and
   lets one inference result feed validation and code generation. The next
   prototype should cover one real gdev module dependency chain and preserve
   exact diagnostics, not just a synthetic lookup workload. Measure allocations,
   traversed type/row nodes and CPU before broad migration.
3. If compact evidence still spends most CPU in Bend's term ownership/runtime,
   isolate the typed-core and Wasm boundary behind a stable, tested interface
   and compare a native arena-backed implementation of that bounded core. This
   is an architecture experiment, not a claim that a language rewrite is
   inherently faster. Require exact source/diagnostic/artifact parity and a
   measured cold phase reduction before replacing the existing implementation.

A one-request arena is not a safe RC-off switch for the generated C. Constructor
matches currently consume fields and reuse their storage; arrays install
reference wrappers in place; closure/task delivery also mutates storage. An
immutable arena backend would need borrowed matches, fresh data nodes,
copy-on-write arrays, a separate mutable scheduler/IO region, and reclamation
only after response copying and worker completion. Bound its memory use and
measure it before promotion. Merely suppressing drops/frees would corrupt shared
values under the current generated code, and ownership self time alone is too
small to explain the entire remaining fivefold gap.

For scalability, measure fresh 1- and 8-thread compiles on gdev and increasing
matched project/schema fixtures, then repeat after doubling declarations and
type/effect uses. Record phase work counts and CPU per input unit. A candidate
passes the target only when full cold wall time is below 500 ms in a controlled
normal-priority run and native CPU plus frontend costs support that result;
unchanged/edit-session shortcuts are reported separately.

## Acceptance gates

- Alternate fresh baseline/candidate processes, recording native CPU and wall
  time separately; record process startup, project loading and frontend time.
- Check exact Wasm parity where representation is unchanged, plus ABI and
  create/clean/frame behavior for gdev.
- Check cold, ordinary body edits, interface edits, operation/schema edits,
  invalid edits followed by recovery, and increasing project sizes.
- Run semantic, ownership and parallel-backend regressions before enabling a
  backend optimization. Run `bend PROOF.bend` with the final source tree.
- Report the measured cold and edit latency separately. The 500 ms target is an
  acceptance criterion, not an extrapolation from cache-hit percentages.
