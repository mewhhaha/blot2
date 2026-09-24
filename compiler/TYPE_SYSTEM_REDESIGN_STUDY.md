# Type-system redesign study: a 100–200 ms gdev compile

Investigation on 2026-09-24 by three `gpt-6-sol` agents at `xhigh`, followed by
orchestrator review. Source checkpoints: Blot2 `827175d`, gdev `6c9221c`. The
target here means fresh source to Wasm for the full gdev application; ordinary
edits and unchanged-result hits are separate measurements.

## Recommendation

Prototype a compact, explicitly typed compiler core that retains the result of
generic checking. Keep Blot's nominal ADTs, inferred polymorphism, effect rows,
associated functions, closures and const-built ECS abstractions. For ordinary
generic code, infer one body per declaration or recursive group, retain its
deferred requirements, and instantiate those requirements at each use. Generate
specialized code from the checked body. Preserve a distinct staged path for code
whose structure or result type actually depends on compile-time values.

This is a substantive pipeline redesign. The experiments support its semantic
direction, but do not establish its full coverage or a 100–200 ms compilation
time. Adding annotations to the present pipeline did not avoid its repeated
work; those experiments are in
[the annotation report](TYPE_ANNOTATION_EXPERIMENT.md).

## What the target requires

The current application is 16 modules and roughly 56,000 source characters.
Recent native runs used about 2.6–2.9 seconds of compiler CPU. An earlier
instrumented run spent 2,780 of its 3,230 ms in initial checking,
specialization, and final checking/planning. The other coarse intervals were 122
ms decoding/lowering/template graph, 80 ms const evaluation, and 241 ms Wasm
preparation/output: **443 ms before frontend loading and startup**. These are
historical measurements under documented conditions, not timings of the new Bend
build or independent function self-times. [Phase data](COLD_COMPILE_RESULTS.md).

Deleting all the type-related work in that trace would still miss 200 ms.
Achieving the full target therefore requires compact source/IR transport, faster
lowering and emission, and a smaller startup/loading cost as well as the new
checker. The required total reduction is roughly an order of magnitude or more.
Neither the existing measurements nor these small prototypes prove that a full
rewrite will attain it.

## Experiments performed

| Experiment                           | Observation                                                                                                                                                                                                                                                                                       | What it establishes                                                                                                                                                                                                          |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Real gdev checked-body census        | 821 checked functions; `Type.eq` has 28 clones with one exact signature and 28 selected helper targets. `Array.get` has 25 clones with one signature and one direct-choice class.                                                                                                                 | There is repeated structure, but signatures alone do not identify interchangeable implementations. Different helper names alone do not prove different behavior.                                                             |
| Observable dispatch oracle           | Two revisions with the same `Left`/`Right` call types and `run: F32 -> F32` return 10 and 20 when the associated-member catalog changes.                                                                                                                                                          | Reuse needs the selected implementation and catalog dependencies, not only type arguments.                                                                                                                                   |
| Residual-scheme prototype            | An isolated handwritten TypeScript checker checks two generic bodies once and propagates a method requirement through a caller. Four uses create three variants and one hit; manually bumping a capture-dependency version creates a new variant. The Blot JS oracle confirms the changed output. | A small parametric fragment can retain and compose requirements. Dependency discovery and compiler cache invalidation are not implemented; effects, general captures and type-dependent branches are explicitly unsupported. |
| Exact interning over real signatures | On 492 gdev clone signatures and 9,408 chosen same-origin pairs, structural equality visits 178,830 values. Interning visits 43,506 values up front, then compares IDs. Both interner variants agree on all pairs.                                                                                | IDs can remove repeated traversal, but setup is significant: the tuple trie also performs 173,040 map lookups. This is a constructed comparison workload over real types, not a native compiler trace or speedup.            |

The interning experiment also found that serializing candidate keys allocates
1.30 MB of temporary text for this small workload. The useful experiment is to
construct types directly in compact tables and reuse their IDs throughout the
pipeline. A late interning pass over already-expanded trees could add cost.

Reproduction scripts, raw JSON and full agent reports are local ignored
investigation files:

- [Local census and representation experiments](../build/type-system-study/local/REPORT.md)
- [Research, semantic oracle and residual-scheme prototype](../build/type-system-study/research/TYPE_SYSTEM_ARCHITECTURE.md)
- [Go/Zig source study and alternatives](../build/type-system-study/go-zig/REPORT.md)

The probes used the existing generated JS compiler as a semantic oracle or
source of checked types. They did not measure a replacement native checker.

## Proposed type system and implementation

**1. Retain generic checking results and deferred requirements.** A scheme
should contain a typed body, quantified type/row variables, method and operation
requirements, coverage/reflection obligations, and precise dependencies. For
example, a generic `combine` can carry a schematic requirement
`Add(a, a, result)`; its caller must inherit that requirement even if the
caller's own source contains no `+` expression.

The implementation seam is concrete: `Mono.shape_bindings` currently retains
type schemes while dropping definition obligations. Later specialization and
final checking repeat work. Retain those obligations and their source origins,
then introduce typed expressions that carry the selected method/operation and
its checked types/effects. Final validation must consume this information rather
than rediscover it. A small core verifier remains useful, but its work must be
counted; replacing inference with equally expensive validation is not a win.

**2. Use compact IDs and local inference state.** Intern immutable solved type
shapes, nominal declarations and effect identities. Store unresolved inference
variables in a group-local union-find table with occurs checks, levels and row
constraints. Keep separate domains for mutable inference variables and frozen
type IDs. Instantiate a scheme with one consistent renaming of types, rows,
requirements and provenance. Preserve ordered/duplicate effect labels where
current row semantics require them.

Implement a bounded slice in Bend first. If compact data still spends most of
its time in term ownership, compare the same solver interface with an arena
kernel in native code. Measure both implementations, including conversion and
allocation costs. Switching implementation languages by itself is not evidence
of a speedup, and disabling reference counting in current generated C would
violate its consuming-match and storage-reuse contracts.

**3. Make compile-time staging explicit internally.** Const builder composition,
schema membership, nominal type equality, operation selection, provider
construction/scope and captured constants can determine concrete results. An
ordinary polymorphic body can be checked under residual assumptions; a branch
that changes the generated type or available code may need staged evaluation and
subsequent checking. The prototype rejects those cases rather than pretending to
certify them.

Keep that distinction in the compiler before considering new source syntax.
Record how much real gdev work falls back to staged checking. If most expensive
functions remain there, a parametric-only rewrite will not solve this workload.
In particular, cover `ecs.register_component`, `Entry.contains`,
`app.add_system` and a complete plugin composition, not only `identity` or
arithmetic.

**4. Freeze useful module interfaces.** Export inferred schemes, deferred
requirements, typed generic bodies, and exact dependency identities once.
Explicit public signatures may become useful contracts, especially across
recursive module boundaries, but adding annotations is not the optimization. The
benefit comes from using the interface as a checking boundary. Keep local
inference and pure-let generalization; avoid forcing users to spell the entire
const-built world type.

**5. Keep inference/search predictable.** Prefer local synthesis/checking with
expected types, equality unification, nominal member selection and row solving.
Retain bounded, deterministic dispatch and recursion rules. Avoid introducing
unrestricted implicit search, arbitrary type-level normalization during ordinary
unification, or unannotated polymorphic recursion as part of this performance
rewrite. Those features need their own costs and language decisions.

## What Go, Zig and type research contribute

Go's compiler publishes checked declarations and generic/inlinable bodies in an
indexed serialized representation that supports selective decoding. Blot can
borrow the reusable interface and typed-body boundary while retaining its own
deferred obligations. The older Go 1.18 dictionary/shape design also separates
generic checking from executable representation sharing; Blot must add exact
dispatch and capture evidence before sharing code.
[Current Go compiler architecture](https://go.dev/src/cmd/compile/README),
[Go 1.18 implementation design](https://go.googlesource.com/proposal/+/master/design/generics-implementation-dictionaries-go1.18.md).

Zig provides examples of compact untyped/typed IR, interned type/value
identities, and tracked dependencies. Its demand-driven comptime model
illustrates staging, but lazy validation of unused declarations would change
Blot's current rules. Zig 0.16's millisecond edit examples concern incremental
work; they are not evidence for a similarly fast full cold build. Borrow its
representation and dependency techniques without assuming its entire language
model or reported latencies transfer.
[Zig 0.16 release notes](https://ziglang.org/download/0.16.0/release-notes.html),
[ZIR](https://codeberg.org/ziglang/zig/raw/tag/0.16.0/lib/std/zig/Zir.zig),
[AIR](https://codeberg.org/ziglang/zig/raw/tag/0.16.0/src/Air.zig),
[InternPool](https://codeberg.org/ziglang/zig/raw/tag/0.16.0/src/InternPool.zig).

Qualified types and evidence-based elaboration provide the conceptual basis for
inferred method/effect requirements and a checked core. Bidirectional checking
gives annotations and expected types a useful local role without requiring
pervasive annotations.
[Qualified types](https://web.cecs.pdx.edu/~mpj/pubs/esop92.html),
[OutsideIn](https://simon.peytonjones.org/outsideinx/),
[Bidirectional typing](https://research.cs.queensu.ca/home/jana/papers/bidir/).

Koka's 2021 generalized evidence-passing work shows a principled translation of
typed effect handlers into a simpler typed calculus. The transferable idea is to
represent operations and their scoped provider evidence explicitly in the core.
The compile-time operation identity and the lexically scoped provider value are
distinct; the provider may be captured at runtime. Its runtime benchmarks do not
establish fast type checking, and Blot's scoped synchronous providers differ
from its full resumable handlers. The 2023 capability/region work is useful for
preserving lexical scope and preventing escaping capabilities during
elaboration, rather than as a compile-time speed claim.
[Xie/Leijen 2021](https://www.microsoft.com/en-us/research/wp-content/uploads/2021/08/genev-icfp21.pdf),
[Müller et al. 2023](https://pl.cs.uni-tuebingen.de/publications/mueller23lift/).

## Alternatives and the next decisive test

| Direction                                        | Benefit                                                                         | Cost for current Blot/gdev                                                                                       | Recommendation                                                                   |
| ------------------------------------------------ | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Modular explicit constrained generics, Go-style  | Clear checking boundaries; generic code checked against declared constraints    | Inferred member/effect APIs need explicit constraint interfaces; dependent builder details may become cumbersome | Borrow interfaces and typed bodies; prototype source restrictions only if needed |
| Demand-driven comptime specialization, Zig-style | Natural concrete specialization and precise edit dependencies                   | Repeated evaluation/checking can remain expensive; skipping invalid unused declarations changes semantics        | Use for genuinely staged fragments, not as the only checking architecture        |
| Qualified polymorphic core with staged fallback  | Preserves inferred abstractions while avoiding repeated ordinary body inference | Significant compiler work; success depends on certifying effects and transitive obligations                      | Preferred prototype                                                              |

The next implementation experiment should be a real vertical slice:

1. Retain source-group obligations and implement complete scheme instantiation.
   Start with `ecs.get/set` and nominal State operations to establish soundness.
2. Compose requirements through `Array.get` → `ecs.component_at`, then include a
   substantial effectful function such as `ecs.at` or `ecs.components` and one
   const-built plugin chain. Measure source-body checks, requirement solves,
   staged fallbacks, allocations and full wall/CPU costs.
3. Feed the checked result into final validation and Wasm emission. Compare
   exact artifacts where representation is unchanged, plus gdev behavior and
   diagnostics when code sharing changes the artifact.
4. Measure the output/frontend floor independently. Use true fresh compiles,
   ordinary body edits, interface edits, catalog/schema changes, failed edits
   followed by recovery, and increasing application sizes.

Preserve nominal identity, row scoping, pure-let generalization, constructor
witness behavior, coverage, reflection, validation of unused declarations,
deterministic diagnostics, and transactional cache publication. A cache key must
include exact source/interface versions, resolved selections and relevant const
dependencies; hashes can locate candidates but do not prove equality.

Stop expanding a candidate if it merely moves work into certificate validation,
falls back for most of gdev, or loses time to interning/key construction. A
useful first success is a measured reduction on the complete real dependency
chain with those correctness properties. Claim 100–200 ms only after the full
fresh source-to-Wasm benchmark actually meets it.

## Bend update and verification

Bend was updated from 2.0.24 to the current
[2.0.27 release](https://github.com/bendlang/bend/releases/tag/v2.0.27). The
native build guard now also accepts the verified 2.0.27 C emission. It
normalizes the new underscore-prefixed temporary names while retaining the
existing exact checks on comparison semantics, ownership and runtime helpers.
Unknown versions and altered ownership/equality still fail the guard. The native
compiler executable was rebuilt and installed in `generated/compiler/`.

Validation passed: `bend PROOF.bend`, constructor-ownership regressions with
one/four workers, all 670 compiler/transformer tests, and all 24 gdev tests. The
existing generated JS backend served as the reference for parity tests; it was
not rebuilt during this update.

Three alternating native pairs produced the identical 192,168-byte Wasm hash
`3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`. Median
compile-call wall was 2,015 ms for the saved 2.0.24 build and 1,975 ms for
2.0.27; native CPU medians were 1,960 and 1,930 ms. Individual results
overlapped, so this small sample does not establish a repeatable speedup. These
measurements used a different load window from the earlier annotation
experiments. Raw pairs, proof/test logs and the saved old executable are under
`build/type-system-study/toolchain/`.
