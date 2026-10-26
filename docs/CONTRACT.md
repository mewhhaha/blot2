# K1 shared implementation contract

Normative authority is the versioned snapshot in `spec/`; this document fixes
interfaces between implementation components, not a replacement semantics.

`src/model.goose` is the only shared row definition. All row IDs are owner-local
u32 values: zero means absent, each row arena starts with a zero sentinel. `refs`
and `bytes` are raw arenas with no sentinel. `Span { start, count }` addresses
its declared arena; validate both values before indexing, using subtraction to
avoid arithmetic overflow. All variable-length ID lists use `refs`.

A `CoreBuilder` borrows growable tables owned by one nonrecursive driver;
`with_core` creates those tables. `core_view` lends immutable slices for one
phase. Durable publication serializes/copies into separately owned storage; no
parser, proof scratch or borrowed source pointers escape. Validator contexts borrow
the immutable Core view for one attempt; copying a context must not copy its
entire table inventory. Each attempt retains its own work accounts and scratch.
Source paths/names
are interned in the owned byte arena. Region/Domain IDs refer to binder scopes
and generative introduction sites, never physical addresses or runtime nonces.

Type row children and fields retain canonical source order. Contract rows own
argument/result types, effects, propositions and finite depth/frame envelopes.
Operation registry ID equals the explicit OP tag under K1-SEM-POLICY-1. New
entries append, never renumber. Each operation's refs are source evaluation
order, including moved authorities. OP results have exact Value definitions.
Block parameters are values; affine parameters are a subset, not a duplicate
state vector. Terminators reference explicit edges and ownership discharge.

The frontend calls begin_completion/end_completion for each completed body.
The integration layer seals only successful balanced completion. The validator
independently checks table integrity, types, usage, dominance, evidence and
resources; no boolean checked marker authorizes admission. Backend and optional
optimizer may not invoke completion. Lowering checks the phase counter delta.

Diagnostic ranges: frontend/proofs 1000–1999, validator/artifacts 2000–2999,
runtime/backend 3000–3999, integration/loader/editor 4000–4999. Components expose
stable textual diagnostic names. Work limits reset per declaration, not per
module. Failed or cancelled candidate transactions never replace published
bytes. Cache decoding does not establish source admission.

Implementation ownership: root model/driver/registry/session/tooling/docs;
frontend agent frontend/proofs/parser tests; runtime agent runtime/wasm/guest
fixtures; validator agent validate/artifact/hash/optimize/corruption tests.

Scalar host exports validate Bool arguments as exactly 0 or 1 and evaluate all
numeric `requires` predicates before entering source code or changing the frame
frontier. They support Eq/Lt/Le/AddFits/SubFits/MulFits over U32 arguments,
literals and `MAX - x`; unsupported predicates make the export ineligible.
Invalid inputs trap at the wrapper, because the scalar signature has no failure
envelope. A caller must discard an instance after any trap and must not resume
source execution. The array bridge retains its explicit InvalidInput status.


## Added completion and representation records

`Binder.introduction_kind` distinguishes an erased declaration binder, function
activation and fresh operation introduction. `Definition.value` is always an
SSA Value ID. A static definition's value is produced by `OP_STATIC`, whose
`imm0` names a `StaticObject`; neither field is a host pointer.

Static bytes are canonical little-endian words with typed symbolic relocation
records. `StaticValue` is evaluator scratch and carries those relocations out
of a temporary evaluator frame. Publication separately charges produced bytes.
Required static evaluation shares the enclosing declaration's semantic budget.

`Layout.schema` names a canonical `Schema` row, never a Type ID. A dictionary
contains size, alignment, flags and canonical schema ID. Derived generic
realizations and callable adapters are completed before sealing and may not
complete or clone a source body. ABI plans can name contract-only interfaces
with function ID zero. Stored existential Nat witnesses precede their payload;
Domain binders have no machine word.

`Dependency.kind` uses the semantic DEP_* constants. Its separate `query_kind`
is 1 for a value lookup and 2 for a type lookup. `identity` owns canonical module
path, NUL and queried identifier; `producer` is the selected Definition ID or
zero for an absent observation. Receipts retain actual lookup observations.
Static evaluation records transitive DEP_BODY and DEP_STATIC observations;
ordinary calls depend on complete interfaces. Origins are relocated separately.

The retained CLI session owns two private serialized revision buffers. Only a
successfully completed/validated/emitted current-process candidate can become
active. Candidate storage is prepared before output publication, and commit
changes the active index without allocation. External `inspect` input never
becomes a trusted source-admission receipt. Cache misses/exhaustion perform
fresh source work; a previous diagnostic is never treated as successful work.

## Completion ownership and generic environments

Required work belongs to a source Definition. Its nested anonymous functions,
local `forall` bodies and required-static staging remain in the same operation,
block, type, proof and semantic-work account. Calling a separately declared
dependency consumes its completed interface; that dependency's body work is
charged to its own declaration. Physical Function rows do not reset budgets.

`OP_GENERIC_BIND` (111) is a lexical declaration marker with no result or
machine code. Its arguments are immutable Share captures and `imm0` names the
once-checked generic function. `RULE_CAPTURE` can anchor this marker or an
ordinary closure constructor. Instantiation produces a monomorphic callable;
there is no first-class runtime forall value or higher-rank escape.

Callable adapter environments contain the adapter's dictionary/Nat witness
prefix followed by the target function's ordinary environment.
`CallableAdapter.target_environment_offset` is exactly the prefix byte size;
the adapter passes `env + offset` to the target. Static publication and the
independent validator use the same typed layout. Captured Nat slots must carry
the exact lexical witness, not an arbitrary U32 with matching bits.

`Contract.layout_premises` records bounded aggregate/Plain geometry requirements.
Generic calls discharge these from interface substitutions, without rechecking
the generic source body. `DictionaryRealization` is the complete registry of
declared ABI transitions; lowering cannot invent new representation classes.

`Function.evaluator_only` marks synthetic static staging: independently checked
but absent from runtime function/table inventories. `Terminator.evidence`
records required impossible-path proofs. Static closure relocations pair code
with their exact immutable environment, and dictionary relocations name closed
canonical schemas. Static dependency fingerprints traverse symbolic graphs;
raw table IDs never serve as persistent identities.

## Transport, publication and observations

Persistent encoding sorts external identities and assigns deterministic
owner-local graph IDs, while preserving each module's declaration source order.
It retains scope-owned proof facts even when no operation references them.
The separate current-process clone preserves IDs for optimizer side tables;
it is not the persistent transport format.

`rebuild` treats an external Core object as a required artifact, validates it
independently and emits executable bytes locally. It neither trusts an attached
executable nor promotes external work receipts into the source cache. Diagnostic
rendering checks source/name spans before using untrusted artifact metadata.

Output files are individually atomically replaced. When both Core and Wasm are
requested, the OS adapter stages both, prepares rollback links, and defers
ordinary termination signals during the nonallocating rename window. Reported
I/O failure restores prior outputs. This is not a power-loss transaction or a
simultaneous two-path snapshot for unrelated readers. The retained session has
one authoritative Wasm output and commits its private revision index only after
that publication succeeds. Ordinary generated Wasm (`build`, `rebuild` and
`serve`) uses checked writes and close followed by sibling-file atomic rename,
without file or directory synchronization. Success means complete bytes visible
to readers, not durable media acknowledgement; deferred writeback errors may
occur later. Explicit Core serialization and paired Core/Wasm output retain their
existing synchronization paths. Source-formatting output also retains its
existing writer.

CLI timing separates `setup_ns`, the required `pipeline_ns`, optional
`artifact_encode_ns` and `publication_ns` inside `total_ns`. These clocks exclude
process startup before CLI dispatch and teardown after reporting. Pipeline phase
clocks still split loading, completion, planning, validation and lowering.

Phase timing includes fresh semantic and independent validation work counts,
retained bytes and balanced completion counters. `--trace` emits phase/module
events for cancellation and tooling; cancellation is polled between modules
and before publication. Runtime `--telemetry` is separate from ordinary timing:
its manifest declares a read-only `blot.telemetry` word export with 13 U64
counters. The host returns immutable copied BigInt snapshots and retains private
memory. Instrumented geometry and certificates are distinct from default output.
## Compiler work counter scope

CLI `--timings` and retained responses distinguish work from inventory.
`proof_visits`, `static_steps`, `static_bytes` and `interface_instantiations`
count work performed in the current source completion. Static bytes count
published immutable payloads, including captured environments and projections;
steps/bytes are accumulated as deltas, not by summing cumulative object totals.
An explicit generic callable or type-alias application counts once after its
substitution succeeds. Reused bodies do not replay those source counters.

`proof_terms` and `proof_edges` are the completed Core inventories (edges count
fact and evidence rows). `semantic_instances` counts checked function bodies,
including evaluator-only staging; `executable_instances` counts emitted source
bodies, excluding staging, trusted runtime helpers, export wrappers and fixed
adapters. `adapter_count` reports the separate completed callable-adapter table.
`generated_bytes` includes the emitted Wasm and its manifest/certificate.
`rewrite_visits`, `rewrite_applications` and `rewrite_declines` report the optional
optimizer; they are zero with optimization off.

The compiler has no general inference graph: general inference regions/nodes
are zero. `created_regions` counts the separate guarded source-completion
contexts; `active_regions` and `downstream_regions` must be zero after admission.
Candidate validation and optional retained admission report their own visits.
Dependency invalidations count rejected candidates due to changed dependency
presence, namespace, body or exact relocated interface, excluding absent
candidates, changed own text and optional-budget declines.

Retained `total_ns` measures the candidate pipeline. Separate `cache_admit_ns`
(decode and independent validation), `cache_encode_ns` (canonical encoding and
buffer copy) and `publication_ns` expose the surrounding work. Measured request
wall time also includes protocol, scratch destruction and scheduling overhead.

## Bounded release inlining

The release tier may transport an admitted direct, monomorphic, single-block
scalar callee into its caller. Initial eligibility is U32/Bool/F32 arguments and
results, exact total scalar operations and direct calls with matching complete
interfaces. Captures, generic substitutions, effects, contracts requiring proof,
and pinned evidence producers remain outside this rule. No syntax or ABI changes
are implied by optional eligibility.

Callee templates come from the immutable pre-expansion Core. A pending operation
records its expansion depth, so rewriting a callee earlier cannot bypass the
maximum depth. Arguments are evaluated once; cloned operations retain source
order, including evaluated operations after the returned producer. The call's
result identity is preserved and intermediate values receive fresh owner-local
IDs. F32 operations remain separately rounded and are never reassociated.

The optimizer preflights the existing policy limits: at most 32 admitted
operation/terminator nodes in a callee, depth 2, 16 sites per caller, and growth
at most floor(caller nodes / 4), capped at 256. Whole-candidate normalized growth
also stays within N+64, and visits/rewrites retain 8*N+1024/N+256 bounds. Expanded
rows and reference spans are checked against the artifact byte bound before
mutation. Every published candidate is independently revalidated. Optional work
cannot change source admission; budget refusal retains an admitted baseline or
a validated bounded prefix.

`inline_sites`, `inline_growth`, `inline_declines`, `inline_max_callee` and
`inline_max_depth` report this work separately from the R01–R12 catalogue.
They are zero in the off/fast tiers. Inlining never updates retained semantic
receipts: a new revision redoes optional transport from its current completed
callee bodies after semantic reuse.
