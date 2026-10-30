# Typed staging and hygienic generation

Normative design for 066–068, ahead of unfinished implementation dependencies.
The [guide](../compiler/guide.md) still excludes general type-valued
computation. [Host asset parsing](LANGUAGE_EVOLUTION.md#external-asset-boundary)
remains its existing explicit tracked-input boundary. Blot generation uses only
the ordinary lexer/parser/checker/Core pipeline, never a string compiler or
runtime interpreter.

## Code and stages

`code [T, row E]` is a compile-time code value with result T and latent effects
E. `descriptor T` is a compile-time immutable type description, with the same
abstraction and evidence rights as T. Neither is a runtime-reachable guest
value. Stage zero is compilation; quoted bodies describe the next stage. Nesting
quotes adds one stage and is bounded by the normal frontend/evaluation budget.

`@code.quote expression` parses expression normally and checks it one stage
later. `@code.splice code` is legal inside quote: its operand is
checked/evaluated in the surrounding stage, then its owned typed graph is
grafted into the quoted graph. `@code.lift value` inside quote embeds an already
available closed immutable value. Only scalars and recursively closed
aggregates/nominals with portable layouts are liftable. Live capabilities,
borrows, resources, demands, host callbacks and local skolems reject crossing.
Immutable asset references lift as symbolic manifest references tied to exact
parsed bytes, never by reopening their origin.

`@code.emit code` is a generation site: splice its typed body into the ordinary
surrounding program, adding its latent effects to that site's row.
`@code.run code` is compile-time evaluation of closed pure code through ordinary
Core evaluation; IO, Foreign, suspension and unhandled effects reject.
Construction does not run quoted effects. Code may be built/imported by ordinary
pure const functions; unknown runtime code values are rejected rather than
interpreted.

```blot
const left: code [U32, row {}] = @code.quote 40
const right: code [U32, row {}] = @code.quote 2
const answer_code = @code.quote (@u32.add (@code.splice left) (@code.splice right))
entry const answer = func () => return @code.emit answer_code
const checked_answer: U32 = @code.run answer_code
```

Accept matching typed composition. Reject splicing Bool where U32 is required,
using a runtime argument to build code, or running a Foreign code body at const.
Stage-zero locals require explicit lift; spelling alone never captures them.
Quote-local bindings and created effect instances belong to their future stage.
A quoted package may contain closed sealed type/evidence identities; an opened
skolem or current scope capability cannot escape in code or a descriptor.

## Descriptors, hygiene and publication

`@code.describe code` returns its result/effect descriptors. `@descriptor.same`
compares complete type identity; `@descriptor.fields` exposes only public
structural/nominal fields already accessible in the producer's checked scope.
These are typed compile-time operations, not general reflection over private
storage, live values or implementation scratch. Existentials expose their sealed
shape, not their witness. Descriptors cannot grant capability authority.

Own parsed/checked nodes, binder identities, types, operations, evidence and
origin spans. Bound references use private relative binder indices. Free globals
carry canonical producer origin/name plus exact semantic/executable reads. Each
emission gets fresh local identities, including same-spelled generated locals;
explicit imported/outer references retain their checked identities. Repeated
splices duplicate local binders, not free producer identities. Diagnostic source
maps point to quote, splice and generator invocation without reparsing strings.
Private producer operations can remain in sealed checked code, but consumers do
not gain source-level access to their names or representations.

Artifact code records contain the bounded owned graph, public type/effect/usage
shape, portable identities, lexical references and exact dependency frontier.
They carry a schema/feature marker; old readers reject them. Record generator
and quoted bodies, imported implementations including negative selection reads,
descriptors, compiler/schema/options and every explicit tracked host input.
Runtime values are excluded from keys. Hashes locate offers; exact structured
evidence admits them. A body/input change with the same result type still
regenerates its executable users. Shared read ownership does not copy entire
modules.

Generation validates inputs, constructs all owned nodes, checks ordinary
semantic rules and completes publication allocations before installing any
offer. Failure, budget exhaustion, malformed input or OOM discards the complete
candidate and preserves the accepted revision/assets. Retained and restarted
builds use the same hygiene and admission rules. No generated file is patched
after checking.

Diagnostics distinguish `code_shape_mismatch`, `stage_unavailable`,
`cross_stage_authority`, `descriptor_private`, `generated_binding_escape` and
`staging_budget`, with generation and source origins. Existing programs keep
their semantics and absent code tables; no optimization invents code values.

| Acceptance trace                                                | Expected result                                          |
| --------------------------------------------------------------- | -------------------------------------------------------- |
| Two emissions each bind a local `value` beside a caller `value` | Three distinct lexical identities.                       |
| Quote calls an imported opaque operation                        | Preserve its original abstraction/evidence.              |
| Splice a different result/effect/usage shape                    | Reject at splice site.                                   |
| Lift a resource or descriptor for a live scope/skolem           | Reject before publication.                               |
| Asset bytes change, type remains U32                            | Rerun tracked generator and affected executable users.   |
| Generator fails after allocating a partial graph                | Keep prior code/assets usable; release candidate owners. |
| Restart from dependency/checkpoint code records                 | Same bindings, bytes, source fuel and failure behavior.  |

067 implements code/descriptor typing and const evaluation; 068 implements owned
hygienic emission, exact dependencies and retained/restart/OOM laws. Their gates
include population and retained costs. This design alone makes no speed claim
and does not close 053, 065, 067 or 068.

## Current implementation frontier

Closed scalar/structural composition, nested quotes, imported generators and
plain future closures pass focused ownership, hygiene and revision laws.
Callable descriptors retain the quoted closure's own row certificate; operation
labels remain in their complete type identity. Portable admission reconstructs
quote effects and replacement value shapes, rejecting forged authority and
cross-stage captures. Unsupported snapshots omit semantic reuse and restart
recomputes. Ordinary snapshots retain a zero-allocation staging check.

Helper proofs retain lexical bindings, return targets, mutable branch merges,
loop carries, generic substitutions, ordinary nominal construction/field reads
and collection operations. Both latent callable bodies and actually executed
effects are reconstructed. Static providers, fresh future scope instances, local
closures and row-polymorphic calls use their actual owner certificates. Named
provider callbacks retain local or foreign producer principals. A future scope
capture needs an actual capture edge and complete lifetime report; stage
equality or a claimed capture list supplies no authority.

Public nominal descriptors expose common accessible fields with their owned
substitutions. Closed sealed package staging preserves its cleanup owner.
Tracked asset bytes, failed revisions, source/archive/checkpoint restart and
independent emissions have focused executed controls. Future affine parameters
also have portable move and allocation-failure laws. Lexical loan callbacks
retain their actual region owner across independent emissions; captured loans
remain under development. Resource acquisition, release and scope bodies retain
ordinary cleanup ownership and reconstruct their actual Foreign effects. Direct
request loops additionally retain the operation declaration and separate
computation/clause row owners. Earlier-stage lift/splice operands use their own
move environments through nested quotes and once generators; only the closed
result crosses the boundary.

General named pattern/request/resolver helpers, captured loans and general
resource captures, general qualified producer transport and complete generated
declaration/source map support remain unfinished. Full combined compiler and
cost qualification remain open; [the staging record](STAGING_QUALIFICATION.md)
separates focused results from completion of 067/068.
