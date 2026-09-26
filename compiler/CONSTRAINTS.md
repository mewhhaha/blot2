# Inferred constraints, keyed specialization, and development compilation

Design synthesis for M3. This document describes the target implementation; the
current compiler does not yet implement it. Release remains the default until
the corresponding slices pass their gates. The three source reviews are
`design-qualified-types.md`, `design-incremental.md`, and
`design-runtime-first.md` in the compile-speed harness directory.

## Decisions

Keep Hindley–Milner inference and source-defined dispatch. Infer qualified
schemes at every generalization boundary; annotations remain optional. A scheme
contains a type, quantified type/row variables, and the predicates needed to
execute its body. Instantiation freshens all three together.

Release compilation selects evidence and emits one body per complete
instantiation key. Development compilation emits one body per qualified source
definition and passes evidence. Both strategies use the same selector, source
diagnostics, constant evaluator, entry roots, and host ABI. Development
compilation does not resolve overloads by searching at runtime.

An initial check still covers every declaration. `entry` reachability then
limits specialization, final checking, constant evaluation, initialization, and
emission. Declaration tags are ordinary applications after lowering.
Type/constructor layout metadata may remain available without emitting unused
constructor or operation functions.

Retain source-ready replay certificates and existing native caches where their
exact invariants still hold. A source certificate alone cannot justify an
arbitrary generated body. Remove the per-reference template expansion route when
the keyed collector replaces it; do not leave a public legacy mode.

## Predicates and annotation syntax

Use semantic predicates separate from source occurrence IDs:

| Predicate                   | Evidence                                                               |
| --------------------------- | ---------------------------------------------------------------------- |
| Associated binary selection | Selected implementation, instantiated signature, effects, and captures |
| Receiver method selection   | Receiver-owned implementation or bound method closure                  |
| Field read/update           | Selected field layout and getter/setter with its checked signature     |
| Generic operation family    | Concrete semantic operation identity and signature                     |
| Type representation         | Canonical structural type identity                                     |
| Effect reflection           | Instantiated latent row and its descriptor/set representation          |

Keep the existing left-before-right associated-selection rule, receiver-only
lookup, field/method ambiguity, argument evaluation order, and selected
implementation effects. `@type.same` compares the result type obtained by
`State.witness`, which strips function arrows from the witness; it does not
compare the witness value or blindly compare the full function type. Preserve
the existing admissible `state_specialize.type_key` domain for this source
operation: scalar, nominal, array, product, and closed function types. An
internal representation for provider or other types does not silently make them
valid `@type.same` operands; retain their current `ambiguous_state` diagnostic
until a separate language change explicitly expands that domain. `@effect.same`
compares two descriptors. `@effect.has` and `@effect.count` operate on reflected
sets. Checked rows retain multiplicity; reflected sets discard duplicates.

The explicit surface form is a `where` clause after a declaration's complete
type annotation and effect row, before `=`. It is contextual there, leaving
ordinary identifiers named `where` valid elsewhere. Initial implementation
supports top-level and local `let` binding annotations; qualified types are rank
one, so higher-rank parameter annotations are rejected explicitly.

```blot
const twice: a -> a where { associated "add" a a a } = fn x => x + x
const first: a -> b where { field "first" a b } = fn x => x.first
```

Predicate forms are `associated STRING T T T`, `receiver STRING T T T`,
`field STRING T T`, `update STRING T T T`, `operation qualified_name T...`,
`type_rep T`, and `effect_rep R`. Parenthesized types delimit non-atomic
arguments. A receiver predicate's three types are receiver, argument, and
result; a bound zero-argument method uses `Unit` as its argument. An update's
types are the old receiver, assigned value, and new receiver: updating a
`Box U32` field with `Bool` can produce `Box Bool`. Associated, receiver, and
update predicates may end with `! {labels | e}`, connecting the selected
implementation's invocation effects to an annotation row variable. An omitted
predicate row is inferred, not assumed pure. Internally every predicate retains
the full selected signature and effect-row relationships, including effects of
curried application; the surface shorthand cannot discard them. Predicates are
comma-separated, with optional newlines and a trailing comma. Variables in the
annotated type and predicates share one binding-local scope. An open row
annotation uses `! {OperationType, ... | e}`; `! {| e}` is an open empty prefix.
The tail variable is a row variable and cannot also be a type variable. Slice 1
retains the existing concrete operation-label representation: labels may be
closed generic instances, but a label with open type arguments such as `State a`
receives a clear diagnostic. Inferred generic effects continue to work. Symbolic
generic labels require type-bearing row terms, not encoded fake nominal IDs;
assess and implement that representation with slice 4's operation evidence and
effect-token work. This is a staged surface-syntax limitation, not permission to
discard or conflate generic effects.

An omitted clause infers obligations. An explicit clause supplies dictionary
assumptions while checking the body: the declared context must entail the body's
inferred obligations after the shared substitution. Callers must satisfy every
declared predicate. Extra predicates deliberately restrict the annotated API and
remain in its interface; canonicalization removes only duplicate equivalent
predicates. The clause cannot supply an unchecked implementation or fabricate
evidence. An annotation applies to the final value after tags. A closed entry
must satisfy its obligations and the guest ABI. Unsolved predicates preserve the
existing missing/ambiguous dispatch diagnostics where the source form already
existed; malformed clauses have dedicated source diagnostics at the clause. An
explicit `field` predicate does not disambiguate a field and a method with the
same name. Selection retains the existing `ambiguous_member` rule, even if the
explicit predicate is otherwise unused by the body.

## Inference and checked representation

`infer.Binding` currently carries only a type and quantifiers. Add predicates to
the binding scheme and to `SchemeInstance`; carry source occurrence information
in a separate elaboration record. Reuse `AssociatedNeed` and `OperationNeed` as
inputs, while keeping pattern coverage and return-flow information separate.
`Reflection` needs the referenced function's instantiated scheme, rather than
only its name. For the existing `@effect.of name` query, reflection reads the
named function's checked signature row and does not execute or create a
callable. It records the instantiated predicates for future generic reflection
work, but does not make them obligations of the query itself. Initial checking
still rejects an open reflected row, and constant evaluation reads the same
closed checked row; this preserves old-source reflection behavior without
bypassing selection for an actual call.

Use one substitution/renaming across a scheme's type, row, and predicates.
Generalize all residual predicate variables together with the type variables,
excluding environment free variables, annotation variables that are fixed,
ambient row variables, and SCC-shared monomorphic variables. Preserve the
current distinction between generalized pure `let` and monomorphic `use`. Do not
add a stricter ambiguity restriction that rejects existing generic programs
merely because a selected implementation later determines a result type. At a
use site, selection may improve the result type and effect row.

For a computed pure `let` RHS, predicate-dependent variables stay monomorphic
within that let. The RHS is evaluated once and its original use plans are
constrained by later uses. Direct named, constructor, operation, and lambda
templates can still be cloned and generalized at each concrete use. Thus a
conditional qualified callable works at one concrete type, while using that same
computed value at incompatible types keeps the existing `type_mismatch`. The
later first-class evidence representation can lift this restriction without
duplicating RHS evaluation.

Solve closed predicates using the existing selectors. Revisit obligations when
unification makes their determining operands concrete. Publish residual
obligations in the SCC interface; never publish a bare type that silently
forgets dispatch. `groups.Interface`, interface equality, imported schemes,
checked-core comparisons, and source-shape retention all include predicates.
Retained groups that omit unresolved needs cannot be used as resolving
certificates unless those needs are reconstructed.

Record every callable-value expression's instantiation and evidence-slot
mapping: named functions, constants holding function aliases or const closures,
constructor references, bound receiver methods, and direct/indirect calls.
Evidence must attach when a callable value is created, not only when called. The
present untyped `M.Expr` and top-level `M.Signature` are insufficient to recover
this information afterward. Each occurrence retains its original subject for
diagnostics, while scheme identity excludes source offsets. Equal semantic
predicates may share an evidence slot; every source occurrence still maps to
that slot and retains its error location.

Slice 1 keeps value patterns with closed requirements working: their source
definition's ordinary selection still checks the concrete requirement. A value
pattern referring to a genuinely open qualified scheme receives
`qualified_pattern` at the pattern source location. Pattern references do not
currently have a lowered instantiation site or a `PatternTyping` evidence plan,
so silently accepting an open scheme would discard a caller obligation. Slice 4
must assign stable pattern-reference sites, carry instantiated predicates and
their subjects through `PatternTyping` into the checked group, and select or
pass the evidence before the pattern comparison. Include old-source concrete
value-pattern parity and open qualified pattern success in that slice's gates.

Implement predicate traversal in a focused constraints module where possible.
Changes to guarded type traversals in `types.bend` or `model.bend` require
updating the corresponding native generated-C transformations and their negative
shape tests; do not bypass those guards.

## Release collector

After initial checking and entry pruning, process a deterministic worklist of
requested instantiations. Resolve predicates, canonicalize the complete key,
reserve an `InProgress` identity before descending, and reuse it for recursive
or repeated requests. Check and emit a new body once. Recursive growth in
distinct keys has an explicit specialization limit; it never silently merges
different instantiations.

Complete evidence includes concrete material choices inside a body even when
they do not appear in its exported predicates. Prepare those choices without
emitting code or descending into child bodies before reserving the key. Keep
interface predicate answers and ordered body evidence in separate key fields;
body evidence uses a deterministic ordinal within the exact source revision, not
a diagnostic offset. Retain the prepared body for materialization so a cold
request is inferred once. A preliminary request is not a complete cache key, and
later replay validation cannot repair an incomplete reserved identity.

The key contains:

1. Origin module/declaration identity and source/qualified-scheme revision.
2. Closed type arguments and canonical effect rows. Normalize row ordering in
   the same way as existing row equality, preserving multiplicity.
3. Selected evidence identities, instantiated signatures, layout versions, and
   source/interface dependencies that justify those choices.
4. Staged or captured constant dependencies incorporated into generated code.
   Ordinary runtime captures remain closure fields, not runtime-address keys.
5. Key format/compiler version and compilation strategy.

Use unambiguous structural encodings and exact equality after any hash lookup.
The coarse `(origin, parameter, result, row)` counts from M2 are measurements,
not safe cache keys. Offset, call path, worker number, and discovery counter are
not semantic key components. Names/publication order derive from sorted keys or
collision-checked key encodings.

Parallel workers may check independent reserved instances. Merge results in
canonical order; shared keys have one owner and one emitted body. Preserve the
existing evaluation-order temporaries when rewriting associated calls. Keep
final checking for generated release bodies. Migrate `staging_scheme` and
`schema_stage` to general scheme replay only once their current guarded cases
have equivalent tests; an optimized special case is not a second language
semantics.

## Development runtime

Use the runtime-first proposal's uniform private development call convention:
`(closure, argument, provider_chain, evidence) -> value`, all i32 lanes. Release
retains its current three-lane private convention. Public exports and the guest
ABI manifest remain unchanged; entry wrappers provide closed evidence
internally.

Development closures are `[table_index, evidence_pointer, captures...]`.
Evidence tuples are immutable and have statically checked slot kinds. A direct
call supplies the callee's tuple; an indirect call loads its tuple from the
closure header. Forward an existing tuple when its layout matches; otherwise
construct a mapped tuple. Audit direct/indirect calls, exported wrappers, array
callbacks, handlers, operation closures, constructors, initializers, local
numbering, static serialization, and captured-variable offsets together.

Evidence chooses an implementation or operation identity. It does not capture a
provider chain. An escaped closure retains its selection evidence while using
the caller's current providers. A selected handler implementation runs under the
outer chain, preserving the current scope rule.

Collect reachable closed evidence environments without cloning source bodies.
Within one artifact, intern structurally distinct types and operations to dense
IDs; preserve semantic structural identities in all compiler/session keys.
Provider construction, invocation, descriptors, reflected sets, and serialized
constants use the same operation-ID assignment. Code caches keep relocations,
not final numeric IDs. Type equality compares interned IDs whose injectivity was
established by structural comparison. Reflected sets use sorted unique operation
IDs; count reads their length, has checks membership, and descriptor equality
compares operation IDs.

The finite catalog is an implementation obligation, not an assumption that
permits missing instances: collect all evidence reachable through higher-order
calls and const-generated closures. If inference cannot establish an evidence
environment, report the corresponding source ambiguity. Catalog/arena limits
produce diagnostics before overflow. No evidence pointer is a persistent host
handle or survives a reload.

## Constant evaluation, APIs, and caches

The constant evaluator executes elaborated evidence using structural values:
selected functions, operation identities, type representations, and effect sets.
Constant closures retain evidence and ordinary captures separately. Resolve
artifact-local IDs only during serialization. The gdev app builder still
executes at compile time in both strategies, with the same effects and budget
contract. Development mode cannot skip constant evaluation.

Add `mode?: "release" | "dev"` to compile options and propagate through the
reference compiler, native stateless compiler, incremental/project compilers,
workers, request protocol, and native session. Bump the protocol version; reject
unknown modes. This is separate from the existing Analyze/Compile request enum.
`analysis:false` stays orthogonal and returns identical bytes to full analysis
within the selected mode.

Source parsing/lowering caches remain shareable. Qualified interfaces,
specialization, const values, and generated jobs include the strategy and
relevant scheme/evidence/capture identities. Validate exact dependencies on a
positive hit. Publish session state only after success; a failed edit does not
install half-selected evidence. Mode changes in a warm session must match cold
compilation. Never persist runtime arena pointers or artifact-local operation
indices in source or const keys.

Only omit development final re-inference when the checked evidence elaboration
establishes the same invariant as the existing checker. Keep the check until
that is implemented and tested. Array-reuse optimization may be skipped in
development mode once aliasing/bounds parity passes and measurements show a
benefit. Skipping either check or optimization is not a substitute for evidence
passing.

## Five implementation slices

| Slice                                            | Landable result and acceptance                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Qualified schemes and source syntax           | Infer, generalize, instantiate, compare, and cache predicates; parse and check explicit clauses/open rows; retain per-use evidence plans. Adapt the existing elaborator to consume these plans. Inferred/explicit equivalence, local-let/SCC/row tests, unchanged old-source diagnostics and all gates. Report gdev scheme counts and paired CPU; no unexplained regression above 5%.                                             |
| 2. Keyed release specialization                  | Replace per-reference cloning with the complete-key collector and integrate exact session keys. One generated body per complete key, zero duplicate keys, deterministic bytes across worker counts, captured/evidence changes invalidate safely. Full gates and behavior parity; paired gdev CPU no worse than the previous milestone. Record the actual key histogram rather than imposing the unsafe 199-signature lower bound. |
| 3. Development call ABI and member/type evidence | Internal development strategy implements the four-argument ABI, closure evidence, associated/receiver/field dispatch, TypeRep, and structural const evidence. Release remains default. Audit every private call path; focused polymorphism, closure, witness-side-effect, const-tag, and ABI tests pass. No public claim of complete dev support yet.                                                                             |
| 4. Complete development effects/reflection/API   | Shared operation tokens, dynamic provider/invocation evidence, symbolic generic row-label representation, qualified value-pattern evidence, live reflection and const serialization, public mode option, and cache partitioning. All std/examples/gdev behavior and source diagnostics match release; warm mode flips equal cold compiles; analysis/bytes-only outputs agree.                                                     |
| 5. gdev adoption and final measurements          | Only this slice changes gdev runtime options to dev for startup/reload. Measure paired baseline/release/dev CPU and wall at 1/4 threads (at least five runs), clone/key counts, Wasm size, cold/warm edits, and runtime behavior/cost. Keep the switch only after dev improves the intended compile path and parity passes. Write COMPILE_SPEED_RESULTS.md and link it from the compiler README. Never commit gdev.               |

Every slice includes laws with checked proofs, meaningful regression tests, the
proof/build/test/parity gates, review of generated artifacts and cache
boundaries, and a local compiler-repository commit. No pushes. Initial M2
timings are historical evidence, not forecasts: the old 63% specialization share
predates M2's reductions.

## Required invariants and regression matrix

Prove tractable laws for shared scheme renaming, predicate ownership, canonical
structural keys, different evidence/capture keys, deterministic lookup, and
operation/type ID injectivity. Test the full observational claims; do not
describe release/dev equivalence as formally proved without a model.

The regression matrix includes U32/F32 local polymorphism; mutually dependent
groups; left/right dispatch; field/method clashes; evidence-dependent effects;
partial/escaped closures; nested and shadowed State families; first-class
operations and providers; equal/different nominal witnesses with observable
witness evaluation; descriptor versus set reflection; recursive demand keys;
same signatures with different captures; declaration tags; unused panicking
constants/runtime initializers; source errors in unused declarations; warm
failed edits/rollback; mode flips; relocatable code caches; and deterministic
Wasm across thread counts. Existing frozen parity workloads remain unchanged on
the baseline side.
