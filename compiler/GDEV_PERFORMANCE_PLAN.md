# Gdev compile-time investigation and plan

Date: 2026-09-23. Investigation of the current working trees, using three
gpt-6-sol agents at xhigh effort. The measurements below describe the saved
preimplementation baseline; see
[implementation results](GDEV_PERFORMANCE_RESULTS.md) for the approved
optimization work and subsequent measurements.

## Recommendation

Keep the language surface initially. Reduce repeated specialization/inference,
then retain that work across project edits. If those changes cannot meet the
latency target, test a simpler ECS schema representation and a typed compiler
core before committing to a language or implementation-language rewrite.

Treat clean compilation and edit latency as separate objectives. Suggested
decision targets are below one second for a clean gdev build and below 200 ms
for an ordinary function-body edit. These are goals to test, not predicted
results or requirements already agreed with the user.

## Current measurements

The current application contains 16 modules, 55,988 source characters and 35,688
CST nodes. The compiler reports 821 functions and emits 192,168 bytes of Wasm.
This is a newer workload than the 15-module checkpoints in
[CONCURRENCY.md](CONCURRENCY.md); their function counts and phase times must not
be substituted for this revision.

Three sequential clean requests in each retained native process, milliseconds:

| Native threads | Median native request | Median load-through-instantiation | Total range |
| -------------- | --------------------: | --------------------------------: | ----------: |
| 1              |                 3,134 |                             3,233 | 3,001–3,369 |
| 2              |                 3,025 |                             3,121 | 2,948–3,403 |
| 4              |                 2,823 |                             2,924 | 2,792–3,148 |
| 8              |                 2,810 |                             2,915 | 2,794–2,983 |

These are exploratory desktop measurements, without CPU isolation or discarded
warmups. Sample order, process retention and background load can affect results;
small differences between configurations are inconclusive. The native interval
includes request/response transport. Total time includes project loading,
frontend preparation, encoding, native compilation, decoding and instantiation;
it excludes one-time compiler setup, catalog loading and application activation.

One-time frontend setup was about 40–43 ms and process startup 3–5 ms. Project
loading took 67–116 ms, preparation 2–6 ms, encoding 10–16 ms, decoding 5–9 ms,
and Wasm instantiation less than 1 ms. About 97% of the one-thread median total
is in the native request. Eliminating frontend work alone cannot remove the
multi-second delay. Eight threads help modestly in this sample, rather than
providing a solution to the latency problem.

Raw samples and the reproduction script are in
[build/gdev-investigation](../build/gdev-investigation/) (ignored local
investigation artifacts). From the blot2 root:

```sh
deno run --allow-all build/gdev-investigation/measure.ts 1 3
deno run --allow-all build/gdev-investigation/measure.ts 8 3
```

### Current native phase trace

A temporary C build generated from the current Bend sources, with timestamps at
phase boundaries, produced the same 192,168-byte Wasm as the production binary:
SHA-256 `3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`. Both
artifacts were instantiated successfully. One one-thread diagnostic request took
2,959 ms up to the ready-to-send boundary:

| Phase                                                                  | Wall time |
| ---------------------------------------------------------------------- | --------: |
| Request decode, prelude/project lowering and effect-family preparation |     48 ms |
| Specialization: graph setup and initial shape inference                |    147 ms |
| Specialization: template setup and shared constants                    |    344 ms |
| Specialization: declaration expansion/inference                        |    999 ms |
| Specialization: public expansion/interface refresh                     |    326 ms |
| Final checking of the specialized module                               |    949 ms |
| Final constant evaluation                                              |     56 ms |
| Wasm emission                                                          |     67 ms |
| Response encoding and preparation                                      |     24 ms |

Rounded intervals need not sum exactly. This is a diagnostic sample, not an
isolated production benchmark. The trace used Bend 2.0.24 and clang 22.1.8 with
`-O2 -w -pthread`; its percentages describe that instrumented build, not precise
production phase measurements. Specialization totals about 1,816 ms (61%); final
checking adds 949 ms (32%). These stages account for approximately 93% of the
native request. The specialization interval includes its own inference work; the
56 ms const interval does not include specialization of shared constants. It
would be misleading to attribute all compile-time builder work to that final
const interval.

Three additional requests in a retained traced process corroborated this split.
Across all four diagnostic requests, median native time was 3,071 ms; median
declaration specialization was 1,035 ms and median final checking 964 ms. Final
constant evaluation remained 56–69 ms and Wasm emission 67–90 ms.

The trace supports optimizing expansion/inference first. Even a hypothetical
complete removal of final checking would leave roughly two seconds; reaching a
sub-second clean build requires reducing specialization too. Actual final
validation must remain sound. Removing final const evaluation or Wasm emission
entirely would each save only about 2% in this sample.

See [the trace](../build/gdev-investigation/trace-1067316.jsonl),
[the instrumenter](../build/gdev-investigation/instrument.py), and
[stock](../build/gdev-investigation/stock_hash.jsonl)/[traced](../build/gdev-investigation/traced.jsonl)
output hashes. Rebuild/reproduce the diagnostic from the blot2 root:

```sh
BEND_NO_TELEMETRY=1 bend compiler/native_main.bend -o build/gdev-investigation/blotc.c
python3 build/gdev-investigation/instrument.py
clang -O2 -w -pthread build/gdev-investigation/blotc-trace.c -lm -o build/gdev-investigation/blotc-trace
deno run --allow-read --allow-run --allow-env build/gdev-investigation/measure.ts 1 3 build/gdev-investigation/blotc-trace
```

Production executable SHA-256:
`9a3f74a1488a66868df544c6cd913291df43b1c1940b94f41ac6da74ac3f6aec`. Generated
uninstrumented C SHA-256:
`41bd86877a63c9ed6f905cbd2db0dd9ae5e12566340dadac8ffddbea591580f9`.

## Established implementation causes

1. **Reload repeats a clean compile.** `../gdev/blot_runtime.ts:68-84,161-170`
   retains a native process but creates a fresh source project and calls the
   stateless compiler for every reload. It supplies no thread count, so
   `native_process.ts:46` selects one. The watcher adds 75 ms of debounce
   outside the compile timings. Reusing the process is not equivalent to reusing
   checked program declarations.
2. **Existing incremental caches begin too late for specialization.**
   `native_session.bend:998-1013` calls `Families.prepare` and `Mono.prepare` on
   the combined module before looking up cached inference groups. Merely adding
   import support to the current single-file incremental API would retain this
   specialization cost on changed revisions.
3. **The pipeline repeatedly infers related program representations.**
   `monomorph.bend:491-494,1653-1661` obtains whole-module inferred shapes.
   `:1449-1473` expands and infers specialization units; `:1508-1528` refreshes
   affected interfaces against completed dependencies. `main.bend:36-41` then
   checks the prepared module before evaluating constants. Refreshing effects is
   necessary for correctness; the opportunity is to retain sufficient typed
   results, rather than blindly removing checks.
4. **Expansion can create repeated copies.** `monomorph.bend:381-401` clones
   template references, using an active recursion stack and counter-based
   generated names. It is not a global cache keyed by concrete instantiation.
   Some specialization lookups at `:68-88,253-259` also use eager recursive
   `Bool.pick` fallbacks, so finding a match does not stop the remaining
   traversal. Their current timing contribution still needs measurement.

Earlier work already indexed type/row substitutions, parallelized specialization
units, retained shared-constant interfaces and avoided merging inherited
environments. Those improvements are in the current tree; repeating their
descriptions is not a new optimization plan.

## Why gdev stresses this implementation

The ECS is ordinary source code, not a compiler intrinsic. Its builder grows the
type of the world after each registration (`../gdev/src/ecs.blot:35-61`). Five
resources and three components each have a current and snapshot cell, alongside
Entities and Entity: 18 nested world cells. Each component also adds three
provider wrappers (`:125-135`). The application registers ten systems.

This combines generic functions, closures, inferred effect rows, type-directed
member selection, type equality and compile-time construction. Those features
are plausible multipliers of expansion and inference work. They are not proof
that any one feature must be removed. The numeric protocol module is also a
substantial part of the source, so experiments must keep the actual application
behavior rather than obtain speed merely by deleting its work.

## Implementation sequence

### 1. Establish a repeatable gdev performance gate

Capture source and executable hashes and run alternating candidate/baseline
samples on the same CPUs after builds finish. Separate first compile, repeated
clean compile, an ordinary system-body edit, an ECS schema edit, an invalid edit
and recovery, and an unchanged request. Retain per-phase timing and counts of
clones, unique concrete instantiations, re-inferred declarations and type nodes.
Use current gdev plus small ordinary compiler fixtures to catch regressions.

### 2. Remove avoidable work without changing language behavior

First test short-circuit/indexed specialization lookup. Then count repeated
instantiations and trial memoization within a compilation. Preserve first-match
lookup semantics, diagnostic priority, nominal identities and resource limits.
Keep a change only when paired whole-request measurements show a useful gain.
Current expansion creates clones before their concrete choices are solved; safe
deduplication needs staged inference or canonical post-inference keys, rather
than a function-name lookup inserted into the expansion loop.

The larger optimization is to carry typed specialization results into the next
phase. Today's specialization returns a rewritten module and inferred bindings,
not a fully validated checked module. Preserve coverage/reflection constraints,
dependency/name validation and diagnostic ordering alongside typed interfaces,
resolved member choices, effect rows and bodies. Attach dependency fingerprints
and re-infer affected components, with the existing final checker serving as an
oracle during development. Remove a redundant production traversal only after
differential checks establish parity. This addresses clean builds as well as
edits.

### 3. Add project sessions that also retain specialization

Persist the import graph, parsed module/declaration identities and source
origins. Send changed declarations, and invalidate dependents based on actual
body/interface/schema dependencies. Reuse the existing transactional
type/const/code caches after the retained specialization stage.

Generated identities must be stable across unrelated edits. A specialization key
needs more than a function name: source identity/body, concrete type and effect
arguments, dispatch choices, relevant nominal schemas and lexical or capture
dependencies. Do not reuse the current traversal counter as a durable identity.
Shared const-evaluation fuel and failure ordering must remain intact.

Expose this through a project session API and connect gdev's reload loop. Keep
the previous artifact and acknowledged cache revision after failed edits.
Measure invalidation breadth: a local motion-system edit with unchanged checked
effects and schema should not rebuild the entire engine merely because the
compile-time application closes over it. Changed effects can require broader
revalidation. Include a retained-edit memory test: the existing
[memory report](MEMORY.md) records a Bend allocation issue relevant to
long-lived processes. Recheck its status on the chosen backend before relying on
unbounded session lifetimes.

### 4. Use controlled language/library experiments if needed

| Option                           | Experiment                                                                                                        | Tradeoff and decision condition                                                                                                                                            |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| More explicit generic boundaries | Annotate selected high-fanout helper signatures, use concrete operator/member calls in a copied fixture           | Small ergonomic cost; useful only if it removes measured solver passes or ambiguity. Annotations alone need not stop cloning.                                              |
| Fixed ECS schema                 | Replace the nested registration chain in a branch with one explicit or generated world/schema and typed accessors | Reduces type growth while keeping typed gameplay code. Trades open-ended plugin registration for explicit schema composition; compare runtime behavior and compile counts. |
| Explicit staging                 | Make schema construction a distinct stage with stable output interfaces, separate from changing system bodies     | A clearer cache boundary, but changes builder authoring and can restrict arbitrary compile-time closures. Prototype in the library before adding language rules.           |

Keep rendering, entity behavior, save/load and state-preserving reload
equivalent in these comparisons. Vary resource count, component count and system
count independently to distinguish nested type growth from source size. The
fixed-schema experiment must also replace the per-cell handler construction and
generate the matching accessors, snapshots and codec; merely flattening a type
while retaining that handler chain may preserve most specialization work. Check
immutable world-copy costs and frame time as well as compilation.

### 5. Reserve larger pivots for measured failures of the above

**Typed elaboration core:** retain today's source syntax but elaborate generic
definitions once into a typed intermediate representation with explicit
operation/member evidence and deferred constraint placeholders where choices
remain generic. Discharge those constraints, and re-infer choice-dependent parts
where necessary, through a memoized instantiation worklist. This is the
preferred larger compiler pivot: it targets repeated semantic work and supplies
a natural incremental boundary. It requires careful inference/effect semantics
and substantially more engineering than a lookup fix.

**Runtime capability dictionaries:** lower selected generic operations to a
uniform explicit capability record, sharing bodies instead of cloning handlers
per use. Keep static effect checking. This could reduce specialization but can
introduce indirect calls, larger environments and weaker runtime optimization.
Sharing code across different value layouts also requires a common boxed
representation or specialization by ABI shape. Measure both compile latency and
frame performance before adopting it.

**Different compiler implementation language:** first profile allocation,
structural traversal and reference-count/scheduler costs after algorithmic
improvements. Prototype one hot pass with an equivalent IR in an isolated
backend if those costs dominate. Rewriting the same repeated inference pipeline
in Rust/C++/TypeScript has no established speedup here and would require
replacing or re-establishing the current Bend laws and validation strategy.

## Validation and stopping rules

Implementation changes must preserve compiler diagnostics, effect propagation,
exports, nominal identities and resource-limit behavior. For semantic-preserving
changes compare artifacts exactly when identities remain stable; otherwise
compare ABI, diagnostics and execution against the clean oracle. Run the
compiler regressions, gdev tests and `bend PROOF.bend` before committing.

Do not spend another broad cycle tuning forks, parser workers or output packing
unless the new phase profile assigns substantial cost there. Do not remove
effects or rewrite the compiler on the strength of the total three-second number
alone. Choose the next step from measured work eliminated, not a promised
speedup.
