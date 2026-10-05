# Predictable demand evaluation

Design and implementation status, 2026-10-05. Make ordinary demand parameters
compile to control flow and local values when their uses are known. Keep a
deferred value at runtime only where the compiler cannot eliminate its storage.
The first acceptance case is source-defined `&&` and `||` producing the same
branch structure as their explicit `if` equivalents.

Use `@demand value` for requesting a deferred result; keep `~` on parameters and
types. This document proposes replacing `@force`, not adding a second evaluation
mode. **Both spellings are implemented as aliases.** The first optimization is
also implemented: known, fully applied expression bodies consisting of parameter
reads, scalar intrinsics, `if`, constants and demands use branches and locals.
Analysis admits at most 48 expression nodes. It does not inspect operator names.
Multiple reads use a local memo reset on each invocation, including inside
loops. Other bodies use the existing cell.

Inlining records the consumed module in the caller's code artifact; retained
code validates that module and propagates the dependency across reuse. This is
conservative module validation, not yet a separate body fingerprint. The broader
loop, alias and escape analysis described below remains future work.

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
garbage-collection roots. Avoid allocating a memo slot per iteration for a
demand created outside the loop.

### Completion and cancellation

The successful-result contract is established. Behavior after an aborted or
failed demand needs an explicit compatibility decision before optimizing those
paths. The evaluator currently distinguishes pending, evaluating, and cached
states, resets to pending on an evaluator error, and rejects recursive forcing.
Wasm sets an evaluating marker before the indirect call; a trap or
request-handler exit does not follow the normal cache-publication path. These
mechanisms do not establish a single general retry policy.

Add characterization cases for reentrant demand, guest traps, request `yield`,
handler `return`/`break`, and invoking a captured computation again. Decide
whether an aborted demand becomes retryable or terminal and how partial effects
are treated. Never cache a placeholder result from a cancelled computation.
Until the contract and evaluator/runtime parity are established, keep the
affected demand paths on the existing representation. The initial branch
optimization must exclude cases whose nonlocal exits are unproved.

This proposal does not introduce concurrent forcing or cross-thread sharing.
Those would need their own state and synchronization contract.

## Current implementation and evidence

Typed [Core](src/core.zig) already has `suspend_` and `force` nodes, typed
captures, and source origins. `suspensionExpression` creates a deferred body; it
does not itself allocate a guest object. Extend this representation and its
consumers instead of adding another frontend or re-inferring source bodies.

The runtime materialization happens in [the Wasm emitter](src/core_backend.zig):
`newTemplate` allocates captures, `demandDescriptor` allocates a 16-byte cell,
and `forceDemand` emits memo-state checks and an indirect call. The new bounded
analysis in [demand_inline.zig](src/demand_inline.zig) lets the emitter bypass
that representation for admitted calls without changing retained Core.

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
[checker](src/check_demand_tests.zig) and [Core](src/core_demand_tests.zig)
laws. Add behavioral and structural regressions for the new transformations:

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
