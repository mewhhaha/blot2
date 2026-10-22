# Bounded numeric and index proofs

Design for tasks 069–071. This document proposes a source surface; the
[language guide](../compiler/guide.md) describes the implemented language. It
extends [associated evidence](ASSOCIATED_CONTRACTS.md) and the value binders
specified for [scoped effects](SCOPED_EFFECTS.md). These proofs add no general
value-dependent type computation or user-defined theorem solver.

## Values, propositions and witnesses

A proposition refers to immutable checked value identities. A source spelling,
Wasm local number, collection length, pointer equality or equal machine layout
cannot substitute for that identity. Each rebinding creates another version; an
alias of the same checked value preserves its version.

The initial intrinsic witness types are:

| Type                        | Fact                                                 |
| --------------------------- | ---------------------------------------------------- |
| `@proof.U32Eq x y`          | Unsigned values `x` and `y` are equal                |
| `@proof.U32Lt x y`          | `x < y` in unsigned U32 order                        |
| `@proof.U32Le x y`          | `x <= y` in unsigned U32 order                       |
| `@proof.U32AddFits x y`     | Mathematical `x + y` is at most `4294967295`         |
| `@proof.U32SubFits x y`     | `y <= x`, so subtraction does not wrap               |
| `@proof.Index values index` | `index < length(values)` for this collection version |

`values` has type `Array a` or `List a`; numeric operands have type U32.
Operands in a written witness type are preceding value binders, U32 literals, or
`@array.length values` / `@list.length values` over those binders. General
calls, mutable reads, effects and arbitrary expressions are forbidden there.
These annotation terms are checked descriptions, never evaluation requests. The
`@proof` namespace is intrinsic. Ordinary contract or implementation names do
not create proof authority.

A dependent arrow exposes a value name in subsequent annotations, as specified
for capability rows. For example:

```blot
const at: (values: Array a) -> (index: U32) ->
  (@proof.Index values index) -> a =
  fn values => fn index => fn proof => @array.get values index
```

Instantiation substitutes the checked identities of the first two arguments into
the final proof parameter. A proof about another array with the same length does
not satisfy this parameter. Passing an exact alias does. A generic helper cannot
infer a missing value argument from a witness or use an associated type equation
as numeric evidence.

## Introduction and use

`@proof.eq`, `@proof.lt`, `@proof.le`, `@proof.add_fits`, `@proof.sub_fits` and
`@proof.index` take their two value operands and return the corresponding
witness. Operands evaluate once, left to right. Each constructor checks its
stated condition and traps if false. The trap belongs to that expression;
earlier effects still run, and later expressions do not. Index failure uses the
ordinary collection bounds trap. Numeric failure uses a specified
`invalid_numeric_proof` trap. These are checked constructors, with no unchecked
constructor or assume operation.

A valid in-scope witness or branch fact can discharge the constructor's check.
Without one, the ordinary runtime check remains. A condition known false cannot
produce evidence: execution reaches the required trap. The checker must not use
contradictory facts to justify arbitrary propositions or remove that trap.

Required witness contracts reject contradictions established by the finite rules
below with `contradictory_proof`: for example, simultaneous `U32Lt x y` and
`U32Le y x`, or a required `U32Lt 0 0`. A dynamically false checked constructor
instead retains its trap; it does not assert an unchecked contract.
Contradictory automatic branch facts make that successor unreachable after
evaluating its guard. They never supply a witness to a reachable successor.

```blot
entry const checked = fn (values: Array U32) => fn (index: U32) => do:
  let valid = @proof.index values index
  break at values index valid
```

This performs one bounds check at construction. The helper's access consumes the
same exact fact, so it needs no second check. A direct ordinary access without
proof remains valid and keeps its existing check.

Witnesses are erased checked values. They support lexical aliases and explicit
proof parameters, including imported generic helpers. They cannot be compared,
cast, reflected, exported through the host ABI or constructed from Unit/data.
They have no fields or public constructors. Proof-only parameters occupy no
runtime argument slot. Ordinary operand arguments retain their normal calling
and ownership rules.

The initial surface does not store witnesses in products, collections, nominal
payloads, demands, resources or returned closures. A witness result is allowed
only when every operand is a literal or a preceding public value binder in its
complete result contract. A local temporary identity cannot escape in a result.
Returning the corresponding data separately does not invent an existential
relationship; such packaging needs the later explicit package machinery.
Dropping or repeatedly consuming a witness is valid; it owns no runtime value.

Witness propositions have a distinct erased proof kind. Ordinary type variables,
associated data-type equations and type-representation witnesses cannot be
instantiated with this kind. The initial API admits explicit proof parameters
and complete proof result recipes, not generic containers or an unrestricted
`a -> a` helper instantiated at a proof. A lexical alias preserves its exact
proposition. This keeps ordinary runtime polymorphism independent of proof
calling conventions; no Unit substitution silently bridges the two kinds.

## Branch and arithmetic facts

Only the resolved intrinsic U32 comparisons introduce automatic order facts. A
user-defined operator that happens to be spelled `<` supplies no proof. A true
`x < y` edge adds unsigned strict order; its false edge adds `y <= x`. Equality,
non-equality and the other unsigned comparisons have their exact complementary
rules. The prelude's demand-based `&&`/`||` contribute only along the actually
evaluated edges established from their checked bodies. A name or operator
spelling alone grants no short-circuit fact. Effectful operand expressions are
first evaluated into exact values; subsequent re-evaluation is another value
unless ordinary checked alias evidence proves it identical.

Dominated instructions can consume a fact. Joins retain only facts established
on every reachable incoming edge after the existing value-version mapping. A
branch-selected array or index needs facts for that selected version on every
edge. Comparing just the predecessor spelling or storage slot is insufficient.
Loop entry facts about unchanged outer values survive. A carried or rebound
value has a new identity and loses predecessor facts. The initial rules do not
infer loop invariants or induction proofs: a guard inside the current iteration
can prove an access using that iteration's value. Exiting a branch drops facts
owned only by that branch.

U32 addition, subtraction and multiplication retain their existing modulo-2^32
semantics. An integer inequality does not silently change that arithmetic to
unbounded arithmetic. In particular, `index < length` alone does not prove
`index + offset < length`, and wrapping multiplication never grants a bound.
`AddFits` and `SubFits` can authorize the corresponding nonwrapping transfer
rule; they do not prove the resulting collection index is in range. No initial
multiplication, division, signed-integer or F32 theorem rule is supplied.

The finite deduction rules are exact-term substitution by equality, unsigned
reflexive `Le`, `Lt` weakening to `Le`, transitivity of `Le`/`Lt` (strict when
either edge is strict), evaluation of literal comparisons, and the stated
intrinsic length equations. `Index values index` is equivalent to
`U32Lt index length(values)` for that exact collection. Known U32 values satisfy
`0 <= x <= 4294967295`. `SubFits x y` is equivalent to `Le y x`; `AddFits x y`
is equivalent to `Le x (4294967295 - y)`, where this complement is an internal
nonwrapping term. With `AddFits x y`, an ordinary addition result has its
mathematical sum; with `SubFits x y`, subtraction has its mathematical
difference. These are directed intrinsic result equations, not arbitrary
algebraic rewriting. No deduction from a contradiction is permitted. Work for
transitive edges and result equations consumes the same body budget.

Persistent collection updates create new checked versions. A length-preserving
update can preserve a bound only through its intrinsic length equation;
concatenation, slicing, filtering and calls with no exact length contract
cannot. An old witness still describes the old immutable value if that value
remains available. Foreign results and unknown callbacks never inherit facts
from their inputs merely because layouts or lengths coincide.

## Check-removal examples

These examples specify 070–071 behavior; proof syntax is not yet executable. The
ordinary guard below evaluates once. The access retains its load and result but
removes its redundant bounds comparison:

```blot
entry const guarded = fn (values: Array U32) => fn (index: U32) => do:
  if index < @array.length values:
    break @array.get values index
  break 0
```

With an empty array, only the fallback runs. At length one, index zero reaches
the load and index one reaches the fallback. The same result holds when the
comparison is expressed by its exact unsigned intrinsic. An overloaded
comparison requires proof from its checked body before supplying these facts.

A new index version keeps its own check:

```blot
entry const next = fn (values: Array U32) => fn (index: U32) => do:
  if index < @array.length values:
    index := index + 1
    break @array.get values index
  break 0
```

The original comparison alone does not prove the rebound access. A one-element
array and index zero must trap at the load; the compiler cannot reuse the old
index witness. Generalizing the increment to an arbitrary U32 offset also keeps
the ordinary wrap semantics. `U32AddFits index offset` establishes only that
this addition does not wrap; a separate bound for the sum is still required.

A witness created for `left` cannot satisfy `at right index proof`, even when
both arrays currently have the same length. An exact alias of `left` can. A
length-preserving intrinsic update can prove a new index fact through its length
equation, but the old witness parameter still names `left`. A join of different
arrays cannot choose whichever predecessor happened to have a proof.

`@proof.add_fits 4294967295 1` traps after evaluating its operands. The ordinary
expression `4294967295 + 1` still produces zero. Neither expression changes the
other's semantics, and neither establishes an index for an empty collection. A
dominating explicit bounds witness removes a later repeated constructor check
and the matching access check; it never erases an earlier necessary constructor
trap or an effect before it.

## Owned evidence and separate compilation

Each checked body owns a flat term/proof graph. Terms name formal value slots,
capture slots, source value versions, literals and exact intrinsic lengths.
Proof nodes name the proposition, introduction instruction or incoming formal,
and the complete predecessor proofs. Runtime stores and solver ordinals are not
portable identities. Formal/capture substitution imports this graph once per
checked invocation, with explicit remapping and no dependency on source names.

Public interfaces carry complete witness parameter/result recipes. Implemented
bodies retain their required checks and the conditions under which each removed
check is justified. Source and compiled callers apply the same substitution and
proof matching. A proof is not an implementation declaration and cannot be
supplied by an overlapping or private implementation.

Artifact decoding validates tags, bounds, operand types, formal scope, graph
acyclicity, introduction conditions, dominance and every proof consumer. A
compiled body must pair its proof graph with the exact admitted body/control
flow. Deleting a guard, changing a relation/index/length, moving a consumer past
a join or substituting another producer must reject the artifact. Hash equality
only locates an admission candidate. Omitted optional optimization evidence
recomputes checked code; malformed required public proof contracts reject.

Retained keys include the exact value/control-flow recipes, intrinsic arithmetic
interpretation and imported public proof contracts. Guard, binding, callee and
length changes revoke dependent elimination. Failed edits and failed imports
publish no partial evidence. Evidence owns its data independently of source
ASTs, inference scratch and producer lifetimes; OOM releases every partial
owner.

## Bounds, diagnostics and erasure

A checked body admits at most 4,096 term nodes, 256 simultaneous branch facts,
128 nesting levels and 65,536 proof-rule visits. Charge edge and pair work,
including failed matches; memoize visited graph pairs so shared DAGs do not
expand into trees. Use exact equality after hash lookup. The proof subsystem is
inactive for a body with neither proof constructs nor a check-removal candidate.

Optional branch reasoning that exceeds a limit drops affected facts and emits
the ordinary checked operation. An explicit checked constructor also retains its
runtime check when it lacks a bounded static proof. Required type/contract
validation cannot guess: malformed or excessively large required evidence emits
`proof_analysis_limit` or rejects the artifact. No budget exhaustion grants an
unchecked access.

Diagnostics distinguish `invalid_proof_operand`, `proof_mismatch`,
`proof_scope_escape`, `proof_runtime_use`, `contradictory_proof` and
`proof_analysis_limit`. They show the expected and actual bounded proposition
plus the relevant value binding or guard origin. Source-less dependencies retain
producer/member identity and omit unavailable source spans. At most four origins
and eight explanation steps are rendered, under the existing diagnostic byte
cap.

After checking, witness values, aliases, parameters and derivation steps erase
completely. They allocate no runtime objects, carry no Wasm locals and create no
retain/release work. Necessary constructor guards remain ordinary comparisons
and traps; proven guards disappear. Removal of a bounds check cannot remove the
read itself, reorder operand evaluation or discard earlier effects. Access
lowering consumes a validated proof flag in resolved IR, rather than consulting
mutable solver state during Wasm emission.

## Acceptance matrix for 070–071

- Empty collections admit no index. Length one admits only zero. U32 maximum,
  maximum-minus-one, zero offsets and wrapping increments preserve exact traps.
- A proof for one value/SSA version, different array, rebound index or private
  opaque representation cannot discharge an unrelated access.
- Dominating true/false and short-circuit edges, nested branches, joins and loop
  carries retain exactly their valid facts. Contradictions never manufacture a
  reachable proof. Tests execute effects immediately before failed constructors
  and accesses to prove trap ordering.
- A generic imported `at` accepts matching caller evidence, including re-exports
  and compiled producers after producer teardown. Forged recipes, guard
  deletion, cross-producer substitution and invalid escapes reject with owned
  diagnostics.
- Every retained guard/index/length/implementation edit matches independent
  fresh diagnostics, results and bytes; failed edits preserve the preceding
  revision. Portable restart and every allocation-failure boundary preserve
  those laws.
- Inspect Wasm to prove witness erasure and the exact number of bounds checks.
  Measure fresh and retained CPU, proof visits and requested/peak memory on
  no-feature controls, proof-heavy straight-line code, joins and shared DAGs.
  Check limits with a small test budget while preserving exhaustive OOM
  coverage.

No runtime performance or compiler qualification is claimed by this design.
