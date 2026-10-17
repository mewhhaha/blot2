# Approved constant receipts

The owner approved this design and requested implementation on 12 October 2026.
Task 086 is in progress. Primitive constant-slot receipts are qualified on main;
broader constant authority and whole-task qualification remain pending.

## Historical attribution before the current continuation

The current captured game has 93 units. At qualified implementation `2798ff9`,
an LLVM release profile of a retained scalar edit reports 51–53 ms in constant
work, 19 ms in value evaluation and 545–549 ms in inference. These phase clocks
are separate; they do not attribute all inference to constants.

A separate Fast/no-LLVM attribution build records 872 first constant visits per
real revision, including 662 value constants. One declaration accounts for
57,019 of the unchanged 70,330 total source steps and dominates the inclusive
constant clock. Four edit/revert phases retain exactly those counts. All six
fresh/no-op/edit/revert outputs match the ordinary release's Wasm and source
steps. This slower instrumentation build identifies work; its clocks do not
establish a release speedup. Raw pins and records are under ignored
`build/bench/constant-receipts/`.

## Publication authority

Add a dedicated owned constant receipt. Keep the existing source value-template
transport contract unchanged: transporting a representation alone grants no
constant-slot or callable proof.

A receipt records one successful ordinary constant evaluation: original
producer/declaration identity, exact initializer, published principal interface,
complete value graph, actual value/source/interface/provider reads, evaluation
options and source fuel. It records executed call judgments separately from
unapplied function values. It holds no AST, solver, prior Session pointer or
mutable owner.

An unapplied named closure may link to the current declaration under equal
identity, signature, rows and captures. That link grants no proof of its body:
later specialization and emission validate the current body through their
ordinary gates. A call executed during constant evaluation instead records its
body and transitive observations. A body edit cannot reuse that result.

Before publishing a hit, validate every recorded observation against the new
revision and reconstruct its graph into the current owner. Reuse shared current
constant anchors only after those constants have reached their ordinary ready
state. Remap all identities, captures and type/row evidence; never copy old
callable certificates or raw guest addresses. Serialize static data through the
current allocator and relocation path.

Debit exactly the recorded source fuel at the original evaluation position.
Nested reads need a fuel tape so already completed constants are not charged
twice and newly demanded constants keep ordinary order. A different limit or an
insufficient remaining budget declines the hit and takes ordinary evaluation,
preserving the failure location. Copy/proof work has its own bounded budget.

Reserve all publication capacity first. The final slot transition allocates
nothing. Failed validation, OOM and rejected revisions publish neither a partial
slot nor a new committed receipt owner. Preserve the previous revision.

## Initial admission and required checks

Admit only complete, successful immutable outcomes with complete read and fuel
tapes. Unknown observations, effects, providers, demands, generative state,
cycles, failures and exhausted proofs take ordinary evaluation until a separate
exact reconstruction law supports them. This is an initial scope, not task 086
completion for unsupported constant forms.

Required laws cover unrelated edits, changed actual reads and called bodies,
unapplied function body edits, shadowing/renaming and producer relocation,
provider/generative fallback, evaluation order, tight fuel limits, diagnostics,
failed-edit recovery, complete OOM sweeps and fresh/retained/restart byte
parity. Measure receipt traffic, retained live memory and total release CPU
against an ordinary no-receipt control. Keep a receipt only when validation and
copying pay for themselves. The final compiler/analyzer gate and task 086's full
coverage remain required.

## Initial implementation boundary

The dedicated artifact owner retains successful non-function constants with at
least 64 ordinary source steps. Each tape separates local work from nested reads
and records source/call depth plus temporary value and child allocation debt.
Primitive scalar outcomes use an identity-free transport path; they do not index
the old temporary value graph. Primitive collections require at least four
source steps per output child, so copying raw literal collections keeps ordinary
evaluation. Statically literal scalar collections skip recorder installation
before evaluation, avoiding rejected-class recording and cache-walk overhead.
Replay requires already-ready, graph-equal current read anchors; it never forces
a speculative dependency. Capacity and all graph/evidence imports precede the
allocation-free slot transition. Replayed temporary allocation debt preserves
later ordinary value/child limits without retaining dead temporary graphs.

Initializer/call projections and complete Core validation remain authoritative.
A constant-only gate accepts a bounded duplicate tail of primitive or
primitive-element Array/List/Cursor types. Shared type IDs, rows, extra words,
operations and declaration catalogs remain exact. A changed ordinal in source
metadata requires an independently equal closed container shape; value evidence
is reconstructed in current storage. Principal and executable gates retain their
ordinary exact-catalog policy.

Inference observations during value work (including warm cache queries),
cumulative canonical/lexical/summary budget changes, collection growth,
optimized indexed/ragged builders, demands, effects/providers and generative
operations decline recording immediately. Dropping the recorder restores
ordinary inference scheduling and collection; unsupported constants do not
disable its existing reuse paths. Arbitrary type/producer relocation, unapplied
closure links, serialized-data retention and restart receipt transport remain
open. These are limitations of this initial slice, not task 086 completion.

Typed-view cache inputs are a separate publication observation. A bounded walk
declines a receipt when such an input is reachable from its output or ready read
anchors. Reconstructing equal headers alone does not publish the ordinary cache
entry: a later use can allocate a different alias and fail a value quota that a
warm use would satisfy. Dead temporary inputs may be omitted because later
ordinary evaluation cannot name them. Owned cache publication remains open.

Focused laws cover executed scalar/owning-Array results, sibling and payload
edits, exact fresh bytes/fuel, failed revision/recovery, full allocation-failure
sweeps, tight source/value/depth limits and forged/nonduplicate type-tail
declines. Development and release costs still require measurement before
admission.

## Value-only replay boundary

The follow-up candidate leaves the principal prepass and final explicit-scheme
validation at their ordinary positions. It records only the intervening raw
expression outcome and local work. Initial solved type and row inputs are owned
by the receipt and compared through current semantic evidence; a changed lexical
solving environment declines recording. Final type projection and typed-view
publication run ordinarily after either replay or evaluation. Successful slot
publication still allocates nothing. This preserves principal query, inference
and cache effects without treating transported data as a principal certificate.
Inference encountered inside the expression remains ordinary and declines this
value-only tape. This is a follow-up candidate, not qualified task completion.

Receipt counters report immutable owner payload bytes (record array plus owned
event/source/input slices), record lookup comparisons, reachable graph values
examined and known graph-index bytes. Payload bytes exclude the shared evaluator
snapshot and allocator overhead. The current index counter charges new capacity
across all twelve shared graph matching/materialization buffers, including graph
order and type/row maps, plus sparse inspection-page payload. It excludes
semantic interning and hash-table headers. Earlier dense-index measurements
excluded those mapping/order capacities, so small-workload counter increases can
reflect broader accounting. These counters supplement requested/peak solver and
scratch accounting, not whole-process RSS.

Executed partial Array-member judgments have a separate selected-query receipt
boundary. A ready method and its existing syntax recipe must contain at least 64
visits. The receipt owns the receiver/expected judgment, ready value reads,
bounded principal-cache lookup outcomes, source reads and proof/view/plain-fact
publications. Replay matches those facts in the current owner and reserves all
publication storage before importing the output graph. New principal or constant
slot publications, changed cumulative budgets, nested queries and unknown
implementation evidence decline. This boundary does not yet admit an enclosing
constant receipt: growth buffers, escaping typed-view keys and the enclosing
judgment/fuel tape remain ordinary.

Release qualification admits scalar results with scalar ready reads, and
computed Array/List payloads containing only primitive scalars with scalar ready
reads. Compound payloads/anchors keep ordinary evaluation: the captured edit
spent 19.8 MB on dense graph indexes without a CPU payoff. This type/shape
admission also rejects older compound receipts before importing semantic or
graph state.

The focused cost-gate followup raises primitive value-work admission from 64 to
128 source steps: the captured 105-step scalar did not repay owner/lookup work,
while the measured 161-step primitive spines did. An old owner containing only
subfloor receipts installs no dedicated constant provider or fallback gate.
Known non-primitive declared result heads skip recorder/provider observation
before evaluation; open heads retain result-based admission. This followup is
included in qualified compiler 6a57437. The
[merged qualification](ITERATOR_CONSTANTS_QUALIFICATION.md) records the actual
LLVM costs, full native/973-guest gate and 355-file zero analyzer. Primitive
scalar/collection and deep-member edits improve modestly. The captured project
has zero dedicated receipt/index bookkeeping and no constant payoff; its roughly
5% retained CPU regression comes from late ownership fallback assembly. Task 086
remains open.

## Merged checkpoint, 13 October 2026

Local `10fab46` qualifies this admitted slice with 1,624 native laws, 1,030
executed guests, 975 complete failure sweeps plus two expected-error laws, and
zero analyzer findings across 373 files.
[Merged qualification](CONTINUATION_QUALIFICATION.md) records the exact
source/binary pins, measured costs and still-open scope. Isolated clocks above
remain separate from the final combined release measurements.

Local `b145c5e` qualifies sparse inspection and request-shared graph scratch
with 1,651 native tests, 1,043 guests, 1,000 complete failure sweeps plus two
expected-error laws, and zero findings across 374 files. The large-snapshot
constant workload improves from 18.005 to 15.158 ms median retained CPU; the
small control is near parity. Captured project constants still have no receipt
activity. The
[combined qualification](CONTINUATION_QUALIFICATION.md#child-fields-and-retained-graphs-13-october-2026)
records exact pins, counter semantics and the unrelated retained compiler
regression.

## Primitive growth receipts, 13 October 2026

Local `38e822d` admits primitive Array/List growth within an otherwise complete
value-only receipt. The tape owns a mutation serial and the final root buffer's
offset/capacity at the end of this constant. Later constants cannot alter that
captured frontier. Replay reserves the same buffer and charges temporary value
and child debt before its allocation-free publication. Scalar results retain the
serial without a root frontier. This adds no space to the event record.

Growth into old child spans, mixed member-query tapes, unobserved nested growth,
saturated serials and nonprimitive graphs decline. Escaping typed-view inputs
and inference/query budget transitions retain their existing rejection. The
existing 4,096-view observation bound is unchanged: the measured 4,096-element
source crosses it and uses ordinary evaluation.

Seven alternating LLVM pairs cover population and six edits at four sizes, 392
samples total. Retained median CPU is 1.630→1.172 ms at 512 elements and
3.710→1.746 ms at 2,048; median paired ratios are 0.7187 and 0.4718. Population
ratios are 1.0336 and 1.0560. The 32-element control is near parity; the
4,096-element fallback costs 1.0362 times retained CPU. Every output and source
fuel count matches a fresh compile. An initial partial experiment incorrectly
expected reuse at 4,096; its preserved debugger trace identifies the existing
view bound, and the final measurement explicitly includes that fallback.

The combined compiler passes 1,664 native tests, 1,053 guests, 1,011 complete
failure sweeps and two expected-error sweep laws, with 374 files/zero analyzer
findings. Captured project compilation is near parity and still has no
constant-receipt activity. [Merged qualification](CONTINUATION_QUALIFICATION.md)
records final source/binary pins and all measured costs. Compound graphs,
inference/query publication, escaping views and portable data authority remain
open in 086.

## Current continuation — 15 October 2026

The uncommitted continuation integrates ordinary inference-query barriers with
owned input/output frames. Replay uses current solver judgments; it transports
only immutable outputs after validating their actual producer, binder, type, row
and source owners. Unchanged output frames share input storage; changed frames
own their maps and clean up failed publication. Cheap closed structural matches
retain their allocation-free ordinary path.

The immutable graph importer retains closed universal/existential metadata,
actual dictionary closure graphs and immutable package/proof temporaries.
Generative scoped identities, live lifetimes, capabilities, instanced rows and
staged closure edges still use ordinary evaluation. Guard failures and source
fuel keep their ordinary positions. Quantified callable fields serialize through
the existing parametric carrier and dictionary ABI, including actual captures,
constructors and effect-row instantiations.

Root focused evidence is under
`build/bench/finish-rest-20261015/{constant-frame-integration,immutable-graphs-integration,rank-field-integration}/`.
Native complete-OOM and executed guest controls cover exact bytes/work, forged
producers, source/archive/restart, changed payloads and failed-edit recovery.
The rich combined portable module still needs the separate general Package
reader amendment; these slices do not establish complete portable closure.

A single matched Safe/noLLVM captured-project pair preserves exact Wasm and
70,330 source steps. Retained edits replay 59,915 steps through six receipts and
96 solver queries. The prior dev control has eleven receipts and 61,383 replayed
steps; differences in receipt count alone do not establish a speedup. The pair
is unscored and lacks release CPU qualification. Exact 427 external pins and
records are in `build/bench/finish-rest-20261015/captured-current/` and
`captured-dev-control/`. Literal-edit and cumulative-allocation targets, final
release costs and the combined full gate remain open.

Pure temporary allocation now follows the same rule: the final reachable graph
determines transportability. Reflection metadata, unused or purely installed
providers, completed pure requests and pure resolver temporaries can replay.
Recording declines at actual suspension creation, every force, staging,
operation execution and state successor read. Scope generation and live
authority keep their existing boundaries. Ten actual positive/negative cases
cover full OOM and tight source-work budgets;
Source/archive/edit/recovery/checkpoint tests run both tiers and host modes.
Root integration evidence is in
`build/bench/finish-rest-20261015/pure-temporary-integration/`. This removes a
blanket syntax/value deny switch without widening the portable graph authority.
