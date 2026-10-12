# Associated types and implementation declarations

This is the task 054 contract for tasks 055–056. The executable language remains
the [guide](../compiler/guide.md#qualified-bindings); this document specifies
new syntax. It extends [module abstraction](MODULE_ABSTRACTION.md) and the
existing [ownership contract](CONTRACT.md). It does not change ordinary
operator, receiver, field or result-selected dispatch.

## Declarations and names

Contract bodies retain their comma-separated predicates and contract inclusions.
They may additionally declare these members:

```blot
type Identity a is contract = { type Item = a }
type Source s is contract = {
  type Item,
  const first: s -> (Source.Item s),
}
```

`type Item = T` is a defined type member: a checked equation, not an overridable
default. `type Item` is an abstract type member. Both have kind Type and take no
additional member arguments. `const first: T` is an abstract value member with a
complete function annotation and no initializer. Members share one local name
space; duplicates, a value/type name collision and undeclared names are errors.
Contracts with abstract types or value members require explicit implementations.
Contracts containing only defined members and existing predicates remain erased
structural bundles. They accept no implementation declarations.

Contract parameters use the existing named, shaped and explicitly curried
parameter syntax. Their binders scope over the whole body, including forward
references to members. Member equations and signatures introduce no additional
type or effect-row binders. A complete function type passed as a parameter may
carry arbitrary latent rows: `type Callable f is contract = { type Run = f }`.
An equation cannot silently introduce a fresh row, such as
`type Run = Unit -> a ! {| e}` with unbound `e`. Method invocation rows are
closed or already bound in the public parameter shape; omitted invocation rows
are pure. Method-local polymorphism, associated row members, parameterized
associated members and default methods are outside this initial syntax.

`Source.Item s` is a type projection. The contract application must be fully
applied, with exactly its declared argument shapes. For a curried contract, use
the same explicit parentheses as an ordinary type application. A
module-qualified projection is `lib.Source.Item s`; aliases and forwarding
retain the original contract and member identity. Resolve the contract path
first, then its declared member. A lexically bound type parameter is never
interpreted as a namespace. Projections do not create type-constructor values or
permit runtime type computation. `Identity.Item U32` normalizes to U32 without a
runtime value.

Forming a projection retains its contract requirement; normalization discharges
that requirement from a given scheme, structural predicates or a selected
implementation. Merely knowing an equation does not grant unrelated methods or
discard its prerequisites. Generic aliases can retain the projection recipe;
each expansion propagates the requirement to the using scheme. Data/opaque
payloads and other declarations without qualified schemes must discharge their
projection requirements when checked. A remaining generic requirement there is
an error; pass an explicit output type parameter instead. No hidden evidence
requirement is dropped from a constructor or storage contract.

`Source.first` is a polymorphic function template qualified by `Source s`.
Ordinary application determines the contract parameters from the instantiated
signature. It can be captured or passed as a callback under the existing
specialization rules. Unconstrained contract parameters remain qualified
requirements; a concrete executable use cannot guess them from an associated
output. There is no runtime dictionary. A declared contract member reserves its
qualified name; an ordinary binding of that same qualified name is a duplicate.
Existing bindings under contracts without such a member retain their meaning.

Neither member syntax nor an implementation registers a legacy nominal
associated function. In particular, `Source.first value` does not add
`value.first`, change `@type.call`, or replace a prelude operator. Legacy
predicates inside a contract still use their current dispatch rules.

## Implementations

An implementation has an explicit declaration name and explicit parameters:

```blot
impl ArraySource a : Source (Array a) = {
  type Item = a,
  const first = fn values => @array.get values 0,
}

const read: s -> (Source.Item s) where { Source s } =
  fn values => Source.first values
entry const answer = fn () => read #[42]
```

`impl` is contextual at a declaration start. Its grammar is
`impl Name
parameters : ContractApplication [where { predicates }] = { members }`.
Parameters use existing declaration parameter forms; there are no implicitly
bound head variables. The head has exactly the contract's argument shapes.
Type/row variables quantified by an implementation must be determined by its
head. Requirements cannot introduce existential binders or determine an
otherwise absent parameter through a selected output. Transparent aliases expand
before matching; opaque arguments remain nominal.

The body must define every abstract member exactly once and no other members. It
cannot override a defined member. Type equations may use head parameters,
provided prerequisites and the implementation's other type members. Value
members use ordinary lambda syntax and inference; an optional annotation must
agree with the instantiated contract signature. Forward an existing function
with a lambda rather than a method initializer expression. Check all equations,
signatures, ordinary predicates and bodies, including unused members, before
publication. After type equations are checked, method bodies may call one
another or recurse using their fixed signatures. Such function recursion does
not justify circular type equations or circular evidence prerequisites.

An implementation adds no initializer, effect, provider or guest export. Method
bodies execute only when called, with ordinary argument evaluation, effect,
failure, fuel, capture and ownership behavior. `entry impl` and `opaque impl`
are invalid modifiers. `private impl` is permitted. Evidence selection and
normalization never evaluate a method or force its captures. Creating a selected
method callback materializes captures using the ordinary named-function rules at
that expression's source position.

## Scope and coherence

An implementation may be declared in the original contract producer or in the
producer of its anchor nominal. The anchor is the first type binder of the
contract's public parameter pattern, in written depth-first order; substitute
the head and take that argument's outer nominal constructor. Transparent aliases
do not change ownership. Primitives, arrays, lists, cursors, functions,
products, records, a variable head and a zero-parameter contract have no user
nominal owner, so only the contract producer may implement those heads. A
nominal nested inside an Array does not own the Array head. This rule is checked
independently of import aliases and prevents third-party implementations for
foreign pairs.

Implementation heads are finite first-order ordinary type/row patterns. They
cannot contain associated projections, runtime values or evidence-dependent type
computations. Existing occurs checks and type/effect equality apply.
Requirements are not used to prove heads disjoint: two heads that have any
common type/row instantiation overlap, even if their requirements differ or one
fails. Reject overlap before publication. A generic implementation and a
concrete specialization therefore cannot coexist. There is no priority,
source-order selection, right-hand fallback, negative instance or overlapping
specialization. An exhausted disjointness proof is an error, never permission to
admit a pair.

For a resolving module, the candidate set contains public implementations from
the acquired transitive module graph plus that module's own private
implementations. Importing an implementation name is not required; importing a
contract/type does not discover files outside that graph. Named/namespace
imports and selective forwarding cannot reorder or duplicate a candidate.
Forwarding preserves the original implementation producer and declaration name.
Public coherence is checked across the whole acquired graph; each module's
private implementations are also checked against the public set and its own
private set. Private implementations from another module never participate in
selection or diagnostics. A dependency archive advertises the same public set as
its source producer, and admission repeats the same coherence checks.

Selection first uses a matching logical requirement already supplied by the
enclosing qualified scheme. This is a deferred proof, not a competing local
instance or runtime dictionary. Once the application is sufficiently known,
instantiate heads with fresh variables and select the unique matching candidate.
Then discharge that candidate's prerequisites, validate its associated equations
and methods, and retain the complete selected evidence. A matching head whose
prerequisites fail is incompatible; do not try a different implementation.
Unknown arguments can stay residual inside a principal scheme. No backend
layout, emitted call or selected portable receipt may consume residual evidence.

Requirements on a public generic function are selected in its caller's evidence
context. A concrete use inside a defining body keeps that body's lexical context
and may select its private implementation. The latter is a private executable
dependency, like a private helper, and cannot become a caller-visible witness or
projection equation.

## Equality, normalization and effects

The new predicate `type_eq T U` asserts ordinary semantic type equality,
including nominal identity and function effect rows. It introduces no runtime
equality test, coercion or representation equality. In a given scheme it is a
logical equation; at a concrete use it must be discharged. Legacy named bundles
may include it without becoming nominal implementation-requiring contracts.

```blot
const keep: a -> a where { Identity a, type_eq (Identity.Item a) a } =
  fn value => value
```

One contract/member identity and equal argument graphs denote equal projections
under the same evidence context. Defined members normalize by substitution.
Abstract members normalize only from the matching given equation or complete
selected implementation. Ordinary variables may unify as usual; the checker must
not invert `Source.Item s = U32` to invent `s` or choose an implementation.
Different contracts' `Item` members are distinct, and different applications do
not become equal merely because their storage matches. Nested projections
normalize from their innermost available proof outward; stuck terms retain their
requirements instead of guessing Unit, U32, F32 or a pointer.

A contract's defined member may refer to another member or to a projection whose
contract requirement is included in the body. The member dependency graph must
be acyclic after ordinary alias expansion. Reject direct, mutual and growing
projection cycles. Nominal recursive data inside a finite result remains legal.
Abstract type equations of an implementation obey the same rule. Evidence
prerequisites may recurse on smaller concrete heads; repeating the same
contract/application proof on the active path is an unfounded cycle. A growing
chain is bounded by the same depth/work limits, not a recursive fixed point.

Types and rows are substituted together. Every scheme use freshly instantiates
its quantified row identities; callback input/result rows and associated output
rows keep their exact known labels and tails. The evidence key includes those
rows. Projection normalization performs no invocation, handler installation or
effect subtraction. A pure method can satisfy a larger declared ambient using
the existing function compatibility rule; a Foreign method cannot satisfy a pure
signature. Selecting one method never unions the effects of unused methods into
a call. Old `associated`, `receiver` and result dispatch keep their current
left-before-right, receiver-only and selected-result behavior.

## Module boundaries and identity

Contracts, members and implementations use portable identities consisting of the
canonical original producer path, declaration kind, original declaration name
and, for a member, its original member name. Numeric unit/table handles are
relocated views. Renaming a forwarding alias or inserting an unrelated private
declaration does not create a different identity; conservative rechecking is
permitted. Changing an original name/path does. Alpha-renamed binders are
compared in declaration order with their type/row kinds and public parameter
shapes. Different definitions claiming one portable identity are never merged by
name.

Members inherit their contract's visibility; there are no individually private
members of a public contract. A public contract signature, defined equation,
public implementation head/prerequisite/output or published method scheme cannot
contain a private nominal, effect, contract or implementation identity. Public
opaque outputs are legal and remain abstract. An implementation in an opaque
type's producer may unpack that type; a contract producer elsewhere cannot use
its ABI recipe as semantic field/type evidence. Alias and forwarding rules
preserve these restrictions.

A private implementation can service concrete uses in its producer's executable
body. It cannot justify a concrete projection exported in a public signature or
public evidence record. Public method bodies may use private helpers while their
checked schemes and public associated equations remain usable independently. The
private Core owner remains available for legitimate specialization, and artifact
import cannot promote its private implementation/member catalog.

## Owned evidence and portable schemas

Keep public declarations as owned flat tables: contract parameters and member
descriptors, defined equations, method schemes, implementation heads,
prerequisite spans, associated equations and method targets. Projection type
nodes name an owned contract/member handle and an owned argument span. Public
snapshots copy only public roots; private records have inaccessible tombstones
or a separate executable section. No AST pointer, solver variable/index, scratch
slice, mutable substitution cursor or optional-cache answer becomes a public
member definition, implementation witness or Core field.

Principal evidence contains symbolic projections, quantified type/row binders
and residual obligations. Selected evidence is a complete owned DAG with the
implementation identity, instantiated arguments/rows, associated results,
selected method targets and prerequisite proof ordinals. Its graphs share owned
nodes; they do not recursively duplicate prerequisite trees. Proof edges cannot
refer to a future, missing or foreign owner. Captures and layouts still follow
their ordinary physical ownership rules; erasing evidence introduces no managed
cell or dictionary.

Required read sets include the exact contract/member interface, candidate-set
and coherence certificate, selected implementation head/requirements/equations,
every normalized projection/prerequisite and each consumed method body/capture
and its transitive dependencies. Adding a reachable implementation must recheck
coherence even when the former winner is unchanged. Type-equation edits
invalidate normalization/layout consumers; selected body edits invalidate
executable consumers even if the public equation and signature stay equal.
Diagnostic provenance is owned separately and is not part of semantic keys.
Unknown, incomplete, scope-mismatched or exhausted optional proofs decline reuse
and take ordinary checking; a required proof failure remains authoritative.

Task 055 adds projection/member/type-equality tables with dependency wire
version 3 and new settings/schema interpretation versions. Task 056 adds
implementation and selected-proof tables with wire version 4 and another
interpretation bump. Backend checkpoints version those tables too; compiler
fingerprints include all new source and interpretations. Unknown versions
rebuild from source or reject a source-less required dependency under existing
admission rules. Decode into private owners, validate all kinds, ordinals,
binder scopes, type/row graphs, member completeness, original producers,
privacy, coherence and proof cycles, then relocate and publish. Re-encoding is
deterministic in source table order; candidate diagnostics use canonical origin
order, never hash iteration order.

Source and compiled projects must select the same original implementation and
normalize to equal graphs. A failed edit, malformed artifact, exceeded limit or
OOM releases the entire candidate and preserves last-good source owners, query
tables, evidence, revision stamp and executable output. Publication remains
allocation-free. Optional index allocation failure may take a bounded scan;
failure to allocate required evidence cannot be hidden as a successful witness.

## Bounds and diagnostics

New normalization/evidence/coherence work shares at most 1,000,000 charged steps
per checked project operation, inside the existing inference budget. Charge each
candidate/pair, graph node, row label and prerequisite edge before traversing
it. Maximum active normalization/prerequisite depth is 256; maximum
implementation records in an acquired graph is 4,096. Memoized exact subproblems
may share work; they never reset the budget or conceal an active cycle.
Candidate indexing is optional, and disjointness pair enumeration itself spends
the shared budget. Legacy programs without new declarations/projections take
their ordinary path.

Required failures have these stable native/client diagnostic codes:

| Code                                         | Trigger                                                         |
| -------------------------------------------- | --------------------------------------------------------------- |
| `missing_type_member`                        | Undeclared member or absent abstract equation                   |
| `associated_arity`                           | Wrong contract application shape or unsaturated projection      |
| `undetermined_implementation`                | Head does not determine a quantified type/row parameter         |
| `orphan_implementation`                      | Neither original contract nor anchor nominal is owned           |
| `overlapping_implementation`                 | Two visible heads have a common instantiation                   |
| `missing_implementation`                     | Known required application has no matching head                 |
| `incompatible_implementation`                | Matching head fails prerequisites/equations/method checks       |
| `ambiguous_qualified`                        | Executable use retains unconstrained evidence/arguments         |
| `recursive_associated_type`                  | Defined/selected projection equation cycle                      |
| `recursive_evidence`                         | Repeated active prerequisite application                        |
| `associated_limit`                           | New evidence/normalization/coherence work or depth is exhausted |
| existing privacy/type/effect/duplicate codes | Ordinary corresponding failure                                  |

An abstract type lacking an implementation produces `missing_implementation`; an
implementation lacking its required equation produces `missing_type_member`.
Rejection of overlapping declarations is primary at the later declaration in
canonical producer/source order, with the earlier origin related. Required-use
errors are primary at the requesting use. Explanations retain at most four
candidate origins, eight prerequisite/member steps, 256 bytes per type spelling
and 2,048 explanation bytes, with explicit truncation. Report `head_mismatch`,
`requires_evidence`, `incompatible_type`, `incompatible_effect`, `selected`,
`overlap` or `limit` from already checked facts; rendering never runs a second
inference/selection pass. Private candidates outside the requesting scope appear
as absence, without hidden names or payloads. Source-less related origins use
owned archive provenance; absent source spans stay absent. Truncation does not
change candidate selection or the primary code.

## Accepted and rejected laws

These are acceptance requirements, not claims about the incoming compiler:

| Case                                                                              | Required result                                                             |
| --------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `Identity.Item U32`, generic `Callable.Run f`, imported/forwarded defined member  | Ordinary type/row substitution; no runtime witness                          |
| `Source.first #[42]` with ArraySource above                                       | 42; one selected implementation; ordinary array access behavior             |
| Two contracts each declare `Item`                                                 | Qualified projections remain distinct until separately proved equal         |
| Nested `Outer.Item (Inner.Item s)` with complete proofs                           | Normalize inner then outer; retain both dependencies                        |
| Abstract projection in a given `where { Source s }`                               | Residual principal evidence is legal; ground execution requires a witness   |
| `type_eq (Source.Item s) U32` with unknown `s`                                    | Retain equation; never invent an input or pick an instance from U32         |
| `impl All a : Source a` plus ArraySource                                          | Overlap error regardless of requirements or declaration/import order        |
| Duplicate alias/forwarding of one implementation                                  | One original candidate; no false ambiguity                                  |
| Foreign contract and foreign nominal implemented by a third module                | Orphan error                                                                |
| Source contract implemented by the producer of a public opaque Token              | Legal without exposing Token's representation                               |
| Public equation/prerequisite contains a private identity                          | Privacy escape error                                                        |
| Private implementation used by an exported concrete helper returning U32          | Legal private executable dependency; no public witness                      |
| Public signature depends on that private implementation's concrete Item           | Privacy escape error                                                        |
| Pure method under a declared Foreign ambient; Foreign method under pure signature | First legal; second effect error; call traces retain source order           |
| Free row/type name, extra member, missing equation, equation override             | Reject declaration, including unused bodies                                 |
| `type Item = (Loop.Item a)` or mutual/growing projection recursion                | Cycle or associated-limit error; no guessed recursive type                  |
| Descending prerequisite chain versus repeated/growing chain                       | Complete finite proof versus recursive-evidence/limit error                 |
| Opaque Item changed from scalar to reference with same public identity            | Invalidate layouts/ownership; preserve roots and fresh/retained parity      |
| Selected method changes with stable public types                                  | Invalidate executable reads; diagnostics and output match fresh compilation |
| Archive/checkpoint forged member, witness, producer or private promotion          | Reject before publication; source rebuild where available                   |
| Allocation failure during any public/evidence owner preparation                   | Release partial owners; last-good unchanged; retry succeeds                 |

Task 055 qualifies defined members, symbolic abstract projections, equality,
imports, row/type substitution, normalized layout preparation and portable
member tables. Its concrete execution laws can use defined members. Task 056
qualifies implementation declarations, method templates, global coherence,
selected proofs and concrete abstract-member execution. The final combined gate
exercises both; neither stage may turn unavailable implementation support into
an assumed proof.

Measure fresh compilation, retained edits and checkpoint restart separately.
Record normalization visits/hits, residual projections, candidates, overlap
pairs, prerequisite edges, maximum depth and proof bytes beside requested/peak
allocations. Include no-feature controls, long nested projection DAGs, disjoint
heads and generic prerequisite chains. DAG growth must track distinct nodes and
proof edges, not expanded paths; exhausted runs must stop at their stated
charge. Use executed-Wasm scalar/reference/callback and sync/JSPI paths,
source/compiled imports, stable-type selected-body/type-equation edits, failed
revisions and deterministic OOM sweeps. Compare output/diagnostics against fresh
compilation. The handwritten parser, `grammar.baba`, contextual-marker
preparation, Deno formatter and Tree-sitter/editor inputs must agree on each new
syntax form. Regenerate outputs from their inputs; never patch generated tables.
Formatting must preserve declaration kinds, method/projection binding and
evaluation order, including forms nested in ordinary imports, lambdas and
annotations. Preserve no-feature Wasm and dispatch traces; report any
inference/allocation cost instead of claiming completion from unexercised tests.
The language-evolution cold/retained targets remain unchanged.

## Specification qualification

This documentation adds no compiler behavior or benchmark claim. Examples use
existing parameter, type, row, privacy and dispatch rules with the new syntax
specified here. The draft passed `deno fmt --no-config --check` on its three
Markdown files and 32 local link/anchor checks. No compiler code or executable
fixture changed for this specification, so there is no compiler/performance
measurement claim. Tasks 055–056 own the executable, portable, allocation and
performance gates; the parent owns combined compiler/analyzer qualification and
milestone records.

Task 054 is complete at local revision `f184dde`, integrated with task 052's
qualified privacy/opaque boundary. The joint
[qualification record](MODULE_ABSTRACTION_QUALIFICATION.md#integrated-qualification--12-october-2026)
records that compiler batch. This specification still implements no associated
member, projection or implementation declaration; tasks 055–056 own those
remaining laws and costs.
