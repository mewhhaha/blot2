# Compiler representation study

2026-09-24. Three `gpt-6-sol` agents at `xhigh` investigated runtime costs,
repeated checking, and solver representation. The coordinating agent measured
current phases and worker scaling, reviewed the experiments, and reconciled the
stateless and session compilation paths.

## Conclusion

The strongest new evidence points to **work amplification in the compiler's
representation and execution model**. From process startup through the first
gdev compile, the runtime performs about 80 million internal heap allocations
and 6.16 million closure applications. The stateless type checker makes only
20,446 top-level type-unification calls. These counts cover different scopes, so
their ratio is not a per-unification allocation measurement. They show why
optimizing the unification rules alone is insufficient.

The next substantial experiment should keep an entire inference/SCC region in
compact owned state: integer symbols and type/row IDs, mutable variable cells,
direct work queues, and freezing only at region boundaries. Combine this with
retained typed bodies and explicit specialization evidence. This changes the
implementation while preserving inference, effects, generics and staging.

A smaller native prototype validates one part of this diagnosis: replacing
`NatIndex.find`'s generated closure-based traversal with a consuming loop
reduced the full gdev compile call from **1,177.4 to 1,090.2 ms (7.4%)**. It is
an isolated experiment, not an installed or fully validated optimization. No
experiment yet demonstrates a 100–200 ms full compilation.

## Baseline and measurement boundaries

The frozen installed native compiler has SHA-256
`7d479e0f4507772a42a8affba04df5d4472a38ab75bf669de2849e005e14cb93`. The workload
is all 16 modules of `../gdev/src/main.blot`, producing 821 checked functions
and a 192,168-byte Wasm artifact, SHA-256
`3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`.

Paired performance samples use fresh native processes and freshly loaded
projects, with a warm filesystem and shared Deno driver. The compile-call timing
includes frontend preparation, encoding, transport, native work and response
decoding. Process startup and source loading are separate. Instrumentation and
prototypes live under `build/architecture-study/`; production compiler source,
installed artifacts, and gdev were preserved.

## 1. Native runtime costs dominate the sampled profile

Five native compiles yielded 5,762 instruction-pointer samples at a nominal 1 ms
CPU interval. All sampled and control runs produced identical Wasm.
Sampled/control median compile times were 1,179.0/1,174.6 ms: about 0.4%
apparent sampling overhead in these runs.

| Native self-sample category                              | Share |
| -------------------------------------------------------- | ----: |
| `term_drop`: reference release and recursive reclamation | 24.1% |
| `span_fade`: extracting fields from shared data          | 10.9% |
| `rfc_wrap`: creating reference-count wrappers            |  4.8% |
| Closure application                                      | 12.5% |
| Native String equality loop                              | 10.8% |
| Map bit traversal                                        |  4.0% |
| Direct String-index lookup                               |  2.6% |

These are disjoint sampled instruction locations, not inclusive function times.
Compiler inlining limits source-level attribution; allocation and reference
management also occur inside other symbols. The first three categories total
39.8%, but eliminating their instructions would not eliminate all representation
costs or imply a sound implementation.

A separate single-worker census, counting from process startup through the first
completed compile, recorded:

- 80,098,230 allocations and 80,062,901 frees in Bend's **custom heap**.
- 159,865,800 allocated eight-byte words: about **1.28 GB of cumulative churn**,
  with roughly 49,000 KiB process peak RSS in the control benchmark.
- 6,161,136 closure applications.
- 2,528,254 applications into `NatIndex.find` branch closures (41.0%).
- 922,699 into dependency membership and 534,455 into specialization membership.

These are not 80 million operating-system allocator calls and not 1.28 GB of
simultaneously live memory. They expose short-lived compiler bookkeeping.

### A measured prototype

The isolated `NatIndex.find` loop preserves ordinary ownership and reclamation
while removing higher-order branch dispatch. Five alternating fresh-process
pairs all produced exactly the same gdev Wasm:

| Metric              |    Current |  Prototype |
| ------------------- | ---------: | ---------: |
| Median compile call | 1,177.4 ms | 1,090.2 ms |
| Median native CPU   |   1,140 ms |   1,060 ms |
| Median peak RSS     | 49,416 KiB | 50,632 KiB |

The later four pairs saved 71–94 ms each; the first pair saved 143 ms and has a
warm-order effect. This establishes a material cost for generated traversal
closures. It does not establish the gain from rewriting every traversal, and it
has not passed the full Nat48 boundary, ownership, diagnostic and proof gates
required for production.

Atomic increments alone are already an examined smaller lever: the previous
study's count-preserving sequential variant saved 1.8%. Disabling reclamation
also previously increased memory sharply. Neither substitutes for reducing the
number of temporary objects and ownership operations.

## 2. Retained checking still leaves repeated body inference

The corrected stateless JS census follows the same `Main.analyze_source`
algorithm as the native compile benchmark. Its checked-module hash matches the
uninstrumented reference. It records:

- 492 distinct generated clone names and **830 clone-body inference entries**:
  492 during specialization and 338 during final checking.
- 152 successful same-frontier follower replays; existing reuse is working.
- 49,834 recursively counted clone body-object nodes, 50.8% of all inferred
  body-object exposure. This is a structural count, not CPU attribution.
- 706 `infer_pending` calls and 3,612 specialization `solve` entries.
- 833 associated-selection attempts and 172 operation-selection calls.
- 20,446 top-level `Infer.unify` calls and 166,252 `Types.resolve` calls.

Source checking retains enough information to establish principal signatures,
then `Mono.shape_bindings` discards body definitions and solver state.
Specialization subsequently infers generated AST bodies. A signature cache
cannot replace that work: selected callees, operation families, captured
providers and nominal equality decisions are part of the result.

Retain a typed source body and its deferred obligations at an independent SCC
boundary. Instantiate type/row variables and solve the obligations at each use.
Carry selected targets and provider/nominal choices as explicit evidence into
code generation. Separate the identity of the source scheme, the obligation
solution, and the emitted code variant. Preserve ordered errors and exact
catalog dependencies.

Value-dependent builders and compile-time branching are the hardest boundary.
`ecs.register_component` changes the world schema and introduces State
operations; `app.add_system` changes the schedule. These need typed partial
evaluation or an exact fallback. A scheme frozen after caller constraints or one
staged branch is not reusable principal evidence.

**Path correction:** an initial census used `NativeSession.update` in analysis
mode. That path bypasses the stateless frontier coalescer and inferred all 492
clone bodies twice. Its 24,096 unifications and 209,197 resolves are kept as
separate session data; they are not the current stateless baseline counts.
Sharing coalescing with the session planner is an additional possible win.

## 3. Solver state should survive across operations in a region

The session trace captured 25,894 real top-level type/row obligations and 38,478
distinct persistent history cells. It observed no repeated binding of a variable
within its active type or row history. The captured replacement values also
contained no references to variables already bound earlier on their path. These
observations support investigating a one-assignment cell fast path; they do not
prove an invariant for all accepted programs.

The solver agent built an integer-ID, dense-cell JS replay for one maximal
history chain:

- 3,648 actual captured obligations and 6,470 history bindings.
- One-time conversion reads 43,804 type-node occurrences and 8,763 row nodes,
  producing 10,594 interned type IDs and 2,280 row IDs.
- All 3,648 calls succeed in the prototype.
- A reproducible sample of 256 calls matches the existing solver on success,
  next fresh ID, added-binding count, both fully resolved operands, and resolved
  newly added bindings.

The replay advances through **captured authoritative histories**, rolls back
trial writes after each call, and checks successful obligations. It is not an
integrated replacement compiler, a complete error oracle, or a native speed
measurement. Ordered/duplicate row labels and arbitrary chronological histories
still require explicit correctness coverage.

There is a concrete reason to retain that boundary: with chronological input
`?1 := F32; ?2 := ?1`, the existing resolver returns `?1` for `?2`; a naive cell
follower returns `F32`. Both variables were assigned only once. Thus single
assignment alone is insufficient: the fast path also needs normalized
replacement invariants, or version-aware edges and a compatible fallback.

For scale only, the JS replay measured 34 ms initial conversion and a median
14.1 ms across five warmed replay passes, including 8.5 ms freezing/normalizing
the trial results. Trace-file loading/parsing took another 119 ms and is
excluded. This is a partial, oracle-fed JS replay, not a native comparison or an
end-to-end latency forecast. Its conversion and freeze costs reinforce the need
to retain compact state across operations.

Importing a separate full history for each of these calls would revisit
12,576,884 cells, versus 6,470 once along the shared path: a 1,944-fold
difference in **hypothetical import work**. The existing compiler does not
currently perform that proposed per-call import. The selected session history
path can cross checker tasks: this does not demonstrate that a single stateless
SCC arena would retain all that sharing. It is evidence for selecting a region
boundary that amortizes import, rather than converting full histories at each
helper call. The actual region boundary and its savings remain to be measured.

## 4. More workers currently provide little benefit

Three alternating pairs per comparison give these compile-call medians:

| Workers | Matching one-worker control |  Candidate | Change |
| ------: | --------------------------: | ---------: | -----: |
|       2 |                  1,172.1 ms | 1,275.6 ms |  +8.8% |
|       4 |                  1,171.0 ms | 1,176.2 ms |  +0.4% |
|       8 |                  1,170.8 ms | 1,131.6 ms |  −3.3% |

Eight workers use about 1,600 ms native CPU versus 1,130 ms for their control. A
four-worker runtime trace contains a 417 ms turn where one worker consumes 415
ms CPU and every other worker less than 1 ms. Another 435 ms turn has worker CPU
times of 73/98/71/434 ms. Coarse source-level independence has not translated
into balanced native work.

Compact worker-owned regions should precede further scheduler tuning. Then
schedule independent source SCCs and specialization jobs, sharing immutable
interfaces and merging results deterministically. The staged shared-constant
dependency chain requires reducing its work as well as finding parallelism.

## Target budget and next implementation

Current one-worker entry-to-entry CPU intervals are approximately:

| Interval                                |    CPU |
| --------------------------------------- | -----: |
| Decode, lowering and initial planning   |  65 ms |
| Initial checking                        |  94 ms |
| Shared specialization preparation/work  | 199 ms |
| Remaining specialization                | 368 ms |
| Final planning/checking/export          | 333 ms |
| Constant evaluation                     |  38 ms |
| Wasm preparation, emission and response |  76 ms |

These are coarse diagnostic intervals, not independent optimization budgets.
Even deleting the entire specialization and final-check intervals would leave
about **273 ms native CPU**, before host costs. Deleting initial checking too
would leave about 179 ms. These deliberately impossible bounds show why 100–200
ms requires savings across the pipeline. The remaining costs are not immutable
floors, but they must be measured and addressed.

Recommended sequence:

1. Harden the measured direct-lookup prototype and remove other proven branch
   closure hotspots. This is an immediate, bounded improvement.
2. Build one complete compact inference region with integer symbols, type/row
   IDs, owned variable cells and direct queues. Import once, run all local
   inference/obligation operations, freeze the principal result once. Compare a
   Bend linear-buffer implementation with a native region implementation where
   appropriate; retain the existing solver as the semantic oracle.
3. Retain typed generic bodies plus explicit obligations/evidence. Start with a
   transitive chain such as `Array.get → ecs.component_at → ecs.at`, then a
   complete component-registration chain. Remove both generated-body checking
   passes for supported cases while preserving the original fallback.
4. Remeasure allocations, phase time, full compile time and RSS; then optimize
   staged evaluation, wire representation, and coarse parallel scheduling.

Acceptance requires exact successful artifacts and principal interfaces, ordered
failure equivalence, occurs checks, pure-let generalization, ordered duplicate
effect labels, scoped State/provider identities, captures, nominal dispatch,
recursion, invalidation, and failed-edit recovery. A production integration must
pass the existing tests and Bend proof gate. No new language restriction is
proposed.

## Relevant compiler designs

These are design precedents, not performance predictions for Blot:

- [Zig's current InternPool](https://github.com/ziglang/zig/blob/master/src/InternPool.zig)
  uses integer indices for interned types/values and strings, plus explicit
  analysis-unit dependencies and thread-local storage with shared shards.
- [Rust's type representation](https://rustc-dev-guide.rust-lang.org/ty.html)
  interns types and caches structural information. Its
  [memory guide](https://rustc-dev-guide.rust-lang.org/memory.html) describes
  arena lifetimes and sharing canonical types.
- [Go's compiler architecture](https://go.dev/src/cmd/compile/README) retains
  typechecked code in Unified IR and supports indexed, lazy decoding of exported
  object graphs.

## Reports and reproduction

- Runtime profile, allocation census and native lookup experiment:
  `build/architecture-study/cost/REPORT.md`.
- Stateless/session body and obligation census, typed-scheme design:
  `build/architecture-study/checking/REPORT.md`.
- Captured solver histories and compact replay:
  `build/architecture-study/solver/REPORT.md`.
- Current phase markers, raw timing pairs and worker traces:
  `build/architecture-study/root/README.md`.
- Frozen input files and their hashes:
  `build/architecture-study/baseline/SNAPSHOT.json`.

The experiments establish concrete costs and one 7.4% improvement. The larger
representation change remains a hypothesis to validate end to end.
