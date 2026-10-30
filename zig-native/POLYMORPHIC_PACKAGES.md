# Annotated polymorphism and existential packages

Normative design for 063–065. Proposed forms do not extend the current
[executable guide](../compiler/guide.md) until qualified. Ordinary inferred
schemes remain unchanged. [Usage contracts](USAGE_CONTRACTS.md) and
[scoped effect identities](SCOPED_EFFECTS.md) apply inside every abstraction.

## Explicit binders and checking

`forall [a, row e, region r] where { Predicates } => T` binds named type,
effect-row and region variables in T and its predicates. `where` is optional.
Binders are simple distinct names; higher-kinded binders, impredicative
instantiation and unrestricted higher-rank inference are rejected. A type binder
ranges over unrestricted value representations; affine ownership or loans appear
explicitly as `unique a`, `once (...)` or `borrow r a`, never hidden in an
unrestricted binder. A row binder preserves operation identities and capability
footprints.

A forall may occur in explicitly annotated arguments, results and record fields.
Introduction checks a lambda or existing principal against fresh rigid skolems
for every binder, under exactly the written evidence. Elimination instantiates
the binders freshly at an annotated use. Ordinary unification cannot assign a
skolem, merge independent scopes or generalize it as an inference variable.
Contravariant inputs, covariant results and latent rows are checked
structurally; rank comparison alpha-renames matching binder sorts. Polymorphic
recursion needs an explicit principal. No arbitrary forall is guessed for an
unannotated value.

```blot
// Proposed: the callback must be valid independently for every a.
const two: (forall [a] => a -> a) -> (U32, F32) = func identity => return
  (identity 42, identity 3.0)
const id: forall [a] => a -> a = func value => return value
entry const answer = two id
```

Accept the same annotation through an imported producer. Reject passing a
U32-only identity, inferring rank from two incompatible uses of an unannotated
callback, or implementing `forall [a] => a -> a` by returning 42. A skolem
cannot enter an older inference variable, public result, associated equation or
exported interface as a free identity. Escape checks walk types, rows, evidence
and capture/storage footprints, not just the visible result type.

## Packages and opening

`exists [a] where { Predicates } => T` hides one or more type witnesses and
transports their checked evidence. Existential binders are type binders only:
regions, live capability identities and usage obligations cannot be hidden.
`pack [Witnesses] value as PackageType` requires an explicit existential type,
checks value against its substituted body and constructs every required proof.
Witnesses may be private producer representations, but the consumer sees only
the abstract interface. Missing, ambiguous or incompatible evidence rejects
packing.

`unpack package as [a] value in expression` evaluates the package once and opens
fresh rigid abstract identities plus its evidence in expression. Binder count
must match; value is a plain local name. The result cannot contain the opened
identities in types, projections, evidence or captures. Opening consumes an
affine package and borrows an unrestricted package for the lexical open scope.
Repacking within the scope is allowed when it seals every hidden identity and
retains all footprint/usage obligations; leaking a raw value or a closure
capturing its opened representation is rejected. Returning an unconsumed
unrestricted sealed package is legal; a consumed affine owner must leave by
explicit repacking.

```blot
type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = func value => return value }
impl Flag : Render Bool = { const show = func value => return if value then 1 else 0 }
type Item = exists [a] where { Render a } => a
const number: Item = pack [U32] 42 as Item
const flag: Item = pack [Bool] true as Item
const items: Array Item = #[number, flag]
const show: Item -> U32 = func item => return
  unpack item as [a] value in Render.show value
```

Each opening selects its stored evidence, never a newly searched ambient
implementation. `Render.Item a` remains an abstract projection backed by that
same dictionary until sealed or used through an allowed operation. Consumer
reflection, equality and field access cannot reveal a hidden witness. Reject
returning value, casting it to U32, using U32 operations on it, or mixing values
from independently opened packages. Even equal concrete witnesses have distinct
open skolems. Packing a scoped capability does not extend its region: its hidden
value/dictionary/captures remain in the package footprint and cannot escape.

## Representation and specialization

The owned type graph has distinct quantified binders, bound-variable references
and solver-private rigid identities. Bound variables use scope depth, ordinal
and sort. Rigid nonces are request-local and forbidden in published interfaces.
Predicates and associated projections attach to their quantifier or package
owner. Annotation spans are diagnostic-only; lexical scope and alpha-equivalent
structure are semantic. All graph walks share the module inference budget,
128-depth and 4,096-cell comparison bounds; unsupported inference reports a
positioned error and publishes no partial graph.

A package is an immutable owned payload plus an immutable evidence/operation
bundle and its representation/drop descriptor. Hidden values cross its abstract
ABI as typed owned carriers; pack adapters box when representation is not
already uniform and dictionary adapters unbox only at their private concrete
witness. This permits `Array Item` with heterogeneous witnesses without runtime
source compilation or exposing layout. Carrier ownership, closures, unused
fields and cleanup use
[the runtime ownership contract](CONTRACT.md#storage-and-ownership). Known
closed witnesses may specialize away the carrier; abstraction and effects must
remain identical. General unknown runtime packages retain the dictionary ABI.

Higher-rank code retains a checked parametric template and evidence parameters;
closed call sites specialize it at each type/row instantiation. Dynamic calls
use the same typed-carrier/dictionary ABI, never one monomorphic function
pointer for incompatible representations. Raw host callbacks cannot claim a
forall without that ABI and verified evidence. Entry ABI adapters expose only
supported closed monomorphic signatures; no implicit export of internal skolems
or dictionaries.

Portable graphs preserve binder sorts/order, alpha-normalized types, predicates,
associated members, effects, usage/footprints, owned package shape and
executable adapter/body dependencies. Producer identities use canonical origin
and name; private witnesses stay sealed. A version/feature marker distinguishes
new forms; older readers reject them. Checkpoints and dependencies never contain
solver addresses, live scope tokens or transient IDs.
Template/witness/evidence/drop changes invalidate affected semantic and
executable users even if the outer package type is unchanged. Failed edits/OOM
leave the accepted revision intact.

Diagnostics distinguish `rank_annotation_required`, `rank_mismatch`,
`skolem_escape`, `package_witness_mismatch`, `package_evidence_mismatch`,
`abstract_representation_access` and `polymorphism_budget`. Identify the binder,
opening site and escape/use site without revealing a private witness to callers.

064 qualifies checking, rank-2 multi-instantiation, imported annotations, escape
through projections/captures and failure/OOM. 065 qualifies
concrete/heterogeneous packages, dynamic dictionary execution, private
witnesses, portable round-trips, retained invalidation and destruction. Partial
checking or source-only packing cannot close either implementation task. This
specification has no runtime or performance claim.
