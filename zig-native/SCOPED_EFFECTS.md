# Scoped effect identities

This specifies scoped effect identities, subtraction and escape checking. It
extends the
[current closed-family behavior](../compiler/guide.md#effect-families-and-scoped-state).
The full design below remains the target. A direct annotated scope subset is
implemented; see
[its qualification and limits](SCOPED_EFFECTS_QUALIFICATION.md). Existing closed
operations, providers, State runners and request handlers retain their behavior.

## Source surface

An effect-family type in a value annotation denotes a capability for that
family. Its type arguments describe operation signatures; its identity is a
separate checked value fact. Two values of `State U32` can therefore name
different instances without inventing different U32 types.

`@effect.scope (fn (state: State U32) => body)` creates one fresh capability,
calls the callback once, and returns its result. The callback has exactly one
capability parameter with an explicit family annotation. Every dynamic scope
entry is fresh, including recursion and repeated calls at the same source site.
The capability lives until that callback finishes. Scope creation installs no
provider: the body must handle or forward its operations within the fresh
owner's lifetime. Its residual effect cannot cross scope exit.

`state.get` selects the family's declared operation as a callable value;
`state.get ()` invokes it. Existing provider/runner/request syntax accepts this
operation value. The names `State`, `get` and `set` grant no compiler privilege;
ordinary effect declarations determine members and signatures.

```blot
type State a is effect = {get: Unit -> a, set: a -> Unit}

entry const two = fn () => @effect.scope (fn (left: State U32) =>
  @effect.scope (fn (right: State U32) => do:
    use (outer, result) <- do (@effect.state left.get left.set 10):
      use (inner, reads) <- do (@effect.state right.get right.set 100):
        use a <- left.get ()
        use b <- right.get ()
        use left.set (@u32.add a 1)
        use right.set (@u32.add b 2)
        return #[a, b]
      return @array.concat #[inner] reads
    return @array.concat #[outer] result
  )
)
```

The result is `[11,102,10,100]`. The right provider forwards the left operations
to the outer provider. Its installation cannot redirect them merely because both
capabilities have type `State U32`.

Generic operations accept symbolic type arguments in written rows:
`Unit -> a ! {State.get a}` names the ordinary static family instance selected
when `a` is instantiated. This extends today's rejected free type argument;
closed specializations retain today's exact source/type identity.

Rows may also name a capability operation or its proven operation alias.
Parameter scope includes its function's result annotation:

```blot
const read = fn (state: State a) -> a ! {state.get} => state.get ()
const alias = fn (state: State a) => do:
  let operation = state.get
  return operation ()
```

A dependent arrow binder permits the same relationship in a complete function
type. Its value name is in scope only in subsequent arrow/result annotations; it
is not a general value-dependent type expression.

```blot
const apply: (state: State a) -> ((Unit -> a ! {state.get}) -> a ! {state.get}) = fn state => fn callback => callback ()
```

The grouped result preserves ordinary arrow-row placement: its written row
describes callback invocation, while supplying the capability remains pure.

Operation aliases retain the exact identity. An arbitrary ordinary function with
the same input/output types cannot serve as a row label. Capabilities have no
public constructor, integer conversion, host ABI or authority-bearing constant
literal. Existing const reflection requires closed static descriptors; an
unresolved symbolic or scoped identity cannot become a closed reflected set.

## Identity and rows

A checked operation key contains its original declaration/member identity,
semantic family arguments and an instance term. Static operations use the
existing static instance. Scoped operations use the capability's bound identity
term. Source spelling, physical layout and current solver ordinals never decide
equality.

Identity terms form a bounded owned graph: capability parameters, captures,
fresh scope binders and value-flow selections. Aliases copy a term. Calls
substitute argument terms for parameter terms; captures preserve that
substitution. A branch-selected capability retains a selection term, rather than
choosing either provider statically. Handling that exact selected value can
discharge its selected operation. It cannot discharge an independent call on
either original value without an equality proof.

Rows retain today's multiplicity and chronological substitution. A provider adds
one occurrence of its exact operation to the body's ambient row; a State
provider adds one occurrence of each selected read/write operation. Subtraction
removes that supplied occurrence only. Explicit repeated labels remain repeated;
they do not count dynamic calls. A matching occurrence may be exposed through an
open tail using the ordinary transactional row rules. Same family/type with a
different instance term is not a match, and unresolved identities never become
empty effects.

Nearest matching provider lookup compares the complete runtime key. A callback
runs under the matched frame's outer chain, excluding itself and younger
installations, as in
[the current provider chain](src/backend/provider_chain.zig). Unrelated keys
forward. Reinstalling the same capability is ordinary nested shadowing; creating
a new capability is generativity. Each State installation still allocates a
fresh state cell, separately from capability creation.

Request clauses use the same exact key. Two different scoped keys are distinct
clauses; duplicate clauses for one substituted key reject. Captured
computations, requests and forwarded callbacks preserve identity through
suspension. Neither inlining nor specialization may hoist scope creation or
merge dynamic entries.

## Lifetime and capture

Scope exit requires that its fresh identity occurs in neither the result's
reachable capability footprint nor the residual effects. Footprints accompany
values and checked callable contracts separately from effect rows: a pure
closure can capture authority. Products, collections, constructor payloads,
closures, demands, providers, computations and selected method evidence carry
the footprints of their reachable members.

Returning a capability, its operation, a capturing closure/demand or an
aggregate containing one rejects. A completed memo retains the footprint of its
stored result; an unforced memo retains its captures. Handling an operation
removes an effect requirement, never its captured authority. A result discarded
before exit does not escape. A projected capability-free component may escape
when checked structural evidence proves its footprint empty.

Local callbacks can use the capability while its owner is alive. Generic
functions publish owned parameter/capture/result/store footprint relationships;
callers substitute actual identity terms. Returning a parameter is valid within
its caller's lifetime, but a fresh scope still rejects that returned value at
its own boundary. Calls cannot erase obligations through a pure annotation, an
unconstrained type variable or an unresolved callback target.

Writing a capability-bearing value to a longer-lived State cell, persistent
root, host capture or resource is an escape too. The sink must have a checked
lifetime contained in every captured capability's lifetime. Foreign calls and
unknown storage contracts conservatively retain their arguments; capability
footprints cannot cross them. Future usage contracts may prove a narrower sink.

Generic and opaque store contracts publish the sink lifetime and its
relationship to argument footprints. A State cell born before a fresh scope
cannot store that scope's capturing pure closure, even when the scope returns a
scalar. A cell born inside the scope and discarded before exit may store it.
Private ownership journals retain implementation roots within their activation;
their temporary retention does not constitute a semantic escape sink.

Opaque public views expose sufficient footprint relationships without exposing
private payloads. Source and compiled callers enforce the same relationships. An
opaque wrapper, associated witness or polymorphic identity function cannot hide
a shorter-lived capability. Recursive footprint analysis is bounded and
conservative; exhausting it reports a diagnostic instead of claiming emptiness.
The default per-binding limits are128 graph depth,65536 visits and4096 identity
terms. Diagnostic traces retain at most four origins/eight steps/2048 encoded
bytes; truncating a trace never truncates the semantic escape check.

## Runtime and transport

Static keys keep their current catalog representation. A dynamic key pairs the
specialized operation descriptor with an owned activation identity. Capabilities
and operation closures retain that activation owner; provider frames store the
same key. This representation is independent of the State cell and provider
head. All changes obey [the ownership contract](CONTRACT.md).

Register an owned scope-end cleanup record before exposing the capability. The
scope owner has an active state and participates in ordinary activation cleanup.
It stays active across suspended calls/requests. On normal completion, early
return, trap or cancellation, cleanup marks it inactive exactly once before
frame/field retirement. Revocation is distinct from reference destruction: a
local closure or ready-memo cycle may still retain the identity, but cannot
prolong its authority. An owner never reactivates. Outstanding owned handles
keep its identity distinguishable until released; recycled addresses cannot
impersonate it. Invoking an inactive operation fails before provider lookup. The
host cannot construct or deserialize fresh authority.

Scopes nested inside resumable computations belong to those computation
activations, not the native/C stack that first entered them. Cancellation
detaches the owned activation once. This is required in058 even before the
broader resource contracts in062; a synchronous-only cleanup is insufficient.

The existing demand-force journal alone does not provide scope-end cleanup. A
canceled pending request may retry under current request semantics; rerunning
the scope creates a new owner at the same site. An authority-free ready memo
keeps its existing strong result, and terminal memos remain terminal. JSPI host
rejection revokes through activation cleanup without silently converting pending
request cancellation into terminal failure.

Public schemes and dependency/checkpoint evidence encode symbolic identity
binders, substitutions, operation origins and footprint relationships. They
never serialize a live activation ID or provider head. Loading code recreates
fresh owners when it runs. Evaluator snapshots or constant receipts containing
fresh authority decline ordinary value transport/reuse. Compile-time execution
may run a fully handled scope and return capability-free data, but reusing that
evaluation needs an explicit receipt for its generative work.

Source/artifact validators check binder scope, graph edges, operation
signatures, family arguments, capture relationships and limits before
publication. Cache keys include the owned identity/footprint interpretation and
every consulted source or interface fact. A changed operation argument, hidden
capture/store contract or provider target revokes the affected receipt even with
identical machine layout. OOM and rejected edits preserve the previous
successful owner.

## Diagnostics and acceptance

Use existing unknown-member, type/effect mismatch, duplicate-request and
open-descriptor diagnostics where their meanings apply. New diagnostics are
`effect_identity_scope` for an unbound/unresolved identity term,
`capability_escape` for an invalid lifetime transfer and
`capability_analysis_limit` for an exhausted proof. Escape reports name the
originating scope, first escaping capture/store/result and requesting use;
traces remain bounded. A static operation and a scoped capability with the same
family are reported as distinct keys.

| Case                                                     | Required result                                                           |
| -------------------------------------------------------- | ------------------------------------------------------------------------- |
| Nested same-typed State capabilities                     | Independent cells and result `[11,102,10,100]`                            |
| Alias or captured operation                              | Exact original owner/provider                                             |
| Generic symbolic family argument                         | Correct closed specialization; distinct semantic arguments stay distinct  |
| Generic capability plus callback                         | Argument identity substituted through callback row/capture                |
| Same capability installed twice                          | Inner provider wins; callback forwards under its outer chain              |
| Handler for a different capability                       | Original requirement remains unhandled                                    |
| Repeated labels/open tails                               | One supplied occurrence removed; multiplicity/cursors preserved           |
| Selected capability                                      | Runtime selection and exact selected-key subtraction agree                |
| Return capability/operation/closure/demand/aggregate     | Escape rejected, including pure and already-handled closures              |
| Escape through opaque/associated/compiled evidence       | Same rejection as source                                                  |
| Write into longer-lived State/root/host                  | Escape rejected at the sink, including hidden generic/opaque stores       |
| State born inside scope; private journal retention       | Accepted when discarded at exit; no false semantic escape                 |
| Nonescaping local callback                               | Accepted and executable                                                   |
| Two calls/recursion/loop at one fresh site               | Separate activation identities; no hoisting or merging                    |
| Suspend, resume, trap and cancel                         | Owner remains active while suspended; cleanup once at termination         |
| Canceled retry / ready or terminal memo / JSPI rejection | Fresh retry owner; memo state preserved; revocation before retirement     |
| Source/dependency/restart/failed edit/OOM                | Same routing, diagnostics and owned evidence; no fresh authority restored |

058 must measure added checking/key work and runtime routing against closed
static controls, with seven alternating compiler pairs and31 warmed guest
pairs.059 must test every hidden escape path and accepted local use in both
codegen tiers and sync/JSPI execution. Both require native allocation-failure
laws, fresh/retained/checkpoint parity, zero teardown owners, the full compiler
gate and zero analyzer findings. This design does not complete either task.
