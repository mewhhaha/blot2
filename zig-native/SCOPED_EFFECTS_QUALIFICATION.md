# Direct scoped effect qualification

This is an implementation slice of [the reviewed design](SCOPED_EFFECTS.md).
Tasks058 and059 remain open. No milestone commit or full compiler gate is
claimed here.

## Supported boundary

Direct `@effect.scope (fn (capability: Family Arguments) => body)` creates fresh
authority on every guest entry. Member operations, local aliases, capturing
local thunks and ordinary providers preserve the exact owner. Nested same-typed
State capabilities return `[11,102,10,100]`; callback forwarding returns119 and
reinstalling one capability shadows its own installation. Scoped request clauses
carry an exact operation selector and a separate counted authority edge; two
same-family owners route to distinct clauses, while aliases of one owner reject
duplicate clauses. Unhandled owners forward to their outer provider.

Checked/frozen operation keys retain declaration, family arguments and a lexical
scope binder. Runtime descriptors remain static; the activation owner is a
separate counted edge retained by operation closures and installations. State
cells remain separate. Frozen validation checks binder ownership, member
references and exact request selector/label correspondence. Runtime invocation
checks active permission before provider lookup.

Each owner registers a dedicated activation journal record before exposure.
Normal cleanup revokes before its private storage retires; trap/JSPI rejection
revokes invocation owners before closing frames. Retained aliases preserve
identity without preserving permission. Native handles never recycle, and
exhaustion fails. The journal is separate from demand-force records.

Fresh scope execution declines ordinary constant evaluation. Emission declines
fragment reuse for the owning job. Capability layouts cannot become closed
semantic value evidence. Scoped semantic receipts decline import; checkpoints
may retain validated symbolic binders and executable code, which creates fresh
owners when run. No live authority enters an evaluator snapshot or archive.

## Conservative limits

Only direct callbacks with explicit family annotations are admitted. Symbolic
family payload arguments substitute through generic scope factories, including
separately compiled factories. A structural result may retain the same unsolved
payload variables: those shapes originate outside the fresh owner. The result
footprint compares the exiting binder exactly. A longer-lived outer capability
may cross an inner boundary through structural data; that inner capability still
rejects. Dotted member selection preserves the complete checked projection path,
including operation aliases. Array reads borrow their input; writes retain
conservative sink checks. Fresh capabilities and known opaque results still
reject. A directly returned source closure has a bounded footprint walk over
resolved bindings and exact operation aliases: no captures, primitive captures
and longer-lived authority may return; an exiting-owner capture still rejects
even when its operation is handled and its row is pure. Unknown callable/opaque
captures and unsupported source forms retain a conservative error. Generic
capability parameters/capture contracts, branch-selected identities, written
capability rows remain unsupported. State read/write pairs from different owners
reject rather than losing an owner edge.

Anonymous callback adapters whose whole body invokes their parameter may borrow
operations/capturing closures when the callback returns structural data. This
proof stays within the requesting expression; a named/imported helper still
requires an owned capture/store contract. Sync/JSPI callbacks retain permission
until completion and revoke on rejection.

Primitive and structural data may return. Apart from inherited symbolic payload
variables and proven direct source closures, callable, demand, provider, nominal
and unresolved results or transferred arguments reject conservatively, including
pure handled closures and longer-lived builtin State writes. Associated dispatch
arguments use the same guard. This also rejects some authority-free values and
legal storage/callback flows. Precise footprints, opaque/generic/compiled store
contracts, origin traces and the complete059 acceptance matrix remain open.
Structural escape checking is bounded at128 depth and65536 visits per query.

## Validation

Zig0.17.0, Safe/noLLVM, CPU4 for development:

- Focused `zig build test` filters: `scoped effect`, `effect authority` and
  `scoped provider keys`; passing allocation-failure laws cover checking,
  lowering, emission, exact evidence imports and authority/frame publication.
- Frozen evidence rejects missing or substituted scope binders and absent or
  substituted request selectors. Request checking/lowering/emission have
  allocation-failure coverage. Generic payload checking/lowering/emission and
  static-operation storage rejection also have allocation-failure laws.
- Executed controls:23 groups across direct scopes, scoped requests, the
  authority journal, symbolic rows, generic scope factories and storage
  diagnostics pass, including both codegen tiers, sync/JSPI, suspension,
  rejection, trap recovery, aliases, forwarding, source/compiled effect
  declarations, retained edits, failed edits and checkpoint byte parity. Scoped
  request groups also cover cancellation, a demand retry that recreates scope
  authority, provider forwarding and host suspension/rejection inside a clause.
  Generic factories cover U32/F32 scalars and arrays through source/compiled
  declarations, retained specialization edits and checkpoint parity. Static
  generic operation calls enforce the same transfer guard as ordinary calls; a
  capturing pure closure passed through such an operation to longer-lived State
  rejects in both source and compiled consumers. Two direct callback adapter
  groups cover borrowed operations/closures, sync/JSPI, rejection/recovery and
  checkpoints. Two structural lifetime groups prove record/array forwarding of
  longer-lived authority after inner revocation and rejected-edit rollback.
  Projection lowering/emission, checker and allocation-failure laws cover the
  same boundary. Two returned-closure groups cover primitive captures and
  operation aliases across inner revocation. A same-header edit adding a handled
  authority capture rejects without changing the prior checkpoint. Native
  checker/lowering/emission allocation-failure laws cover the returned-closure
  proof.
- The lifecycle fixture proves retained identity is inactive before teardown on
  success and failure, with zero journal roots and leases.
- Zig analyzer:369 files, zero findings.

The full LLVM/compiler gate belongs to the combined qualification. This slice
was developed against staged source tree
`c2b1b545ffa6877affc9e34b9825e1e2ab158680`; unrelated joint-batch repairs and
costs are separate.

## Measurement

CPU6, Safe/noLLVM compiler, seven alternating fresh compiler pairs and31 warmed
guest pairs,2048 calls per guest sample. Both programs return the same four
numeric values. The static control uses two distinct declared families; the
scoped program uses two fresh owners of one family.

| Measurement                                        | Control median | Candidate median | Median paired ratio |
| -------------------------------------------------- | -------------: | ---------------: | ------------------: |
| Static compiler, source baseline versus this slice |       19.311ms |         19.413ms |              1.0105 |
| Candidate compiler, static versus scoped program   |       19.461ms |         21.229ms |              1.0917 |
| Candidate guest, static versus scoped program      |   1.158µs/call |     1.682µs/call |              1.5084 |

Compiler samples include process loading and fresh checking/emission. Retained
and restart behavior is verified separately; these are not retained-edit
timings. Guest overhead includes both fresh owners, callbacks, exact routing,
journals and cleanup. It is about0.52µs per call on this small workload. A
direct-member shortcut removes transient operation closures created solely to
recover the provider owner; an earlier run measured1.744µs for the scoped guest.

Raw inputs, binaries, Wasm hashes, samples and distributions are recorded in
`build/bench/scoped-058/results.json` (SHA-256
`0550e1bbd7f4f174fce1736adddaac0e01dc1ff8f7a9ac9967e1571d4600275a`). The
measured candidate compiler SHA-256 is
`8d6171e91d1b113e6b6f2a490cb89f2c579b896064a974feab7c7e25bd917e20`. These
numbers qualify the earlier direct source slice, not a merged release compiler.
The later scoped-request, symbolic-factory and transfer-guard extensions have
separate source/binary pins; no additional CPU claim is made.

## Merged checkpoint, 13 October 2026

Local `10fab46` qualifies this admitted slice with 1,624 native laws, 1,030
executed guests, 977 exhaustive failure sweeps and zero analyzer findings across
373 files. [Merged qualification](CONTINUATION_QUALIFICATION.md) records the
exact source/binary pins, measured costs and still-open scope. Isolated clocks
above remain separate from the final combined release measurements.

## Owned public flow boundary

Public principal interfaces and immutable Core now own two small footprint
relationships for a single input binder: identity returns binder0; invoke_unit
invokes binder0 with Unit and returns its result. Their bodies have no capture
or storage sink. Source producers infer only exact direct forms; frozen Core
validation checks the body against the claim, and module abstraction validation
requires the public and implementation claims to match. The portable structural
schema digest includes this field. Source/compiled catalogs and retained body
interface digests preserve it; execution owner handles remain guest local.

The two executed public-flow groups cover U32/F32 capabilities, captured
callbacks, sync/JSPI, rejection recovery, source/compiled dependencies,
checkpoints, an escaping identity result, and a retained helper edit that loses
its flow proof while preserving its ordinary a -> a header. Native body-forgery
and checking, lowering/emission allocation-failure laws cover the same boundary.
Twenty-one focused scoped guest groups pass. No full combined gate or additional
CPU claim is made here.

This boundary does not complete general symbolic capability parameters,
dependent arrows, selected capability terms, or arbitrary hidden capture/store
contracts. Unknown helpers and opaque callable results continue to reject
conservatively.

## Quantified capability parameter boundary

An ordinary explicit effect-family parameter owns a quantified identity-variable
edge separately from its family payload. Schemes freshen that edge with the
parameter's operation rows; checking constrains it to the argument's identity.
Function result annotations can name the parameter operation, for example
`fn (state: State a) -> a ! {state.get} => state.get ()`. Exact Unit member
invocation has a public no-capture/no-store claim, validated against immutable
Core and its selected parameter. Other helpers remain conservative.

Principal/Core projection and import copy identity edges into each receiving
owner. Code specialization keys include the checked first capability input's
lexical instance; that owned fact seeds semantic inference independently of
physical layouts. Unresolved instances cannot become closed row evidence, and
ambiguous row-only instance inference declines. These projections publish no
semantic cache receipt. Named fragment import declines until a binder relocation
proof exists. The implementation serializes neither a live authority handle nor
active permission.

Two executed groups cover separate same-typed State owners, U32/F32 payloads,
written parameter rows, source/compiled imports, sync/JSPI, rejection recovery,
retained edits, revert, checkpoint byte parity, and a same-header helper edit
that loses its flow claim. The focused regression batch has32 executed groups.
Native allocation-failure laws cover identity freshening, precise repeated rows,
rollback rerouting, owned principal copying, worklist wakeups,
checking/lowering/ emission, and storage rejection. Frozen validation rejects
substituted binder edges and body claims; closed evidence rejects unresolved
instances. Solver regressions and the analyzer pass. No combined gate or new CPU
claim is made.

Complete dependent arrows, selections, general callback/capture contracts, and
precise same-lifetime State stores remain open in058/059.

## Curried callback boundary

The exact helper
`fn (state: State a) => fn (callback: Unit -> a ! {state.get | e}) => callback ()`
owns a two-binder invocation claim. Immutable Core validation checks its exact
Unit invocation and callback binder; source and compiled interfaces preserve
that claim. Named, inline and demand specialization seed the first capability's
identity before matching callback rows. Extra callback effects retain their
owners; an unhandled exiting owner produces `capability_escape`. Partially
applying an identity helper does not license later arguments to an unknown sink.

Two executed groups exercise separate same-family owners, U32/F32 payloads,
source/compiled imports, sync/JSPI/rejection recovery, retained edits,
checkpoint parity, unmatched callback requirements and rollback after proof
loss. Native checking/lowering/emission allocation-failure laws and forged-claim
validation cover this boundary. General dependent arrows, selections, hidden
capture/store contracts and precise same-lifetime stores remain open. This slice
makes no additional CPU claim or full combined qualification claim.

## Local State lifetime boundary

A direct source closure may be stored in the nearest trusted `@effect.state`
cell when that installation lies within every captured capability's lifetime.
The checker retains a bounded scope-lifetime stack and exact handler keys;
ordinary providers shadow the storage proof. Lambda bodies do not inherit
construction-time frames. Unknown callable captures, opaque sinks and hidden
generic storage contracts remain conservative. Scope exit still rejects a
returned stored closure or aggregate containing one.

Two executed groups cover source/compiled imported declarations, stored captures
across JSPI suspension, rejection recovery, checkpoint parity, older cells,
ordinary providers and returned state negatives. Native laws cover handler
shadowing, construction-time frame rejection and checking/lowering/emission
allocation failure. The focused batch passes36 executed groups and all8
unchanged compile budgets; the analyzer reports369 files and zero findings.
Fixed-path fanout128 requests16,136,290 bytes in 53,920 allocations with exactly
equal work counters before and after this slice. Full combined qualification and
CPU measurement remain separate.

## Complete arrow binder boundary

Complete annotations can bind one effect-family capability input and refer to
its operations in subsequent arrow/result annotations. Binder AST nodes retain
that value-name relationship separately from type variables. Annotation checking
owns the quantified identity edge and limits the value environment to that
annotation; plain implementation lambdas receive those contextual input types.
Exact member and curried Unit-invocation flow claims retain their existing
immutable Core validation. Implementation parameter names may differ from
annotation binders.

Curried results use explicit grouping, for example
`(state: State a) -> ((Unit -> a ! {state.get | e}) -> a ! {state.get | e})`.
This preserves ordinary arrow-row placement and keeps capability application
pure. The durable design example now uses this spelling. Source
frontend/formatter and native parser agree on binder syntax; generated artifacts
come from the grammar.

The existing curried execution matrix now runs both parameter and
complete-header forms through source/compiled imports, U32/F32, two same-family
owners, sync/JSPI, rejection recovery, edits, checkpoints, unmatched rows and
proof-loss rollback. Native checking/lowering/emission allocation-failure laws
cover complete binders, their annotation scope and hidden storage rejection.
Multiple capability inputs, selected identities, general hidden capture/store
contracts and arbitrary opaque footprints remain open. This is a focused
boundary, not full058/059 completion.

Final controls pass38 executed guest groups,8 unchanged compile budgets and19
source frontend/formatter groups. Native scoped and complete-arrow laws include
allocation-failure recovery;369 analyzer files have zero findings. Fresh Safe/
noLLVM controls with isolated equal-length restart-cache directories request
exactly16,136,392 bytes in 53,920 allocations with18,504 type nodes and equal
work counters before and after this slice. A restored CLI checkpoint must not be
compared with a fresh run; an early mixed-state comparison was discarded.

Tree-sitter's existing permissive annotation grammar needs no production change.
The named-binder corpus and highlight controls pass with pinned upstream CLI
v0.27.1:7 corpus parses and15 highlight fixtures, including5 new assertions. The
official release archive SHA-256 is
`d01042f94ba3d6827ddc9788e235f75d8366431be42bdf90ade534d960c98b7d`; the
installed executable SHA-256 is
`6de5f5c0f6d2e281ad2643d3874b66cf240fa77140c5346b670889483982b0c7`. Full
combined qualification and CPU measurement remain separate.

## Ordered capability input boundary

Fully applied two-input member helpers preserve both arguments' instance terms
in parameter order. Exact first/second Unit-member flow claims are checked
against owned Core bodies, including the selected parameter binding and both
scoped input types. Implementation shadowing selects the inner binder. Source
and compiled interfaces carry the same claim; unknown bodies cannot borrow
authority merely because their ordinary headers match.

Specialization keys refer to an owned instance-argument pool. Ordered, swapped
and repeated terms remain distinct. Ordinary function keys use zero and create
no pool storage. Published backend metadata copies the pool and survives
producer mutation and teardown. Scoped executable imports still decline until
their binder terms can be relocated; no guest authority enters portable
metadata.

Four executed matrix groups cover parameter and complete-header forms in both
codegen tiers, source/compiled imports, same-family owners, swapped/repeated
inputs, shadowing, mixed U32/F32 payloads, sync/JSPI, rejection recovery,
checkpoints, edits and proof-loss/unhandled-owner rollback. Native checking,
lowering, emission, ordered interning and complete snapshot
publication/replacement laws include allocation failure. The focused batch
passes34 scoped guest groups and all 8 unchanged compile budgets;370 analyzer
files report zero findings. The activation fixture prerequisite was generated
and its revocation law then passed.

With identical source/prelude bytes and fresh equal-length cache paths, ordinary
fanout128 requests16,104,454 bytes in 53,920 allocations, versus16,136,398 bytes
in the previous slice. Type nodes remain18,504. All inference/solver counters
remain equal; metadata copied bytes fall360 because ordinary specialization keys
shrink. These are allocation controls, not a CPU or full combined qualification
claim.

Remaining058/059 boundaries are owned value-flow identity terms for selections
and aliases; general parameter/capture/result/store footprints across
aggregates, demands, providers and computations; fresh invocation binder
substitution through generative/captured generic calls; opaque/associated
boundaries carrying those footprints; and generic storage/lifetime contracts
with exact row subtraction. Arbitrary multi-input bodies remain conservative.
Neither task is complete.

The combined `ae001bb` checkpoint passes the complete native/guest/OOM gate and
release comparisons. See [merged qualification](CONTINUATION_QUALIFICATION.md)
for exact pins, the repaired revert regression and final measurements. Later
prototypes remain separate.

## Local selected identity boundary

An `if` in the active fresh-scope callback may select two same-family capability
values. The owned selection term carries its source atom and both origin edges.
Aliases preserve this exact term; handling it subtracts only its operations.
Another selection or an original root retains its own requirements. Escape,
residual-row and storage checks inspect both possible lifetimes. Nested ordinary
callbacks and loops cannot create a selection, and a selection must reach the
current fresh owner. Public generative selection schemes remain unsupported.

Payload substitution keeps the same owner term. A reduced symbolic factory first
exposed an exact Core operation/capability edge mismatch at dependency
validation: full payload graph comparison incorrectly gave a resolved copy a new
selection identity. Interning now compares the exact ordered owner terms, while
each scoped value retains its own payload descriptor. The native artifact law
covers encoding, decoding, relocation and exact Core validation under allocation
failure. The original failed fixture and logs are preserved outside the source
tree.

Four executed matrix groups cover parameter and complete-header helpers in both
codegen tiers, source and compiled imports, symbolic factories, concrete U32/F32
payloads, generic identity aliases, independent roots/selections, sync and JSPI,
rejection recovery, retained edits/reverts and byte-exact checkpoint rollback.
Native checking, lowering, emission, type normalization and worklist traversal
include allocation-failure laws; corrupted selection cycles reject. The selected
matrix and eight unchanged compile budgets pass. This is a focused boundary;
root owns full combined compiler qualification.

General multi-input bodies, fresh invocation substitution for public generative
selection schemes, aggregate/capture/result/store contracts across demands,
providers and computations, opaque/associated footprint transport and generic
storage/lifetime contracts remain open. Neither 058 nor 059 is complete.

Final analyzer control checks 370 files with zero findings. Identical pinned
fanout/prelude inputs and fresh equal-length restart-cache paths request exactly
16,104,444 bytes in 53,920 allocations before and after this slice, with 18,504
type nodes and identical work counters. This establishes ordinary allocation
parity; CPU and combined retained qualification belong to the root gate.

The selected-identity boundary is merged in `121eb59`: the full combined gate
passes 1,688 native laws, 1,066 guest/client tests, 1,036 complete OOM sweeps
plus two expected-error harness laws, and zero findings across 375 analyzer
files. Seven captured-project pairs and thirteen public programs retain output
parity and near-parity compiler CPU. Exact source/binary pins and measurements
are in [merged qualification](CONTINUATION_QUALIFICATION.md). Later parameter
footprints remain isolated and unqualified.

## Owned parameter product footprints

Pure named constructors of nested products carry an owned formal-input summary:
up to 16 inputs and the exact mask of inputs retained in the result. Scalar
constants contribute no input. Source classification and frozen Core validation
both reject captures, calls, stores or unproved body nodes; Core references must
select the declared parameter bindings. Inner binders preserve ordinary
shadowing. This is a separate relationship from data type variables and effect
rows.

Checked/source/principal/Core bindings and immutable interface snapshots carry
the summary by value. Body-reuse evidence hashes its explicit domain marker,
arity and mask; absent summaries preserve prior digests. Dependency admission
compares the public claim with the exact private Core body. Interface-only and
coordinated interface/Core forgeries reject. Pure product helpers can combine
live capabilities inside their scopes or discard a younger input while returning
an older input; publishing a retained younger owner still rejects. Unknown
helper bodies continue to decline authority transfers.

Two executed groups cover both codegen tiers, source/compiled helpers, repeated
and reordered owners, nested products, mixed U32/F32 inputs, shadowing, precise
nested lifetimes, sync/JSPI rejection recovery, edits/reverts, checkpoint
restore and proof-loss rollback. Native checking, lowering, emission and
artifact encode/decode/admission laws include allocation failure and corrupted
input masks.

Measured representation cost is explicit: most binding records grow 4 bytes and
SchemeInterface grows 8, while the captured body-cache binding remains 88 bytes.
An attempted 3-byte encoding produces the same actual layouts and was removed.
With pinned identical ordinary fanout/prelude inputs and isolated fresh caches,
requested bytes grow 18,760 with no extra allocations, types or solver work. All
eight existing compilation budgets remain unchanged and pass. Root owns combined
release/retained qualification; neither 058 nor 059 is complete.

Final focused controls pass the product and selection guests plus all 8
unchanged budgets (14 groups), scoped native laws, artifact/OOM laws and 370
analyzer files with zero findings. Pinned ordinary fanout requests 16,104,450
bytes before and 16,123,210 after, in 53,920 allocations with identical
type/work counters. No new grammar is introduced; this boundary uses existing
lambda/product syntax. General value-owner recipes, nonstructural captures and
generative public schemes remain separate work.

Root merged this boundary as `5378347` after the complete frozen gate: 1,693
native, 1,068 guest/client, 1,040 complete OOM sweeps plus two expected-error
laws, and 375 analyzer files with zero findings. Captured CPU ratios against
`121eb59` are 1.0047/1.0073/1.0002, with exact Wasm/fuel. Public requested bytes
increase 10,448–19,228 and peak 4,412–8,092. See the
[combined qualification](CONTINUATION_QUALIFICATION.md) for all pins and costs.
The standalone maximum-binder/mask test lacked suite registration; it was not
covered by its earlier empty focused filter. Checker/emitter/artifact laws did
execute. Its separately tested registration amendment is queued for the next
invocation batch; no source is changed after the frozen gate.

## Multi-input Unit invocation footprints

The owned formal summary also proves one direct Unit invocation of a selected
input. It records that input's ordinal, preserves ordinary shadowing and ignores
unused inputs. Source classification and frozen Core admission require the exact
callable reference and Unit argument; captures, stores and intermediate calls do
not acquire this contract. Existing single/two-input contracts retain their
ordinary representation and hashes.

Generic scoped callback rows may recover erased payload arguments only from an
already bound exact owner and matching operation evidence. Wrong owners, unbound
owners and contradictory payloads decline. Repeated written labels keep their
multiplicity: two providers discharge two occurrences of one owner; one provider
leaves a residual row and rejects escape.

Four executed groups cover parameter and complete-arrow syntax, both codegen
tiers, source/compiled imports, reordered/repeated owners, callback-first and
shadowed ordinals, U32/F32 payloads, sync/JSPI rejection recovery, proof loss,
checkpoint restore and retained edits/reverts. Alongside product/selection/pair
controls and unchanged budgets, all 22 guest groups pass. Registered native laws
cover checking, lowering, emission, exact-owner inference and artifact admission
with allocation failure and corrupted callback masks/kinds. The maximum-16
domain law is now explicitly imported into the suite; its earlier unregistered
filter was not coverage. Analyzer checks 370 files with zero findings.

The invocation kind occupies existing padding. Identical pinned ordinary
fanout/prelude inputs and fresh equal-length cache paths request 16,123,214
bytes in 53,920 allocations before/after, with identical peak bytes, type/work
counters and Wasm. Root owns combined release/retained qualification. General
value-owner graphs, result/capture/store recipes,
demands/providers/computations, public generative selection schemes and
opaque/associated contracts remain open; neither 058 nor 059 is complete.

## Named record constructor footprints

The same formal-retention proof now covers pure record constructors, including
shorthand fields and nested mixtures of records/products. Source field values
must be exact formals or scalar constants; decoded Core proves the same retained
parameter mask. No new field, type tag or allocation owner is introduced.
Nominal constructors, intermediate calls, captures and stores remain unproved.

The shared aggregate matrix adds two record groups rather than duplicating its
test harness. Source/compiled imports, both tiers, repeated/reordered fields,
shadowing, precise younger-owner omission, U32/F32, JSPI rejection recovery,
edits/reverts and checkpoint/proof-loss rollback pass. All 24 focused guest
groups and unchanged budgets pass. Three registered native laws cover checking,
lowering/emission and frozen admission with OOM and forged retained-field masks.
Analyzer checks 370 files with zero findings.

Identical pinned ordinary fanout/prelude inputs and fresh equal-length cache
roots request 16,123,204 bytes in 53,920 allocations before/after, with
identical peak bytes, type/work counters and Wasm. The initial measurement could
not execute its copied baseline binary because executable permissions were
missing; that run is preserved as incomplete, and the corrected comparison uses
new fresh caches. Root owns combined qualification. The general boundaries
listed above remain open; this is an aggregate relationship, not a general
capture/store contract.

Root merged invocation and record footprints as `0d77afc` after the complete
combined gate: 1,701 native, 1,075 guest/client, 1,050 complete OOM sweeps plus
two expected-error harness laws, and 375 analyzer files with zero findings. The
maximum-16 footprint domain law is now registered. Captured paired CPU ratios
against `5378347` are 1.0049/1.0074/1.0051; public allocations and all Wasm
controls are unchanged. Exact pins and the accompanying window change are in
[combined qualification](CONTINUATION_QUALIFICATION.md). Later member-closure
capture work is separate; tasks 058/059 remain open.
