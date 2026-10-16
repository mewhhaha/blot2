# Predictable demand evaluation

Design and implementation status, 2026-10-09. Make ordinary demand parameters
compile to control flow and local values when their uses are known. Keep a
deferred value at runtime only where the compiler cannot eliminate its storage.
The first acceptance case is source-defined `&&` and `||` producing the same
branch structure as their explicit `if` equivalents.

Use `@demand value` for requesting a deferred result; keep `~` on parameters and
types. This document proposes replacing `@force`, not adding a second evaluation
mode. **Both spellings are implemented as aliases.** The first optimization is
also implemented: known, fully applied expression bodies consisting of parameter
reads, scalar intrinsics, `if`, constructor matches, aggregate expressions,
constants and demands use branches and locals. Pattern locals and guards retain
lexical scope. Analysis admits at most 96 expression/pattern nodes, including
the bodies of fully applied forwarding calls. It does not inspect operator
names. Multiple reads, including forwarded reads, use a local memo reset on each
invocation. Recursive and unknown indirect calls, escaping demands and unproved
control retain the shared runtime cell. Proved local loops and lexical callbacks
share invocation-local memos; their first use retains the ordinary provider
scope.

The proof follows available immutable Core across aliases, imports and compiled
dependencies, and admits immutable compile-time captures without evaluating
them. Ordinary emission still reads their current values and records executable
dependencies. Names and source fixities do not select the optimization. Both
codegen tiers enforce the same admission rule. Unsupported or exhausted proofs
keep ordinary demand storage; source parsing, typing and nesting limits remain
independent.

Inlining records the consumed declaration in the caller's code artifact.
Retained code checks its exact Core projection and transitive semantic reads,
and carries that dependency forward across reuse. Unrelated body edits may
retain the caller; changes to consumed bodies rebuild it. Namespace, catalog,
and source-ID changes remain conservative. Forwarding preflights every nested
call's concrete signature before emitting arguments, so a declined inner call
cannot try to materialize an outer demand whose cell was eliminated.

## Language contract

The programmer should be able to reason about evaluation without knowing whether
a deferred argument has a runtime object. Preserve the existing
[demand rules](../compiler/guide.md#demand-parameters):

| Construct             | Meaning                                                                                   |
| --------------------- | ----------------------------------------------------------------------------------------- |
| `fn value => body`    | Evaluate the argument before entering the body.                                           |
| `fn ~value => body`   | Capture the argument expression and its lexical bindings; evaluate it when demanded.      |
| `@demand value`       | Evaluate the pending expression at this point, or return its previously completed result. |
| Repeated demands      | Share one result for this particular deferred argument, including through aliases.        |
| No demand             | Do not run the expression, its effects, or its traps. Still check its types and names.    |
| `fn () => expression` | An ordinary callback; each invocation runs its body.                                      |

These rules must hold for effectful and pure arguments, in every optimization
mode. The compiler must never switch between evaluating once and evaluating
again according to an optimization heuristic.

Demand mode remains part of function types, including `~U32 -> U32`, aliases,
partial application, and callbacks. `@demand` requires one deferred operand; it
does not silently accept an eager value. Merely referring to a deferred value
does not evaluate it. Forwarding to another demand parameter continues to use
`callee (@demand existing)`, preserving the sharing of `existing`.

Introduce `@demand` as an alias for the existing intrinsic first. Update the
prelude, guide, diagnostics, and examples together. Retain `@force` during the
transition; removing it is a separate compatibility decision. Internal IR tags
can retain their names during this source spelling change.

## Expected code

The following ordinary function should need no demand object:

```blot
const and = fn (a: Bool) => fn ~(b: Bool) =>
  if a then @demand b else #False
```

For a known, fully applied call, the resulting control flow is:

```blot
if a then b else #False
```

Evaluate `a` once and evaluate `b` only in the selected branch. Preserve the
bindings captured at the original call. Match the checked function body and its
identity; do not recognize the strings `and` or `&&`. User-defined combinators
with the same behavior should receive the same optimization.

Repeated demands also need not allocate:

```blot
const twice = fn ~(value: U32) =>
  @u32.add (@demand value) (@demand value)
```

Evaluate the argument at the first demand and reuse a local result. If the first
demand is conditional, initialize the result on that path; do not move
evaluation to function entry. If several paths can demand it first, local state
and a result slot may be necessary. A single textual occurrence inside a loop
can execute repeatedly, so counting syntax occurrences is insufficient.

This function can require persistent storage when its returned callback escapes:

```blot
const remember = fn ~value => fn () => @demand value
```

All invocations of that callback must share the result of its captured demand.
If the compiler can see the callback's complete use and eliminate it too, an
allocation is still unnecessary. A captured expression alone is not proof that
it needs a heap object.

## Effects and lifetime

Capture lexical binding versions at argument application, including partial
application. Later `:=` rebinding must not change the captured expression's
inputs:

```blot
const delay = fn ~value => value
entry const answer = fn () => do:
  let amount = 20
  let pending = delay (@u32.add amount 1)
  amount := 99
  return @demand pending
```

The result is 21. Inlining must substitute binding identities rather than source
names. Capturing an array or list preserves its existing value and aliasing
rules; it does not imply a deep copy. Captures remain live until their last
possible demand, and must participate in collection ownership analysis.

Effects run under the providers active at the first demand, as specified by the
current guide. Creating the demand does not capture the provider chain. For
example, if a pending `Read.get ()` is first demanded under a provider returning
20, demanding the same value under a provider returning 99 still returns the
cached 20. Inlining must preserve the first demand's handler scope and effect
order. It must not move operations across `do provider:` or request handler
boundaries. Latent effect rows and nominal/provider evidence remain part of
checking and specialization; optimization does not erase requirements.

Do not speculate even a pure argument onto a path that never demands it: purity
alone does not establish termination or absence of traps. Preserve left-to-right
evaluation of ordinary arguments around deferred arguments. Suspending an
expression must not let its `return` or `break` target a caller scope that the
language currently rejects.

One dynamic creation has one shared result. A demand created before a loop
remains shared across iterations; a demand created inside the loop is fresh on
each execution of that creation. Returning a demand, storing it in a record or
collection, and retaining it across guest calls require correct lifetime and
runtime and host roots. Avoid allocating a memo slot per iteration for a demand
created outside the loop.

### Completion and cancellation

Only normal completion publishes a shared result. A request handler's `yield`
resumes the same evaluation. Its `return` or `break` cancels an unfinished
demand: every active force unwound by that cancellation becomes pending again,
including nested forces. A later force starts the expression again under the
current providers. Effects already performed remain observable and may run again
on a retry; cancellation is not a transaction.

A Wasm trap or host exception cannot run the language's cancellation cleanup.
The interrupted demand remains terminal, and later forces fail without
evaluating it again. This applies to persistent demands that survive a guest
call. Other entry calls remain usable. Recursive forcing fails rather than
returning an unfinished result. The native evaluator resets its pending state
when a failed compile-time evaluation unwinds; a failed compilation publishes no
successful value or revision.

Executed sync and JSPI laws cover handler `return` and `break`, nested pending
demands, retry under a later handler, normal completion after `yield`, repeated
captured-computation invocation, host exceptions, division traps and recursive
forcing through State. The constant evaluator also rejects the recursive case.
No path may cache a placeholder returned during cancellation. Local memo
elimination must preserve these boundaries; escaping demands retain their shared
runtime cells.

This proposal does not introduce concurrent forcing or cross-thread sharing.
Those would need their own state and synchronization contract.

## Current implementation and evidence

Typed [Core](src/check/core.zig) already has `suspend_` and `force` nodes, typed
captures, and source origins. `suspensionExpression` creates a deferred body; it
does not itself allocate a guest object. Extend this representation and its
consumers instead of adding another frontend or re-inferring source bodies.

The runtime materialization happens in
[the Wasm emitter](src/backend/core_backend.zig): `newTemplate` allocates
captures, `demandDescriptor` allocates a 16-byte cell, and `forceDemand` emits
memo-state checks and an indirect call. The new bounded analysis in
[demand_inline.zig](src/backend/demand_inline.zig) lets the emitter bypass that
representation for admitted calls without changing retained Core.

At commit `775d3707d27c5c5d64504206c6b3824a458d8929`, release compiler identity
`2d8050d273b5baa98107c2a38d4144b92885bbe16d0e510e5b2b41b23968c850`, this runtime
predicate was compared with its explicit `if` equivalent:

```blot
entry const probe = fn (x: U32) -> Bool =>
  (@u32.lt x 100) && (@u32.eq (@u32.rem x 2) 0)
```

| Form            | Complete Wasm bytes | Emitted functions | Demand storage                                             |
| --------------- | ------------------: | ----------------: | ---------------------------------------------------------- |
| `&&`            |               1,579 |                 8 | A 4-byte capture and 16-byte cell, plus allocator overhead |
| Equivalent `if` |                  95 |                 2 | None                                                       |

The two allocations occur before testing the left argument inside `and`, even
when it is false. The `||` comparison gave the same sizes. Both pairs returned
the expected results for ten inputs including 0, 99, 100, and maximum U32. Sizes
include shared allocator/runtime helpers; they are not per-operator costs in a
larger program or a measured runtime slowdown.

After the bounded inliner, both operator probes are 101 bytes with two emitted
functions, no linear memory and no function table. The explicit `if` probes
remain 95 bytes. The six-byte difference stores the eager left argument in a
local. The [library audit](../std/PERFORMANCE.md) records the broader runtime
and compilation measurements; it does not isolate an operator's game cost.

From the repository root, put either source in `probe.blot` and inspect its
output:

```sh
zig-native/zig-out/bin/blotc build probe.blot probe.wasm --prelude std/prelude.blot
wasm2wat probe.wasm
```

The equivalent RHS is
`if @u32.lt x 100 then @u32.eq (@u32.rem x 2) 0 else #False`. Keep the exported
name and signature identical. Regression gates should inspect demand overhead,
not require these exact byte counts forever.

## Compiler plan

[Owned, versioned demand-use summaries](DEMAND_SUMMARIES.md) are implemented in
retained artifact queries. They join dynamic branch counts, preserve aliases and
creation scopes, record conservative capture/provider/request barriers, and
schedule recursive call components to a bounded fixed point. Exact consumed body
admission protects reuse across edits. The existing bounded Plan remains the
lowering proof; broad loop and local memo lowering is a separate stage.

Compute conservative demand-use summaries once per retained checked body. Record
whether each demand can be unused, read once, read repeatedly, forwarded, or
escape, along with the control-flow regions of its reads and relevant
effect/control boundaries. Analyze recursive groups to a bounded fixed point;
unknown uses remain conservative. Refine facts using selected evidence without
turning a caller-constrained result into a principal body scheme.

At code-instance preparation, inline eligible known call structure and choose
one representation per demand creation:

| Proven use                            | Representation                                                          |
| ------------------------------------- | ----------------------------------------------------------------------- |
| Never demanded and never escapes      | Remove the deferred body and capture storage from execution.            |
| At most one dynamic demand, no escape | Evaluate directly at the demand site in its original scope.             |
| Repeated local demands                | Local result, plus initialization state where control flow requires it. |
| Escaping or unknown use               | Shared runtime cell with the required lifetime and effects.             |

Use dense IDs, binding substitutions, and an owned control-flow/emission plan.
Keep published Core immutable. Carry both argument and call-site source origins
into diagnostics. Introduce local memo slots in the creation's dynamic scope,
with joins and loop edges handled explicitly. Sharing among aliases must survive
both local lowering and fallback to stored cells.

Do not duplicate the argument expression at every textual demand. Preserve
shared nodes, and bound cloning of callee control flow to prevent code growth.
Use worklists for long operator chains. Summaries should be proportional to the
retained bodies analyzed; instantiation should be proportional to changed code
instances. General inlining heuristics must not make basic Boolean operators
unexpectedly acquire heap allocation.

### Predictable cost guarantee

Make elimination mandatory for fully applied, statically resolved calls with the
checked `and`/`or` body pattern, including aliases and ordinary user-defined
equivalents. Require known captures, no escaping demand, and proved local
control behavior. Emit a branch without a demand cell, capture allocation,
memo-state check, or indirect call introduced by demand handling. The argument
expressions may still allocate or call indirectly for their own reasons.

Apply that rule in debug and release modes, with source dependencies and
compiled dependencies. A missing analysis summary should trigger analysis of the
available retained body, rather than silently changing the cost contract.
Unknown function values and unresolved control behavior retain a documented
fallback. No new source annotation is needed for this initial guarantee.

Provide an opt-in explanation for each site: eliminated, direct, local memo, or
stored, with its source span and reason. Reasons should identify an unknown
callee, escaping use, unresolved control boundary, or inlining limit. Add
counters for demand allocations, local memo slots, eliminated demands, indirect
demand calls, summary reuse, and nodes visited. These are proposed diagnostics
and counters, not existing CLI features.

### Retained compilation and dependencies

Keep an ordinary runtime demand's memo state separate from compiler caches. Do
not merge distinct demand creations because their expression text, type, or code
key matches. Reusing code never authorizes sharing runtime results. Compile-time
demand values still belong to their evaluator session and exact staging
dependencies.

Key summaries by checked body identity and summary version. Code instances must
depend on every body and piece of evidence consumed by the rewrite, including
latent effects, nominal identities, captures, and relevant settings. Changing a
callee's body while preserving its type can change its demand behavior and must
invalidate inlined callers. An unchanged type interface alone cannot authorize
code reuse.

For example, changing `if a then @demand b else #False` to
`if a then #False else @demand b` leaves its type unchanged but changes caller
code. Test that edit through retained sessions and dependency bundles. Preserve
early cutoff for semantic outputs that are unchanged, while tracking the body
dependency required by emission.

Version any serialized summary or representation changes and let compiler
identity reject incompatible artifacts. Publish new summaries and emitted
fragments transactionally; failed edits must not replace the last good revision.
Preserve the current conservative rebuild for static-capture jobs until their
complete value dependencies are represented in cache keys.

## Implementation sequence

1. Pin the current semantics and the comparison above. Specify cancellation and
   retry gaps separately. Add the proposed intrinsic alias without changing
   evaluation behavior, then migrate source examples and the prelude.
2. Add demand summaries and mandatory elimination for known Boolean-shaped
   combinators. Cover direct calls, aliases, custom fixities, and imported
   prelude bodies, including compiled dependencies. Keep unknown uses safe.
3. Add local memo lowering across branches and loops, then forwarding and known
   callbacks. Check snapshot captures, collection ownership, effect order, and
   per-creation sharing at each extension.
4. Complete escaping-value and request-control cases after their contracts are
   pinned. Integrate source-span explanations and structural counters. Qualify
   retained edits, artifact reuse, and compiler cost before widening inlining
   eligibility.

The rename and optimization can ship independently. Do not claim predictable
allocation until the mandatory lowering cases pass in every supported build mode
and dependency path.

## Acceptance checks

Reuse [demand execution cases](tests/demand_cases.ts),
[lifetime checks](tests/demand_execution.test.ts),
[effect execution checks](tests/effect_execution.test.ts), and the
[checker](src/check/check_demand_tests.zig) and
[Core](src/check/core_demand_tests.zig) laws. Add behavioral and structural
regressions for the new transformations:

| Case                                       | Required observation                                                                        |
| ------------------------------------------ | ------------------------------------------------------------------------------------------- |
| False conjunction and true disjunction     | RHS effects and traps never run; demand handling allocates nothing.                         |
| Taken branch                               | RHS runs once, after the left operand, with no demand-specific indirect call.               |
| Custom operator or alias                   | Same proved body behavior gets the same lowering; different bodies keep their own behavior. |
| Repeated and conditionally repeated demand | One execution per creation; no evaluation on an unselected path.                            |
| Demand outside versus inside a loop        | Sharing follows dynamic creation, including zero iterations.                                |
| Rebinding and collection updates           | Earlier captures retain their values; deferred aliases prevent unsafe destructive reuse.    |
| Provider change between demands            | The first demand chooses providers; later demands reuse its result.                         |
| Escaping aliases and persistent arrays     | Sharing and roots survive guest calls and arena resets.                                     |
| Request exit, trap, and recursive forcing  | Match the pinned completion policy; never publish a partial result.                         |
| Unused but ill-typed argument              | Checking still reports the error.                                                           |
| Callee body edit with unchanged type       | Inlined callers update; fresh and retained outputs agree.                                   |
| Failed edit followed by correction         | Last good revision remains usable; recovery matches a fresh build.                          |

Compare optimized and fallback execution for values, effect traces, traps, and
capture snapshots. Measure additional allocations attributable to demands; do
not mistake allocations in `a` or `b` for an optimization failure. Compare
branch structure with explicit `if`, avoiding brittle exact-byte assertions.

Benchmark dynamic predicates and chains of 1, 8, 64, and 256 operators, both
taken and skipped, including loops. Record guest allocation counts and runtime
separately from compiler time, memory, code size, and summary work. Repeat the
existing gdev cold, first-edit, later-edit, no-op, and recovery measurements.
Keep the approximately 500 ms cold and under 100 ms incremental targets; report
distributions and any regression rather than extrapolating from this small
predicate.

## Recursive forwarding (11 October 2026)

A recursive global has no completed scheme while its component is being checked.
Previously, its first recursive application could constrain the unknown arrow as
eager before the declaration's demand parameter was checked. The later demand
arrow then conflicted with that provisional eager arrow.

For an active recursive global whose type is still an unresolved variable, the
checker now exposes the declaration's direct lambda spine as a monomorphic arrow
shape. Only parameter demand modes are copied; parameter types, result types and
effects remain fresh variables. Ordinary annotation and body checking still
resolve them, and recursive-component completion still publishes the scheme.
Eager-only declarations take the existing path without allocating this header.
No caller annotation environment or completed scheme is borrowed.

Annotated, inferred, shorthand, curried and mutually recursive forwarding are
covered by native laws. The previously skipped bounded-inline-proof law runs
again: recursive forwarding checks, but its recursive body remains ineligible
for that acyclic proof. Allocation-failure testing covers provisional header
ownership. Executed guest laws terminate through base cases for recursion counts
0, 1, 2, 9 and 32, cover annotated/inferred mutual forwarding, reject an unused
ill-typed recursive body, and compare retained edit/revert/rejection/recovery
with fresh bytes and execution. This change does not alter demand memoization,
recursive-force completion policy or inline-proof eligibility.

Focused development qualification used Zig 0.17.0, safe native tests with the
no-LLVM backend, six guest laws, and a zero-findings analyzer. Combined release
qualification and final artifact identities are recorded with the compiler
milestone before completion is claimed.

## Lowering explanations and bounded guarantee (12 October 2026)

Task 039's isolated candidate extends the same source proof through available
foreign bodies and immutable captures. Fully applied Boolean-shaped bodies with
proved local control lower to branches in both codegen tiers. Alias names,
custom fixities, source imports and compiled dependency archives select the
ordinary checked body. The eager condition runs once; the deferred operand runs
only on its selected path. Recursive/unknown control, partial application,
escaping demands and exhausted proofs retain ordinary shared storage.

`blotc build ENTRY OUTPUT --explain-demands` emits a `demand_lowering` JSON
record. The project client accepts `explainDemands: true` when opening a
compiler and returns the report in `stats.demandLowering`. Recording is disabled
by default and does not select a lowering. Native callers without source
identities receive unit IDs and spans with an empty filename.

Reports contain at most 256 decisions, with up to 160 UTF-8 bytes per owned
filename. Truncation is explicit and never splits a code point. `omitted` counts
recording attempts beyond the bound. Decisions name the argument's source span,
in UTF-8 byte offsets, and one of these storage forms:

| Lowering   | Meaning                                        | Typical reason |
| ---------- | ---------------------------------------------- | -------------- |
| eliminated | The pending argument has no admitted use.      | unused         |
| direct     | One admitted use executes at its source force. | proved_local   |
| local_memo | Repeated uses share invocation-local state.    | repeated_local |
| stored     | The ordinary shared runtime cell remains.      | escaping_use   |

Other fallback reasons are `unknown_callee`, `unresolved_control`,
`unavailable_body`, `unresolved_shape` and `inlining_limit`. A known partial
application transports its pending argument into the returned closure and
reports `escaping_use`. Distinct specialization decisions at one span remain
distinct records. Generic storage emission does not overwrite a known reason. An
exact-input rebuild owns a copy of the previous report with zero new work
counters. Explained trivia edits regenerate spans. Explained compilations
regenerate executable fragments to observe all sites; their cost includes that
observation policy.

The always-on work counters describe emitted construction/force sites and
physical memo-local slots, not dynamic guest allocations. They are
`demand_allocations`, `demand_local_memo_slots` (including an owning memo's root
local), `demand_eliminated`, `demand_direct`, `demand_indirect_calls` and
`demand_inline_nodes`. The last counts expression/pattern visits in admitted and
declined inline proofs, including concrete forwarding preflight. Existing
`demand_summary_*` counters describe summary construction, reuse and visits.
Each proof shares its 96-node allowance across callees; local aliases/bindings,
formal parameters and producer normalization remain separately bounded.

The isolated task-039 LLVM Fast checkpoint is SHA-256
`f6f2f57440b23f609f9e47aa412cc882082b204592d23718f793c8cb770243e1`, 41,155,832
bytes, identity
`8ac9b8fc96d5dd006a6d617e53ebed6143f2d5c3c7488985846d4722528f9bf2`. Its source
tree is `bd7fdc04333acc67ad1b54fa0018dfe39dd0ec0d`, staged tree
`32cb648d4e45906ad3f7692b0f8b05538cf4155e`, based on qualified `dd6a66a`. The
source patch SHA-256 is
`c30a3cfba260f3e0bc8d88a81a61af28acfd59a83358a29d97793391fd98721d`. Frozen
artifacts and raw records are in the isolated
`/var/tmp/blot2-demand-guarantee-039/build/bench/demand-guarantee/`.

Focused native/OOM laws cover bounded reports, source ownership, byte equality,
independent unchanged-output copies and failed publication. The release passes
49 executed demand/callback laws plus eight unchanged compile budgets. They
cover both codegen tiers, custom operators, imported forwarding and captures,
archives, checkpoints, repeated/conditional uses, loop creation, providers,
persistent aliases, cancellation, traps, recursion, unused type errors and
failed-edit recovery. The isolated analyzer reports 345 files with zero
findings. The subsequent combined full compiler gate passes at `46bf8b9`, with
914 guest/client laws, eight unchanged budgets and 348 analyzer files/zero.

Seven alternating release compiler pairs measure four functions per source:
conjunction/disjunction chains and their 1,024-iteration loops. Predicates use
distinct dynamic remainder divisors. Left-associative source operators keep
256-operator chains within the unchanged parser nesting limit; that limit still
rejects deeply parenthesized/right-nested source. Explicit controls use ordinary
`if` and local rebinding. Source-only compilation has no implicit prelude/cache.
All chain forms have zero demand construction, memo-slot and indirect-force
sites, no table or linear memory, and zero guest memory throughout execution.

| Operators | Candidate compile CPU ms | Explicit CPU ms | Requested bytes | Proof visits | Summary visits |
| --------- | -----------------------: | --------------: | --------------: | -----------: | -------------: |
| 1         |                    1.189 |           1.074 |         279,238 |           16 |             16 |
| 8         |                    1.839 |           1.508 |         734,905 |          128 |             16 |
| 64        |                    6.896 |           4.428 |       4,367,305 |        1,024 |             16 |
| 256       |                   28.171 |          14.440 |      14,993,826 |        4,096 |             16 |

Requested bytes are exactly equal to the incoming compiler for all eight source
forms. The table separates source/compiler costs from guest behavior; direct
lowering does not make checking a demand chain as cheap as checking its explicit
control. Code size and peak allocation are in `chains/compiler-report.json`; the
256-operator report retains 256 sites and omits 768 additional attempts.

Three complete guest batches retain all 32 taken/skipped/loop cases, each with
12 warm-ups and 31 alternating pairs on CPU 7. Median-of-three CPU ratios to
explicit controls range from 0.9619 to 1.0170. Individual rounds/batches retain
large short-call/JIT outliers (including 1.4498); none are discarded. The first
identical-predicate/adaptive-one-call screen is rejected and preserved
separately. Accepted programs, output hashes, Deno/harness pins and
distributions are in `chains/manifest.json`, `guest-report-{1,2,3}.json` and
`guest-summary.json`.

Seven isolated cold public pairs on CPU 8 preserve all 13 Wasm identities,
semantic and prepared counters, requested/peak bytes and zero teardown live
bytes. CPU ratios span 0.98818–1.02373; no overall speedup is claimed. Seven
synthetic pairs retain cross-compiler and fresh/retained/restart/edit byte
equality. These reproducible controls do not establish the historical gdev
latency target; that remains assigned to tasks 084/093 and their captured-input
qualifications.

## Integrated qualification (11 October 2026)

Implementation `b068dc9` passes the complete native gate, 763 guest/client laws,
all eight unchanged compile-allocation laws and the 323-file zero-findings
analyzer. Shared release parity, current gdev execution, artifact pins and mixed
CPU/allocation measurements are in the
[resolved-body qualification](RESOLVED_BODIES.md#qualification-11-october-2026).

## Integrated task-039 completion (12 October 2026)

Implementation `46bf8b9` qualifies the standard LLVM Fast release
`47021c966f75fbb6063b9de52d476fe944a8aa16dc6bc47aeae66cfbf4dd9095`. The complete
native suite, 914 guest/client laws, eight unchanged allocation budgets and
348-file zero-findings analyzer pass. The independent wire host verifies default
null reporting, all opt-in source fields and unchanged executable bytes.

Three complete final chain/loop batches through 256 operators preserve zero
demand storage and Memory/table, with paired median-of-three ratios to explicit
controls of 0.95096–1.01174. Requested compiler bytes increase by 76 over the
isolated checkpoint; proof/summary counts and chain bytes remain exact. Public
Wasm intentionally changes with the combined ownership subtraction. Exact
source, identity, compiler/guest costs, retained/restart controls and preserved
failures are in
[FRONTEND_OWNERSHIP_QUALIFICATION](FRONTEND_OWNERSHIP_QUALIFICATION.md). The
isolated checkpoint remains separate evidence.
