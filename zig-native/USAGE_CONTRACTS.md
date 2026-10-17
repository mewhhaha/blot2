# Usage and lifetime contracts

Normative design for tasks 060–062. The full contract below remains the target;
bounded implementation and qualification status are recorded at the end.
[The guide](../compiler/guide.md), [shared ownership](SHARED_OWNERSHIP.md),
[suspended ownership](SUSPENDED_OWNERSHIP.md) and
[scoped effects](SCOPED_EFFECTS.md) retain their existing semantics.
Specification work may finish before 059; implementation must preserve its
capability escape checks.

## Surface and meaning

Type qualifiers bind to one type atom; parentheses delimit arrows:

| Form                         | Obligation                                                                   |
| ---------------------------- | ---------------------------------------------------------------------------- |
| `unique T`                   | One movable owning path; implicit copying is forbidden.                      |
| `shared T`                   | Immutable owning value, safely repeatable under ordinary retain/release.     |
| `borrow r T`                 | Copyable read-only loan bounded by region `r`; no ownership transfer.        |
| `borrow_mut r T`             | Affine exclusive loan; no other loan or owner access while active.           |
| `once (A -> B)`              | At most one invocation, consuming the callable. Dropping it unused is legal. |
| `many (A -> B)`              | Repeatable invocation; captures cannot require affine consumption.           |
| `cleanup (unique T -> Unit)` | A verified non-suspending cleanup adapter with the cleanup ABI.              |

Bare arrows remain `many`; existing immutable values retain their current
behavior. Qualifiers are contextual type syntax, not magic prelude declaration
names. Affine properties propagate through aggregates and opaque interfaces.
`once` never means exactly once: cleanup runs on an unused owning closure too. A
source protocol needing an invocation must return checked completion evidence;
the compiler does not infer that obligation from `once`.

`@usage.share value` consumes a unique owner and returns shared ownership. There
is no shared-to-unique cast or refcount-based proof.
`@usage.borrow owner callback` and `@usage.borrow_mut owner callback` create a
fresh lexical region, invoke the callback once, then end the loan. Their
callbacks are checked with the region binder from
[polymorphic packages](POLYMORPHIC_PACKAGES.md). The callback result must not
retain that region. Outlives constraints follow lexical nesting; no implicit
lifetime inference or arbitrary region inequalities are introduced.

A many callable can be consumed where once is required; the reverse conversion
is invalid. Arrow subtyping checks argument contravariance, result covariance,
latent effects and all lifetime/usage obligations. A loan does not satisfy an
owning argument. Shared conversion is explicit. No conversion drops a capability
footprint or cleanup obligation.

## Binding versions and control flow

Moving an affine value invalidates its binding version. A copied alias is an
error, including through a generic identity, tuple, closure or package. A borrow
suspends conflicting owner uses until its scope ends. Pure persistent updates
keep their existing semantics; an exclusive qualifier alone does not authorize
unchecked mutation.

Branches join live/moved/loan states. A value moved on one branch cannot be used
after the join; its still-live branch emits the required drop. Every loop back
edge must restore the same ownership and loan state. An outer once callable
cannot be invoked in a loop unless a checked bound proves at most one iteration;
a fresh callable created inside each iteration is allowed. Break/return edges
carry their own ownership states. Unknown recursive/higher-order multiplicity
rejects affine arguments rather than assuming one call.

Closure creation transfers owning affine captures or records bounded loans.
Invoking a once closure transfers its captures to the invocation; abandoning it
drops them. Many closures cannot hide an affine owned capture. Capturing a
capability preserves its exact identity and owner region. Demand creation moves
its captured owners into the demand. Cancellation may retry a demand, so its
body cannot consume an affine capture without a restart-safe checked protocol.
A demand parameter moves its captured owners once only when the callee declares
it affine before generic instantiation (`~(value: unique T)`); a generic demand
parameter such as `keep = fn ~value` stays retryable, so a consuming capture is
rejected there. This is fixed at the call as `demand_once`.
Ready demands retain their strong results; usage contracts never weaken memos.

## Resources and exits

`@resource.acquire acquire release` evaluates its two arguments, invokes acquire
once and attaches the verified cleanup adapter to the returned unique owner. The
owner may move only under an explicit result/capture lifetime contract; its last
owning drop attempts cleanup. `@resource.scope acquire release callback` is the
lexical loan form. It evaluates the three arguments in written order, calls the
unit acquisition thunk once, registers the returned unique resource and cleanup
adapter before exposing a loan to the callback, then ends the loan and attempts
cleanup exactly once. Acquisition failure registers nothing. Callback evaluation
uses a fresh region; a returned closure, package, demand or aggregate retaining
it is rejected. Nested resources clean up in reverse registration order.
Transfers move the cleanup obligation; loans never move it.
`@resource.release owner` consumes an explicitly transferred resource and
invalidates all its capabilities before invoking its registered adapter.

Cleanup adapters may use pure operations and synchronous host cleanup authority;
they cannot suspend, force demands or rely on a source provider that has already
unwound. Unknown adapters require explicit verified cleanup evidence. This is
not ordinary function effect inference: host metadata must promise the cleanup
ABI and synchronous completion. Cleanup must also carry a finite call/iteration
bound; unbounded loops, recursive cycles and unknown higher-order calls are
rejected. A host adapter supplies a bounded completion contract rather than a
source termination guess. A cleanup failure records the first failure and
continues other registered cleanup attempts; the failed adapter is never
retried.

Normal returns, breaks and request cancellation emit language cleanup. A Wasm
trap cannot run arbitrary Blot unwinding. Host invocation leave drains a
separate typed cleanup journal before revoking callbacks and releasing
invocation roots; raw ABI callers must invoke that hook after traps or host
rejection. During JSPI suspension the journal remains owned until settlement.
Cancellation waits for an unabortable host call; it cannot retire live owners.
Exactly-once refers to each registered cleanup attempt, not successful release
by a failing host. These are 062 requirements, not claims about the current
guest ABI.

## Portable evidence and diagnostics

Publish qualifiers, binder sorts, region/outlives relations, invocation upper
bounds, parameter/capture/result/storage footprints, ownership transfers and
cleanup adapter roles in principal interfaces and immutable Core. Opaque and
package boundaries carry the same facts. Bound regions use declaration-local
binder ordinals; live region instances never enter portable artifacts. Imported
calls validate the complete contract before erasure. Missing, stale or excessive
evidence rejects; optimizer uniqueness and call-count guesses are insufficient.
Checks share the inference budget, with at most 128 scope depth and 4,096 states
per contract comparison. Unknown joins decline with a precise diagnostic.

Diagnostics distinguish `use_after_move`, `duplicate_owner`, `borrow_conflict`,
`borrow_escape`, `once_reused`, `multiplicity_unknown`, `cleanup_not_safe` and
`usage_evidence_mismatch`, showing the declaration, first conflicting use and
owner scope. New forms require a portable schema feature marker; ordinary
modules keep their previous representation. Usage/body/adapter edits invalidate
both semantic contracts and executable cleanup users; failed revisions publish
nothing.

| Acceptance case                                                    | Result                                               |
| ------------------------------------------------------------------ | ---------------------------------------------------- |
| Move `unique T` into a once closure, then call once or discard     | Accept; one owner/drop path.                         |
| Store the same unique value in two fields                          | Reject duplicate owner.                              |
| `@usage.borrow value (fn loan => inspect loan)` returning U32      | Accept if inspect has a read-loan contract.          |
| Return `loan`, `fn () => inspect loan`, or a package containing it | Reject borrow escape.                                |
| Conditionally invoke once, then invoke it after the branch         | Reject possible second invocation.                   |
| Resource scopes A then B, callback returns or cancels              | Trace acquire A, acquire B, drop B, drop A.          |
| Trap/host failure while B lives                                    | Host leave attempts B then A; no stale callback use. |
| Drop B fails                                                       | Still attempt A; report B failure once.              |
| Imported function hides duplication or missing cleanup metadata    | Reject before calling it.                            |

061 qualifies source/checker, aliases, branches, loops and imported
multiplicity. 062 qualifies emitted cleanup, sync/JSPI/trap journals, transfer,
failed revisions and every-allocation ownership. Both need
fresh/retained/restart equality and separate population/edit costs; this design
has no executable performance claim.

## Bounded implementation and qualification

The isolated 061 continuation preserves qualifiers and checks binding moves,
affine captures, branch and exit joins, exact one-iteration bounds and direct
lexical loans. Scalar reads and Array/List logical lengths have source,
immutable Core and executed guest controls, including imports, failed edits and
restart replay. Calls carrying hidden loan captures decline independently at the
Core boundary. Contextual ownership admits fresh scalar literals and Array/List
literals of unqualified primitive elements; an existing unrestricted or shared
binding cannot become unique by annotation. Empty collection literals need a
closed expected element type.

The initial 062 scope slice admits `@resource.scope` only with direct
acquisition, cleanup and loan callbacks, with Unit/Bool/U32/F32 payloads or
Array/List payloads containing only those unqualified primitive elements. A
finite pure cleanup recipe is checked independently in source and Core; loops,
named or unknown calls, projections, demands and host cleanup authority require
additional evidence. This includes qualified names that encode an implicit
member invocation. Cleanup qualifiers require an owning scope and an actual
finite executable adapter; a type spelling alone grants no authority. The
intrinsic owns the builtin Foreign operation, so startup/constant execution
cannot bypass invocation cleanup. Callback region escape rules remain those of
ordinary lexical borrowing. Resource transfer through `@resource.acquire` and
`@resource.release`, other reference payload shapes and standalone cleanup
annotations remain outside this admission boundary. A callback may return
ordinary managed data that contains no loan; its result remains rooted through
cleanup.

The existing runtime cleanup stack emits lexical release actions. Resource
modules alone use ABI 4 with typed journal imports and paired cleanup/root-drop
exports; ordinary modules keep their existing ABI and allocate no journal.
Admission checks exact Wasm hook signatures before invocation. The journal
reserves before acquisition, registers without allocation before exposing the
loan, takes each attempt before executing it and drains in reverse order.
Cleanup failure still attempts remaining drops and preserves an earlier body or
host failure. Released trailing entries are reclaimed; the 4096 limit bounds
live reservations, while monotonic tokens reject stale handles. Guest finish
drains the journal before invocation roots, callbacks and providers retire. JSPI
keeps those owners until host settlement; pending calls cannot reenter or be
disposed. Request cancellation through resource-carrying frames requires a
separate checked admission control and remains unqualified.

Focused qualification passes 24 usage/resource native laws, four backend laws,
three resource guests, three unchanged usage guests and 19 host/journal tests.
Every-allocation source/Core and backend sweeps cover 177 and 311 failures.
Compiled controls run in both tiers and sync/JSPI: normal and early exits,
branch/break completion, failed acquisition, trap, nested failing cleanup and
host throw/rejection. Across 4096 failure/recovery calls, roots, leases and host
references return to zero and warmed memory remains exactly flat. A returned
Array survives subsequent cleanup and allocation; 10000 sequential scopes do not
exhaust the live journal bound. Imported bodies, failed revisions, portable
checkpoint and restart preserve bytes. The former isolated 416-file analyzer
claim is withdrawn because its missing Zig/std backend omitted deprecation
resolution. The transfer continuation checks all 428 current Zig files with the
verified backend and zero findings. Source admission and runtime emission must
integrate as one pair; these focused results do not replace combined release
qualification.

Regression owners are [usage_check_tests.zig](src/check/usage_check_tests.zig),
[usage_backend_tests.zig](src/check/usage_backend_tests.zig),
[usage_execution.test.ts](tests/usage_execution.test.ts),
[resource_execution.test.ts](tests/resource_execution.test.ts),
[resource_guest.test.ts](../compiler/resource_guest.test.ts) and
[resource_journal.test.ts](../compiler/resource_journal.test.ts). Tasks 061 and
062 remain in progress pending their broader nominal, generic, transfer and
cleanup requirements and the combined release gate. No performance qualification
is claimed.

The reference payload continuation reuses ABI 4 and the same journal format. Its
opaque payload word holds the checked reference; scope emission retains the
payload before registration, and adapter 2 drops payload, cleanup and provider
roots even when cleanup traps. The two scalar adapters remain unchanged, and
ordinary modules acquire no resource adapter or journal. The private emission
journal records the exact entry classification of exports, preserving nonentry
cleanup adapters through reconstruction without deriving authority from their
names.

Focused reference controls pass four new native laws (including source/Core and
backend allocation sweeps: 181 and 443 faults), eleven related native laws, and
two guest groups in both codegen tiers. They cover fresh Array/List creation,
denied binding promotion, forged callable elements, finite cleanup, trap and
host rejection, JSPI settlement, managed callback results, zero
roots/leases/host references, flat warmed memory, source/archive equality,
checkpoint restart and failed-edit recovery. The 328-file selected Zig analyzer
check uses the verified Zig/std backend and has zero findings. These results do
not finish tasks 061/062; transfer, broader affinity, host cleanup authority and
checked request-frame cancellation remain open.

Explicit `@usage.share` consumes a unique primitive or primitive Array/List
owner and returns the identical payload under shared ownership. Existing shared,
borrowed or unrestricted values cannot acquire this authority. Source/header
context preserves qualifiers for declarations and pure local bindings; immutable
Core checks the input, result and every consuming edge independently. Runtime
sharing reuses normal retain/release and creates no second journal or ABI.
Captured collection storage is reconstructed before preserving its owning
qualifier; constant conversion receipts decline. Qualified guest entry headers
remain unsupported in that slice; the transfer continuation below admits owning
inputs. Source/dependency functions retain their full contracts.

The sharing continuation passes 37 native usage/resource laws and the sharing,
loan and reference resource guests in both tiers, including source/archive,
retained/restart, failed edits, once captures, zero roots/leases and flat warmed
memory. Complete source/Core and backend sweeps cover 159 and 446 faults. It
also repairs inherited returned-once header discovery without weakening Core
capture checks; mutation controls identify executable references through their
declaring binding. Broader usage and resource transfer contracts remain open.

The transfer continuation gives every unique/shared primitive or primitive
Array/List a counted eight-byte owning box. Its payload and optional cleanup
token remain separate; loan types still use their existing region owner.
`@resource.acquire` and `@resource.release` attach/consume the same checked
obligation across moves, sharing and once captures within one invocation.
Acquisition captures its two thunks, reserves journal capacity and allocates the
result carrier before calling the acquisition thunk. Registration independently
checks the live box, payload word and exact scalar/reference child mask before
one allocation-free journal/token commit. Acquiring an already registered owner
traps without replacing its obligation. Cleanup captures admit only closed data;
loans, scoped providers and hidden callable authority reject. Independently pure
transferred cleanup retains no ambient provider.

Only transfer modules use ABI 5 and the exact typed `blot:resource/2` imports.
Scope-only modules retain ABI 4; ordinary modules retain ABI 3 and no resource
journal hooks. Owning guest inputs of primitive scalars or numeric Arrays are
freshly boxed. Owning guest outputs remain unsupported: the host cannot observe
box pointers as scalar values or persist an acquired owner across guest calls.
Module values are immutable and startup has no Foreign invocation authority;
direct, shared and closure-hidden acquired startup values reject independently
at source and immutable Core boundaries.

Counted retirement checks flag 2048 and token offset 4, clears the token and
marks the existing journal record ready after child accounting. It never runs
cleanup inside RC or cycle destruction. Existing root scopes and outer merge
slots close block, branch and loop owners while preserving outgoing references.
Prepared source contracts and selected physical mappings identify owning bodies,
including generic shared substitutions. Safe points drain after complete heap
transactions and before observable host calls. Traps and JSPI rejection drain
before ownership leave and capability revocation; live weak boxes are
invalidated before cleanup. Attempts are taken before calling adapters, drop
always runs, newly retired captures are rescanned, and the first failure wins.

Focused transfer checks cover source/Core admission and startup mutants,
complete backend allocation failure/replay, generic shared calls, acquired ABI
rejection, malformed/stale weak boxes, duplicate and failed registration,
cleanup failures, outer-loan capture rejection, source/archive byte equality,
checkpoint restart, branch merges, break exits and 5000 sequential acquired
resources. Both codegen tiers and sync/JSPI execute 4608 repeated
success/failure/cancellation calls with zero roots/leases/host references and
flat warmed memory. Separate RC/cycle controls prove one retirement mark, stable
child counts and no hook in ordinary Wasm. These are focused results; the
combined compiler gate remains deferred. Tasks 061/062 remain in progress:
broader nominal affinity, explicit generic usage contracts, host cleanup
authority, longer-lived owner handles and checked resource-carrying request/task
frames remain open. Tasks 073/074 require those owned lifetime boundaries; no
concurrency acceptance is claimed.

### Synchronous host cleanup descriptors

A guest binds `cleanup ((unique T) -> Unit ! {Foreign})` with
`guest.cleanupCapability({ parameter, result: "Unit", maxSteps, maxCalls, call })`.
The source qualifier, immutable parameter role, ABI marker 7 and
`blot:cleanup/1` import agree independently. Ordinary `capability()` and
`capabilityAsync()` descriptors cannot satisfy this role. A cleanup import stays
synchronous in JSPI guests; a Promise or thenable is rejected after its attempt
has been consumed.

Both bounds are positive integers at most 65536. `maxSteps` is an explicit
trusted host completion promise; native host work cannot be measured or proved
by the compiler. `maxCalls` is enforced across each guest invocation, including
journal unwinding, and resets for the next invocation. Finite source adapter
work is reconstructed separately in source and immutable Core. Reaching the call
limit records a failed attempt and continues the remaining journal entries.

### Explicit finite pure cleanup literals

A standalone `cleanup ((unique T) -> Unit)` annotation is admitted only on a
finite literal implementation. Source checks global and local definitions;
immutable Core reconstructs the implementation from the owned global body or
local closure, including its parameter, published schemes and exact pure row.
Literal and nested range work uses the same charged cleanup bound. Unknown,
recursive and named adapter calls cannot grant cleanup authority. An ordinary
call can invoke a checked named cleanup definition without weakening its recipe.
Pure cleanup parameters remain rejected because an annotation alone does not
carry a caller-owned finite receipt.

An existential witness must remain unrestricted even when it is phantom and
absent from the package payload. Both source and immutable usage Core traverse
nominal affinity with a shared bounded budget. Lifting a nominal or opaque value
with an affine payload across a stage rejects before immutable snapshot work.
Explicit affine package interfaces remain a separately checked contract.

These continuations do not admit cross-invocation owning guest outputs or
payload and host ABI shapes without a closed checked representation. Broader
reference and public owner lifetime requirements remain open until their
normative laws and the combined compiler gate pass.

### Closed aggregate resource storage

Finite resource payloads and fresh unique/shared literal owners now include
nested products, records, Arrays and Lists of closed primitive storage. A single
charged traversal checks every type edge and rejects hidden callable, provider,
loan and nested qualifier authority. Immutable Core also compares actual literal
children against the declared payload and checks record destinations before an
owning carrier can be published. Counted reference child roles retain the entire
payload graph; the existing reference cleanup adapter releases it after taking
one registered cleanup attempt. No raw managed pointer becomes a host value.
Nominal constructor substitution, structural host descriptors and public owner
lifetime promotion require their own evidence and remain separate work.

### Nominal usage authority

`Nominal.affine` controls moves; the separately reconstructed `has_usage` fact
controls hidden lifetime authority. A nominal containing a shared owner remains
repeatable and still cannot be lifted or hidden by an unrestricted existential
witness. Source and immutable Core derive both least fixed points from owned
constructor payloads under the same charged work budget. Imported definitions
require the exact producer's two facts; portable interfaces and body cache keys
preserve them. An affine fact without the usage fact or an erased feature marker
rejects. This closes repeatable-owner erasure without treating shared data as a
unique owner.

### Conditional nominal resource storage

Concrete data and opaque families can carry closed resource payloads when every
constructor stores closed data under the family's owned data parameters. Each
concrete argument must itself be closed. This optional `closed_storage` fact is
independent of affine and repeatable lifetime facts; a family with hidden usage
cannot claim it. Recursive pure data uses a bounded greatest fixed point.
Ordinary typing does not depend on obtaining this optional authority.

Portable admission reconstructs the claim from constructor payloads, matches
owned generic parameters against actual constructor operands, and checks opaque
machine storage roles from concrete leaves. A stale producer claim, malformed
catalog, forged role, callable payload or hidden owner cannot grant resource
admission. Fresh constructor expressions can satisfy an explicitly contextual
owning type; an existing ordinary value cannot become unique by annotation.
Executed tests cover generic boxes, recursive trees and opaque records across
source imports, dependency archives, retained edits and server recovery. Public
persistent owners and structural host ABI descriptors remain outstanding.

### Public once invocation authority

A public once callable keeps its exact source multiplicity at the export
boundary. Its private Wasm guard consumes the callable before its first body
invocation; a trap, host rejection or pending JSPI suspension cannot restore it.
A second raw export invocation traps before resetting any active descriptor. The
optional version-1 `blot:multiplicity` section names exactly the once function
exports. The guest validates that metadata and reports `once_reused` after an
invocation attempt. Argument validation failure before invocation does not
consume the callable. Ordinary many exports emit no new metadata or guard.

### Public persistent owners and owned cleanup descriptors

The public owner continuation supersedes the owning-output rejection recorded in
the earlier invocation-only qualifications. ABI 6 publishes `unique T` or
`shared T` results as opaque instance-bound `GuestOwner` handles. `T` must
satisfy the independently reconstructed closed-storage contract: primitives,
products, records, Array/List and producer-owned nominal/opaque data, including
substituted and recursive families. Loans, providers, demands, nested usage and
callable payloads cannot acquire authority through this boundary.

Private typed leases retain a real counted owner edge outside invocation frames.
They carry an exact payload layout and usage kind, monotonic nonreused IDs and a
4,096 live-handle limit. Public entries accept scalar IDs, never managed heap
pointers. Unique pass-back consumes the old handle; shared inputs preserve it.
`guest.releaseOwner(handle)` consumes either host handle, and guest disposal
deterministically drains remaining registered attempts before releasing roots.
Source `@usage.share` remains the only unique-to-shared conversion. Existing
primitive/numeric-Array inputs also accept fresh copied values. Modules that
produce no public owners retain their invocation ABI. Where public owners can be
produced, the alternate lease bridge shares the public once guard with the
fresh-input bridge.

The guest validates owner metadata and independently links the exact hook and
entry signatures. A typed journal promotion follows successful native lease and
host handle publication. Failed publication releases the native edge; failed
cleanup consumes the attempt and continues draining. Foreign, forged, stale,
wrong-layout and moved handles reject. Pending JSPI blocks reentry, release and
disposal until settlement.

A module exporting owners binds synchronous cleanup through the distinct
`blot:cleanup/2` role and `blot:cleanup_bind/1` binder. Both Wasm signatures are
independently exact; the ABI parameter uses marker 10. Resource registrations
retain each binding until its cleanup/drop attempt, including across host calls.
The checked immutable cleanup role is preserved; ordinary Foreign and Promise
descriptors gain no persistent cleanup authority. `maxSteps` remains a trusted
host completion promise; `maxCalls` is charged per owned descriptor during each
release/disposal invocation. Invocation-only modules retain their old callback
role, and modules without this feature allocate no owned binding table. The
retained host-function request key includes lifetime, so adding/removing a
public owner result cannot reuse a callback with the wrong lifetime role.

Focused qualification covers source/archive/checkpoint/restart equality, both
compiler tiers, sync/JSPI, raw Wasm duplicate/forged leases, once bridge
sharing, opaque/recursive/reference payloads, shared last-owner cleanup, host
and publication failures, disposal, exact import mutants, complete backend
replay and allocation failures, and flat warmed memory. Structural host payload
descriptors and the combined compiler gate remain separate requirements.

### Closed data host cleanup descriptors

ABI 7 extends synchronous cleanup to closed product/record, Array/List and
producer-owned nominal payloads. `guest.cleanupDataType(exportName)` returns an
instance-bound type witness for an entry's checked cleanup parameter.
`guest.cleanupDataCapability({ type, maxSteps, maxCalls, call })` binds the same
finite synchronous completion promise and invocation bound as scalar cleanup.
The source syntax remains `cleanup ((unique T) -> Unit ! {Foreign})`; ordinary
Foreign callbacks and Promise descriptors gain no data cleanup authority.

A canonical bounded schema records exact physical fields, collection row widths
and leaf layout, constructor payload substitutions and producer-owned opaque
representation facts. Source and immutable Core independently retain the cleanup
role and closed-storage authority. One charged schema budget covers graph edges,
producer catalogues, formal selectors and field comparisons; schemas are capped
at 4096 nodes and 128 levels. The retained host stub rebuilds after
representation import so a prior layout pool's schema ID cannot gain current
authority.

The distinct `blot:cleanup_data/1` and `/2` imports carry the exact schema ID
and payload word. Their synchronous binder and actual Wasm signatures are linked
independently. The guest checks the schema against its active or retained
cleanup descriptor, then copies bounded data using the declared physical
representation. Dynamic block liveness, field reference masks, collection
bounds, variants and cycles are checked; host code receives no managed pointer
or mutable guest alias. Products and Lists become frozen arrays, records become
frozen objects, numeric Arrays remain detached typed-array copies, and public
data variants carry their family, tag and copied payload. Opaque/private
families become opaque witnesses without exposing their producer's
representation. Source qualifiers or hidden resource/loan/provider/callable
facts cannot be smuggled through these schemas.

Structured callbacks preserve their owned binding and original journal token
when a resource crosses invocation boundaries. Explicit release, last shared
drop, disposal and failure use the same single-attempt journal as scalar data.
Host metadata is snapshotted before validation, including accessor-backed
bounds. Modules without structured cleanup retain their existing ABI and data
layout.

Focused checks include full replay and every failed allocation, exact namespace/
schema/signature mutants, actual heap-slot and missing-edge controls, copied
records/products and packed rows, multi-leaf/nested Lists, recursive public
data, opaque witnesses, source/archive/checkpoint/restart equality, failure and
late cleanup, both tiers and sync/JSPI, and flat warmed memory. The combined
root gate and full package/generic region qualification remain required.

### Explicit affine universal identity, 15 October 2026

The annotated contract `forall [a] => unique a -> unique a` already transports
an acquired owner correctly. A new executed law moves a resource through an
imported identity, borrows its result and releases it; using the old binding
rejects with `use_after_move`. Both tiers pass source/archive byte parity,
checkpoint preservation/restart, input edits/revert, host-failure recovery and
actual JSPI suspension while the moved owner lives. Warmed memory is flat. No
production correction was needed. Two root groups and TypeScript/lint/format
pass. Pins and exact test delta:
`build/bench/complete-program-20261015/affine-forall/`. This qualifies the
explicit contract omitted by the earlier generic-shared screen; it does not
supply usage evidence to an unannotated unknown callee. The final combined gate
remains required.
