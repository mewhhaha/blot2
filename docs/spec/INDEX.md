# Blot K1 — language redesign and implementation handoff

**Edition: K1 revision 1, 26 October 2026. Status: normative implementation target; implementation and qualification are pending.**

This issue is the ongoing design index for a deliberately breaking redesign of Blot. The selected goals are checked correctness, functional abstractions, predictable storage, a small compiler core, and fast, bounded compilation work. The linked specifications replace the earlier prototype recommendations in this issue. They choose one implementable first edition instead of leaving competing architectures for an implementation agent to resolve.

**The K1 language runtime has no tracing GC, cycle collector, per-value reference counting/ARC, hidden shared owners, or implicit closure boxes.** Memory authority is checked statically. Allocation uses explicit, fixed-capacity destinations and scoped regions; independently transferable results own one entire backing region. This contract must hold with optional optimization disabled.

## 1. Normative specification and reading order

| Part | Scope | Authority |
| --- | --- | --- |
| [K1-LANG — Language, contracts, and relational data](https://github.com/mewhhaha/blot2/issues/40) | Grammar, explicit exits, types, effects, finite flow proofs, generics, closures, loops, packages | Source semantics and diagnostic meanings |
| [K1-MEM — Scoped memory, runtime, and ABI](https://github.com/mewhhaha/blot2/issues/41) | Pool, capabilities, initialization, failure paths, owned packages, layouts, call ABI, host copy protocol | Storage transitions and physical ABI |
| [K1-CORE — Checked artifacts and compiler](https://github.com/mewhhaha/blot2/issues/38) | Core schema, independent validator, completed interfaces/functions, no late inference, work budgets, optimizer and reuse | Compiler phase and artifact contracts |
| [K1-EXEC — Implementation and qualification](https://github.com/mewhhaha/blot2/issues/39) | Ordered milestones, source map, conformance laws, failure injection, gates, benchmarks and rollout | Required work and completion evidence |

Read this index, then all four parts before changing shared schemas. Section IDs within a part are stable anchors. All parts form one specification: a contradiction is a specification bug to resolve explicitly, not permission to choose the easier behavior. The index's goals and exclusions are binding; the research and future-experiment sections are informative. Examples use proposed K1 syntax unless explicitly identified as current source.

Versioned identifiers are `K1-SEM-POLICY-1`, `K1-OPT-POLICY-1`, and `K1-WASM32-ABI1`. Changes to required reasoning, layout, or operation semantics require the corresponding version/key change and regression laws. Implementation details that preserve these contracts do not require design approval.

**Reviewed baseline:** Blot [`1e39b5d8a4268b9edf769c2813d5231abe1c963b`](https://github.com/mewhhaha/blot2/commit/1e39b5d8a4268b9edf769c2813d5231abe1c963b). Goose reference: [`a108677d300cb0e8bbb842c35a353abe67a20c6c`](https://github.com/aardappel/goose/commit/a108677d300cb0e8bbb842c35a353abe67a20c6c). Existing source and qualification documents were reviewed; this specification does not claim a new compiler build, performance result, or mechanized soundness proof.

## 2. What “if it compiles, it is correct” means

Compilation establishes the stated and inferred contracts of the safe language. It cannot establish unstated application intent. Explicit fallible operations are allowed: a checked program can handle an absent index or exhausted reservation. A hidden trap cannot satisfy a required safety obligation.

| Guarantee | Binding K1 mechanism |
| --- | --- |
| Access is within initialized data | Ordinary indexing requires exact bounds evidence; fallible lookup validates dynamically and exposes success explicitly. Capacity alone never authorizes reading. |
| Arithmetic follows its declared meaning | Ordinary U32 arithmetic requires its preconditions. Explicit wrapping APIs have separate semantics. F32 preserves the specified per-operation behavior. |
| Stored relationships remain valid | `Index[d,n]`, generative domains, and existential packages preserve the relation between an endpoint and its collection. |
| Storage remains live and exclusive where needed | Affine capabilities, lexical loans, initialized-prefix builders, and checked scope cleanup. |
| Failures do not lose resources or publish partial values | Result handling and every ownership transition are checked on all exits. |
| Callable behavior is known before emission | Complete effects, capture, usage, and finite depth/frame contracts, including indirect calls. |
| Admission does not depend on optimizer luck | Required checking finishes before optional rewriting; lowering cannot start general inference. |
| Compilation work has a specified ceiling | Finite algorithms, deterministic required limits, bounded optional rewrites, and bounded cache admission. |

The trusted boundary includes the checker/validator implementation, lowering, runtime primitives, and the host/engine contract. The execution part defines tests and qualification for each; passing tests is not presented as a mathematical proof of the whole system. Native/JIT memory consumption is not hidden inside a claim about guest linear memory.

## 3. Decisions selected for the first edition

| ID | Selected decision | Reason and cost |
| --- | --- | --- |
| D01 | One explicit return rule; lexical value blocks use `break value` | Source completion and Core exits have one meaning. Implicit tail returns are removed. |
| D02 | One parameter pattern; calls pass one value, including tuples | No automatic currying or call-site arity discovery. Currying remains explicit function construction. |
| D03 | Immutable bindings, closed operators, explicit rank-one polymorphism | Local checking has a small predictable boundary. Generic operations use explicit function dictionaries. |
| D04 | A finite flow-proof algebra, no general SMT search | Guards, early exits, contracts, and canonical loops produce checkable evidence. Valid mathematics outside the fragment may require an explicit check or simpler contract. |
| D05 | Initialized length, capacity, and collection identity are separate | Prevents both out-of-range reads and accidental reuse of graph endpoints with unrelated collections. |
| D06 | Immutable View plus exclusive Append/Resize builders | Both builders have fixed capacity. Length growth initializes new elements; resize can truncate. Freeze consumes construction authority. |
| D07 | Explicit destinations and a fixed scoped backing pool | No hidden per-element allocation or data movement. Reservation and placement failures have typed outcomes. |
| D08 | Whole-region `Owned` packages, with one backing region | Escaping data and closures have an explicit release obligation. No nested owner graph or runtime reference count is needed. |
| D09 | Closures capture Share values; affine state is an argument/result | Composition works without secretly owning external resources. Escaping environments require explicit placement. |
| D10 | A typed ANF Core with explicit joins, evidence, and ownership transitions | The optimizer sees evaluation order and obligations directly. No CPS conversion or general theorem engine is required. |
| D11 | Complete semantic artifacts before representation lowering | One checked body serves ordinary uses. A backend cannot repair omitted semantics by re-entering inference. |
| D12 | One uniform baseline generic body with bounded indirect slots | Avoids unrestricted monomorphization. Fixed adapters and dictionaries have visible runtime costs; later specialization is optional research. |
| D13 | Finite loops, no recursive declaration/type cycles, finite callable resources | Covers callback-hidden recursion as well as named recursion. Recursive algorithms need an explicit work array or a later extension. |
| D14 | A small deterministic optimizer with strict budgets | Baseline correctness and resource guarantees do not depend on inlining, fusion, or scalar replacement. |
| D15 | A copy-only host bridge, after scalar exports | Establishes input validity and lifetime boundaries. Zero-copy, reentrancy, asynchronous callbacks, and foreign ownership are excluded from K1. |

These choices are intentionally restrictive where doing so removes a whole class of compiler/runtime machinery. They define a useful data-processing language with functions, products/sums, closures, generic operations, local graph packages, and explicit storage. They do not claim feature parity with every historical Blot construct.

## 4. Syntax and access examples

The three requested function forms have the same result behavior:

```blot
let a: U32 -> U32 = fn x => return x

let b: U32 -> U32 = fn x => do:
  return x

let c: U32 -> U32 = fn x => return do:
  break x
```

Inside a function where `a` is an immutable View and `i` is U32:

```blot
if i < a.length:
  return #Some(a[i])
return #None
```

The guard is runtime work that creates static authority on its true edge. The element read itself needs no additional dynamic bounds decision once that edge's evidence is validated. Returning early on the failing edge is equally valid. A separately declared predicate can provide the same facts only through its checked Boolean contract.

The distinction in the original question matters: **`a.length < N` and `i < N` do not prove `i < a.length`**. For example, length 3, index 7, and N=10 satisfy both premises and still give an invalid access. Exact `length=N`, a lower bound `N<=length`, or a direct guard against the actual initialized length can supply the needed relation. An `Index[d,n]` stores the validated relationship rather than relying on a detached upper bound.

The language part gives complete contracts, explicit array construction, region/owned scope syntax, and graph package construction. K1 keeps `#[]` as the literal family; Append and Resize are named modes, rather than adding independent bracket grammars for ownership, capacity, and mutability.

## 5. Goose alignment and deliberate adaptations

[Goose's pinned specification](https://github.com/aardappel/goose/blob/a108677d300cb0e8bbb842c35a353abe67a20c6c/docs/goose_spec.md) supplies the useful starting point: statically constrained lifetimes, storage placed in lifetime order, destination construction, and reclamation at scope boundaries without GC or RC. K1 keeps that direction.

K1's initial Wasm target uses a **preallocated finite pool**, explicit capacity, and explicit reservation failure. It does not depend on native multi-gigabyte virtual-address reservations, growth without capacity checks, or Goose's particular whole-program specialization strategy. Multiple independent region owners permit escaping Blot packages; they need bounded region metadata and a pool bitmap. There is no metadata per array element or per shared loan.

The default profile reserves a 16 MiB backing pool, 1 MiB frame arena, 256 owner slots, and separate 64 KiB input/output windows. The manifest accounts for metadata, static data, padding, and page rounding as well. Values are configurable within the specified hard limits; they are engineering defaults, not claims of optimal sizes. There is no `memory.grow` in K1 code. Reset is constant-time cursor restoration; release clears a bounded bitmap run and is not falsely described as constant time.

The memory chapter specifies empty/zero-sized values, byte-overflow checks, exact initialization, failure-state restoration, owned capsule construction, generation retirement, closure layout, the call ABI, and host publication order. Those details are necessary for the no-GC/no-RC claim to survive real implementation.

## 6. How simple code becomes fast code

The first performance target is a particle projection: read `{x,y,vx,vy}`, compute `x + vx*dt` and `y + vy*dt`, and write `{x,y}` into a supplied destination. The canonical loop proves `initialized_length(output)=i` and `i<=N<=capacity`; the body edge proves each input read and output append.

The baseline should already be one counted loop with four field reads, two multiplies, two adds, and two output stores per element, plus loop/descriptor work. It needs no intermediate collection, element box, retain/release, collector root, per-row backing allocation, or output copy inside the language kernel. The host bridge's explicit copy is measured separately. Separate F32 rounding remains observable; this target does not authorize implicit FMA contraction.

Cheap local folds remove administrative blocks, forward known values/projections, reuse immutable lengths, and convert known closure calls to direct calls. They cannot erase an observable capacity failure, merge fresh domains, move a failing expression into a zero-iteration path, or duplicate an effectful predicate to count a filter. Stronger release transforms come after the baseline qualifies and retain the same contracts.

Compile-time performance has similarly concrete gates: zero downstream solver creation, one baseline generic body, immutable completed artifacts, semantic caller cutoff when an interface is unchanged, bounded rewrite work, and measured cold/edit/cache costs. No speedup percentage is promised before paired measurements.

## 7. Ordered implementation and finish line

| Stage | Deliverable |
| --- | --- |
| K1-00 | Edition selection, operation/schema IDs, diagnostic catalogue, scalar admission fixture |
| K1-01 | Grammar, formatter/editor support, explicit completion and lexical targets |
| K1-02 | Checked scalar Core, owned completed artifacts, independent validator, late-inference prohibition |
| K1-03 | Required bounds/arithmetic proofs, explicit evidence, storable Index, deterministic limits |
| K1-04 | Scoped pool/destinations/builders and the unoptimized particle vertical slice |
| K1-05 | Relational graph packages with once-validated stored endpoints |
| K1-06 | Share-capturing functions, explicit environments, finite direct/indirect call resources |
| K1-07 | Whole-region ownership and mandatory copy-only host array bridge |
| K1-08 | Rank-one generics, layout obligations/dictionaries, explicit static evaluation |
| K1-09 | Bounded local optimization, portable reuse, corruption handling and transactional publication |
| K1-10 | End-to-end migration, documentation, complete qualification and rollout decision |

Each stage has positive and negative laws in K1-EXEC. A narrow milestone may be complete while later features remain unsupported; it may not publish artifacts containing promises deferred to those later features. Keep K1 explicitly selectable while legacy remains the default. Change the default only after the complete rollout gate.

Required final evidence includes the exact commit/toolchain, test inventory, native and executed-Wasm laws, allocation-failure sweeps, malformed-artifact and host-input tests, ownership/error traces, structural no-managed-helper certificate, solver counters, cache/edit behavior, generated-code inspection, and paired performance data. Repository `AGENTS.md` remains binding. In particular, native development/tests use the required noLLVM configuration, lint must pass, and the full compiler gate is required before compiler commits.

### Implementation-agent prompt

> Implement Blot K1 revision 1 from https://github.com/mewhhaha/blot2/issues/37 and all four linked normative specification parts. Read the complete handoff before editing shared contracts. The reviewed baseline is `1e39b5d8a4268b9edf769c2813d5231abe1c963b`; inspect the actual current checkout, preserve unrelated changes, and follow its `AGENTS.md`, guide, and ownership contract.
>
> Create an implementation ledger and work through K1-00 to K1-10. Keep K1 explicitly selectable; do not silently change legacy semantics. Implement the unoptimized checked path first. Required bounds, initialization, lifetime, usage, effects, and resource contracts must hold before optional optimization. After semantic admission, forbid new general inference at its constructor seam and verify both active-region balance and creation/completion counters.
>
> Use scoped storage with explicit destinations, no tracing/cycle collection, no per-value RC/ARC, and no hidden heap or legacy fallback. Preserve the exact capability state on typed failure. Use the completed generic body and explicit dictionaries/adapters rather than rechecking bodies per call. Enforce versioned required budgets and let optional exhaustion fall back to valid baseline code.
>
> Add the specified accepted/rejected laws and executed runtime cases at each milestone. Qualify the particle loop, graph package, closures, owned packages, copy bridge, artifact corruption, cancellation, failure injection, and retained edits. Run the repository gates and publish the evidence; do not substitute historical test counts or a sampled run for current qualification.
>
> Resolve ordinary implementation details autonomously. If a normative contradiction or missing sound representation is found, record a minimal counterexample and the smallest explicit amendment; do not silently weaken a guarantee. The future experiments and research section are not additional mandatory features. Report completed stages, deviations, remaining gates, measured costs, and the final source commit.

## 8. Future experiments, separate from K1 acceptance

These ideas are welcome only after the first kernel has a measured, qualified baseline. Each must explain which machinery it removes or which useful program it admits, its exact semantics, and its compiler/runtime cost.

1. **Turn recursive algorithms into explicit work data.** Add checked tail-recursion-to-loop sugar or finite work-array combinators before considering general recursion. A bounded stack of Plain work items exposes capacity and error policy directly.
2. **Definition-derived ABI summaries.** Add compositional flattening/uncurrying summaries without revisiting source bodies at every use. Unknown calls retain the uniform ABI; executable dependencies track summary changes.
3. **Small offline-verified rewrite tables.** Express local folds declaratively, test or prove them outside ordinary builds, and ship a cheap matcher/checker. This can strengthen confidence without putting SMT search into every compilation.
4. **Borrowed producer pipelines.** Library combinators can state one-pass callback order and destination construction directly. They may avoid the difficult legality proof required to fuse two already-eager computations.
5. **Certified package transformations.** Define whole-graph remap/reorder operations that transport endpoint relationships through an explicit bijection or validation result. Do not equate domains just because lengths match.
6. **Native storage backend or bounded streaming bridge.** Preserve source ownership/proof contracts while changing backing reservation or transfer mechanics. Zero-copy and persistent handles require their own host lifetime/reentrancy protocol.
7. **A smaller total sublanguage for contracts and static computation.** Compare a separately specified evaluator with extending the general language. Measure what it removes from completion and artifact dependencies.

General shared ownership, GC/RC fallback, unchecked array access, and optimizing away missing correctness proofs are not proposed extensions to the selected contract.

## 9. Baseline work and issue maintenance

At the reviewed baseline, numeric aggregate layouts, bounded rectangular pipeline work, copy facts, collector-free certification, and memory attribution already exist. Preserve their regressions. The latest work closes #28/#32/#33/#35/#36, following #29/#30/#31/#34; these are historical foundations, not unfinished K1 tasks. The new scoped ABI is a stronger and separate contract: existing collector-free execution may still use RC/destruction.

Keep this issue as the decision/index ledger. Keep normative rules in their owning part, executable evidence in implementation issues/PRs, and speculative proposals in section 8 until selected. When changing a rule, update all affected examples, schemas, diagnostics, and laws together. Do not revive superseded alternative runtime/syntax recommendations as if they were still decisions awaiting an implementer.

## 10. Research and projects tied to implementation

Primary sources are linked below. The proposed Blot applications are design interpretations, not evidence that the same performance or proof results transfer automatically.

### Core size and compilation work

| Primary source | Application to this handoff | Limit or tradeoff |
| --- | --- | --- |
| [The Essence of Compiling with Continuations][R1] (PLDI 1993; retrospective/reprint) and [Compiling without continuations][R2] (PLDI 2017) | Typed ANF exposes strict sequencing; explicit joins share branch continuations without arbitrary function allocation. See K1-CORE C03/C10. | An IR is not a compile-time complexity guarantee. Ownership, cleanup, evidence, and bounded traversal remain Blot obligations. |
| [Complete and Easy Bidirectional Typechecking for Higher-Rank Polymorphism][R3] (ICFP 2013) | Separate checking against complete interfaces from local synthesis. K1 deliberately starts with explicit rank-one boundaries. | The paper's calculus does not prove Blot's regions, effects, refinements, or usage rules sound. Do not import a larger inference problem simply because the reference supports one. |
| [Compositional Deep Argument Flattening][R4] (ML Family Workshop 2025) | A candidate for section 8's definition-derived representation summaries and separately reusable adapters. | Deferred beyond the uniform baseline ABI. Known fully applied functions and unknown callable values need different representation treatment; summary changes can invalidate executable dependents. |
| [rustc incremental queries][R5] and [Salsa][R6] | Track actual semantic reads, ordered dependencies, and unchanged-result cutoff. K1 separates interfaces, bodies, static values, layouts, and origins. See C11. | Incrementality helps edits. It cannot repair incomplete interfaces, invalid identity reuse, or expensive cold checking; admission and equality work also need bounds. |
| [Go 1.18 dictionaries and gcshape stenciling][R7] | A concrete comparison for dictionary-based code sharing and ABI adapters. K1 selects one bounded indirect baseline body, preserving semantic domain identities separately. | This is the versioned Go 1.18 design, not a claim about every current implementation. K1 does not copy its GC/runtime or require gcshape stenciling. |
| [Cranelift][R8], [ISLE][R9], and [VeriISLE][R10] | Explicitly typed local rewrite rules, pathological-input tests, and offline checking of individual transformations. See C09/C10/C12. | Replacing a backend does not remove frontend inference. VeriISLE is a partial verifier under development; its solver work need not be part of ordinary user compilation. |
| [CakeML][R11] | Separate source elaboration, core rewrites, lowering, and trusted-runtime preservation obligations. | A verified compiler is a methodological reference, not evidence that the proposed Blot compiler is already verified or fast. |

### Memory and functional abstractions

| Primary source | Application to this handoff | Limit or tradeoff |
| --- | --- | --- |
| [Stack-of-regions calculus][R12] (Tofte/Talpin, POPL 1994), [ReML][R13] (POPL 2024), and [MLKit][R14] | Specify region/effect contracts for higher-order code, lexical lifetimes, and destination placement. Start explicit and add measured local inference only where useful. | Modern MLKit also uses tracing GC. K1 adopts relevant reasoning techniques, not that full runtime or unrestricted region inference. |
| [Austral language specification][R15] | A reference for small structural ownership algorithms, explicit module interfaces, and resource consumption on exits. | Its safety boundary is not the same as proving every Blot array access and arithmetic precondition. Keep K1's required numeric evidence. |
| [Futhark][R16] (PLDI 2017) | A small array-combinator vocabulary and explicit consumption/uniqueness contracts can make individual fusion and in-place laws tractable. | Parallel algebra and global optimization add their own obligations and compiler cost. K1 first qualifies the direct destination loop. |
| [Fully in-Place Functional Programming][R17] (ICFP 2023 / extended report) and [Perceus][R18] (PLDI 2021) | Compare statically established resource behavior with dynamic reuse; study restricted functional fragments that need no allocation/deallocation. | FIP results concern its specific calculus. Perceus uses reference counting and is a comparison only; it is not a selected K1 reclamation mechanism or hidden extension. |

**Reading order for implementation:** ANF/join points and scoped-region material establish the representation and lifetime model; bidirectional checking defines the interface boundary; ISLE informs local rewrite laws; rustc/Salsa informs reuse. Flattening, Go representations, Futhark, and FIP support measured follow-up experiments. CakeML informs the preservation obligations throughout.

[R1]: https://www.cs.rice.edu/~javaplt/311/Readings/essence-retro.pdf
[R2]: https://www.microsoft.com/en-us/research/publication/compiling-without-continuations/
[R3]: https://research.cs.queensu.ca/home/jana/papers/bidir/
[R4]: https://elsman.com/mlkit/pdf/ml25-deep-flattening.pdf
[R5]: https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation.html
[R6]: https://salsa-rs.github.io/salsa/overview.html
[R7]: https://github.com/golang/proposal/blob/master/design/generics-implementation-dictionaries-go1.18.md
[R8]: https://cranelift.dev/
[R9]: https://www.cfallin.org/blog/2023/01-20/cranelift-isle/
[R10]: https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/isle/veri/README.md
[R11]: https://cakeml.org/
[R12]: https://melsman.github.io/mlkit/pdf/popl94.pdf
[R13]: https://elsman.com/mlkit/pdf/popl24-final.pdf
[R14]: https://elsman.com/mlkit/
[R15]: https://austral-lang.org/spec/spec.html
[R16]: https://futhark-lang.org/publications/pldi17.pdf
[R17]: https://www.microsoft.com/en-us/research/publication/fp2-fully-in-place-functional-programming/
[R18]: https://www.microsoft.com/en-us/research/publication/perceus-garbage-free-reference-counting-with-reuse-2/

