# Backend writing phase

No builds, tests, compiler invocations, formatting or verification have run.

Written production ports:
- runtime_ir: all production declarations/functions, including packed instruction/ownership encodings, all opcode contracts, ownership facts, call contracts and SIMD lifting. Unit-test blocks are reserved for the separate test-port phase.

Representation decision: module-owned growing tables use Range { start, len } IDs. Function/Signature contain fixed headers; Body borrows driver-owned growing scratch. Module emit keeps contiguous instruction and type runs, relocating an existing run to the append tail if helper generation interleaves emission. No borrowed grow-table element survives append.

Pending: remaining backend modules, including Wasm assembly and both backend engines. This is writing progress, not a completeness or execution claim.

Additional production ports written: wasm_simd_ops, wasm_control_flow, runtime_flags, runtime_code; byte_encoder contains wasm's complete wire byte/LEB/locals/instruction encoding. Runtime expression tuples are deliberately lowered to direct postfix emission; loop/loopTest split preserves header reevaluation. Native allocation-failure behavior requires the root's logical fault support; Goose builtin physical OOM aborts rather than returning a native allocator error.

Representation refined with root agreement: Body is fixed `{locals: Range, instructions: Range}` into Module backing tables; BodyBuffer borrows caller scratch arrays. Accepted optimized bodies append new ranges. Original Function headers/ranges are immutable; `publishBody` and `preparedView` own the boundary. Tail checkpoints preserve module identity through Goose reference identity and restore backing-table tails too.

Additional complete production modules written: simd_intrinsics, collection_ops, scalar_ops, runtime_identity, discarded_bindings, bottom_result, wasm_local_order, runtime_function_key, runtime_body_relocation, collector_contract, machine_code_sharing, known_call, simd_call, scalar_consumer, storage_span_dominance. Wasm module currently contains complete symbolic store, host/arena/list helpers, resource/task/callback/import/export operations; complete assembly pipeline is still pending. No completeness or execution claim.

Cross-module APIs: Scalar/ValueType/Op/Role numeric tags live in runtime_ir (`SC_`, `VT_`, `OP_`, `ROLE_`); SIMD Lane uses legal Goose variants `unsigned`/`floating`; collection_ops provides opCode/opFromCode. Source enum keyword variants follow the frontend's legal-name mapping. Wire numeric identities are explicit. runtime_identity symbol/owner/text return Option<const u8[:]>.

Written opaque_storage with authoritative producer recipe traversal, parameter/ordinal selection and cross-producer field traversal. Resolver is an immutable typed AuthorityEntry table keyed by nominal identity, replacing native callback/anyopaque transport. Complete producer entries must be supplied; lookup never trusts a copied foreign recipe. Frozen Source uses the frontend's store/frozen enum. Usage ordinals are frontend numeric constants (unique 0/shared 1), distinct from public OwnerBoundary wire kind (unique 1/shared 2).

layout.goose is in progress: interned store/tag records, full physical interning/dictionary slots, scalar/opaque storage queries, ownership discovery and record ordering written; type/solver/evidence/row projections and closed-type memo are pending. Core and scoped backend engines have not yet been written. Keep this file's status separate from completed helper modules.

Additional completed helper ports: packed_layout, numeric_rows, provider_chain, runtime_operations. Core source inputs are read through const module references. Layout now also includes partial-merge reconciliation, closed source-type memo and complete source-type/row/quantifier/projection mapping. Solver/evidence/expectation conversions still pending in layout. Source native temporary scratch allocators become lexical Goose typed arrays; no raw byte heap was introduced.

Layout production writing pass is now complete, including source and solver quantifiers, variable/bound scope relocation, associated projection authority, unknown/formal/closed effect rows, all semantic evidence directions and partial CodeExpectation projections. Native temporary ownership cleanup is expressed through lexical Goose owners and context-tail clearing; physical OOM equivalence remains a pending language/runtime qualification issue.

Written backend_timing with all phase clocks, thread CPU lanes, bounded region/refinement census, overflow and saturation rules, UTF-8 source prefixes and exact conditional JSON report fields. Written allocation_emission with entry-first site ordering, exact source coordinates, bounded deduplication/capacity and output JSON. Clock services call root's scalar/OS native primitives; no compiler invocation occurs in the port.

Wasm derived helper `importName(module,id)` returns the immutable import-name slice from names Range; root's resource/task safepoint ports use it. Added acyclic_layout, storage_input_alias and storage_type_key production ports (bounded canonical DAGs, cycle/limit poisoning, inline primitive memo, exact descriptor collisions and atomic final encoding).

High-level core_backend.goose is now actively being written. Its concrete Generator borrows caller-owned typed contexts. Current written portions include complete diagnostic/value/layout/role/signature/entry inference and retained interface helpers; artifact callback/query wiring, named/closure/callable emission, public entry adapters and compile-run lifecycle remain WIP. scoped_backend is still unwritten. Wasm assembly and broad optimization/storage-proof families remain. Do not count either high-level engine as ported yet.

Discarded-binding proofs now carry `(owner Grow reference,start,len)` into one caller-owned shared boolean table; init appends its unit's flags rather than clearing prior units. `values(proof)` exposes the immutable span for artifact snapshots. Backend planning must supply `discard_flags:bool[>..<]&`. This preserves per-unit memo lifetimes without allocating a resizable owner inside a cache entry.

Adjacent dependency written: `eval/specialization.goose` now has the complete
production service first writing pass (test-only laws remain deferred). It
preserves named dictionary projection, type/row matching, returned-function
variance, exact selected owners, semantic refinement, receipt admission and
rejection counters, physical-hole publication rules, scoped code projections
and retained mapping order. Projection callbacks are the agreed typed
`CodeProjection` alternatives; the cache is a borrowed backend `Generator`.
`named` takes caller-owned mapping/row buffers and returns a borrowed
`ResolvedBody`. `core_backend::StaticCodeProjection` aliases its physical
projection context. These files are unverified and external module API
alignment remains part of the later whole-port checks.

`scoped_backend.goose` is now partially written: graph selection,
independent-scalar proof, native fixed value/callable/type-evidence models,
zero-source code, root-descriptor equality, read frames, ABI and metadata cache
algorithms. Its Generator, emission paths and compilation lifecycle remain.
`core_backend.goose` and `wasm.goose` remain work in progress; most optimization,
storage and proof modules have not yet been written. This note is progress,
not a complete-port claim.

Current coherent writing boundary: `core_backend.goose` now includes the
complete named-function, closure-function, callable, constructor, primitive,
operation and scalar-host adapter algorithms, concrete evaluator provider
adapters, refinement wrappers, retained-capture graph ownership and exact
principal graph lease admission. These paths depend on the still-unwritten
`backend_emission::Owner` implementation. Its planned native `Config` plus
`withOwner(config,context,function)` will create caller-scoped typed backing
arrays and dictionaries; body callbacks in core already describe the exact
source emitter setup and operations. No body emitter stub was added.

Still pending in core: host data schemas and public entry wrappers, compile
attempt ownership/retry/assembly/capture lifecycle, public exports and display
helpers. CompileWorkspace will contain driver-owned fixed context references;
`compileWithOptions(workspace,units,entry,options)` will preserve complete
fresh-attempt rollback and both retry orders, with output byte/message owners
borrowed from the caller. This API replaces the source allocator parameter
without returning any references to lexical local owners. Exact workspace
fields will be documented when that portion is written.

Further production first passes written (unverified): `host_cleanup_shapes`,
`backend_plan`, `backend_representations`, and `layout_bridge`. Planning keeps
startup selections, transitive runtime reach, conservative callback coverage,
occurrence fallback, initialization cycles and allocate-before-emission order.
The representation bridge memoizes successful roots only and never infers an
inverse through canonical record order. The concrete bridge context has
caller-owned `Tables` (partial expectation store plus five u32 Grow buffers),
and binds the exact layout/evidence owners lazily.

Shared `support/path.goose` now supplies POSIX dirname/normalization/relative
spelling for canonical protocol identity paths. Core now includes export
selection, entry-interface admissibility, public entry wrappers and detailed
entry type display. CompileWorkspace/lifecycle and body emitter remain pending.

Current high-level boundary: core compilation attempts, typed evaluator
providers, generation adapters, host entry/callback/owner wrappers, source
interface validation/display, assembly orchestration, artifact capture and
replay, counters, result publication, and both nested retry paths are written.
`core_backend` remains WIP: exact artifact diagnostic dump projections and
remaining helper/API alignment are not complete. The checked/native build has
not run. `support/json.goose` supplies typed Writer/Options and custom
jsonStringify dispatch; artifact dumps must use explicit source views for
range-backed lists, numeric IR enum names and derived snapshot ownership.
Generic serialization of new native contexts is not a wire-equivalent dump.

Body-emission writing has started in `backend_emission.goose`: full native
planning ADT/models, Owner/Config/withOwner lexical ownership, payload cleanup,
semantic-site publication, guarded instruction emission, allocation role runs,
wide allocation bitmaps and exact allocation helper selection are present.
Most preparation and expression/body emission algorithms still remain.
`resolved_body.goose` uses typed variable-mode ADT payloads (actual payload
size), numeric body IDs, typed references indexed at construction, and semantic
per-body cleanup. No variable-mode index_of or untyped byte heap is used.
Payload storage is reclaimed at the end of the attempt after all holders clear.

CompileWorkspace is a fixed driver-owned record in core_backend: Generator,
SessionTables, module stamps, metadata/journal and all reuse states; source
origins, region/SIMD/optimizer contexts; retained output capture/snapshots and
explanation; output byte/message owners; independent replay module/contexts,
context-copy owner and replay bytes. It must be constructed before compilation,
and successful retained-result contexts stay live until Result.deinit. Fresh
attempt reset reconstructs semantic owner identities and clears all mutable
state before either retry path. Scoped generator and Wasm assembly remain WIP;
most optimization/storage families are still unwritten.

`core_backend.goose` now has the production algorithm first writing pass,
including the remaining private captured-closure adapter, associated-target
translation, source-shaped artifact dumps and public compile wrappers. The
artifact projections expand Job list ranges with real reserved capacities,
write original union payload shapes, spell numeric Scalar/ValueType/Role/Op
aliases as their source enum names, and omit derived snapshot owner IDs. This
is an unverified writing status: downstream/native API alignment, tests and
compiler qualification have not begun. Supporting backend modules remain
missing, so it does not constitute a complete backend port.

`resolved_call.goose` also has its complete production first writing pass.
Its variable arrow tails use typed reusable runs while preserving application
order, partial-prefix errors and per-plan cleanup. `host_entry.goose` has the
complete bounded no-escape proof and exact guard-before-handle host-stub check.
`support/json.goose` now exposes the shared typed serializer used by artifact
source views and root dispatch explanations; debug lines use the native locked
stderr primitive. JSON output remains unverified until the whole writing pass.

`resolved_flow.goose` and `unit_index.goose` production first writing passes are
now written. Unit indexes preserve the two-pass ordered grouping algorithm,
first-use group publication, packed 32/30/2 parent metadata and saturating
counts, closure/merge/carry flags and quantifier membership. Uses objects have
stable typed reusable owners; their tables and immutable hash-set images are
reclaimed explicitly. Reference-valued dictionary slots use nullable reference
value types so the native dictionary can construct empty buckets; only nonnull
values are inserted. No build, test, formatter or verification has run.
Recursive ownership writing update: Goose spec 7.8 prohibits resizable local owners at calls into any recursive cycle. The emitter now uses concrete fixed Owner maps and list descriptors backed by typed reusable native pools, with runtime_cleanup.initPooled and actual deinit on exit. Shared support/pooled_map and support/pooled_buffer implement native typed storage; backend/substitution_buffers holds exact typed specialization scratch. Specialization's one mapping algorithm now accepts lexical or pooled finite sinks, and refinement uses specialization_receipt.initPooled. Core Generator scratch paths still need the same fixed-owner conversion before the writing phase can be called complete.

The emitter's local storage decisions, ambiguity closure, instance preparation, prepareBody/prepareMapped, cursor family and linear-cursor preparation, numeric proof preparation, staging, prepareNode/prepareChildren, packages, binding metadata, constructor sharing, patterns, callable/computation descriptions and factory preparation are now source-written. These are unverified first-pass code. Call inlining, most remaining emission methods, scoped Generator, Wasm assembly and numerous production leaf modules remain unwritten. No build, test, formatting or verification has run.
Further writing progress: collection_edit_call and collection_iteration now contain their entire production algorithms. Emitter inlining (ordinary, numeric, opaque, evaluated captures, static and partial calls), aggregate/record/constructor emission, projection preparation and location masks/shapes, packed projections, update copy/reuse paths, collection-step preparation/emission and private-cursor family metadata are source-written. The active source frontier is around backend_emission.zig 3660: private cursor row/binding/directory routines and subsequent collection/scalar/control/task/template methods remain. This is a writing frontier, not a source inventory or compilation check.

Generator.owner_id is a process-local nonzero context identity distinct from allocation_owner; resetGenerator preserves it through retries. layout.withStore is a complete lexical typed-owner factory for isolated private reuse probes, with callback completion and explicit deinit before owner release.
Current writing frontier: backend_emission production algorithms through callableImplementationLayout (Zig around 5870) are written, including private cursor storage, numeric row pack/unpack and guards, exact/ragged builders, all collection operation dispatch, list spans/rows/edits and SIMD expressions. exact_builder, ragged_builder and list_traversal now have complete production passes. Template/call/resource/control/task/binding/expression methods after that frontier remain, as do scoped Generator, Wasm assembly and other backend modules.

Goose cleanup syntax correction: function-level earlier `defer` scopes in backend-owned files were rewritten into named continuations with explicit deinit/restore and return channels, preserving value evaluation before cleanup. port-notes/lower-cleanup.py is a source-writing helper for that one migration, not a compiler or oracle bridge. Loop/branch-scoped cleanup still needs manual control-flow writing. Spec 7.8 also requires native cycle-local references to be passed down without storing them: pooled cleanup links are now parent-owned numeric frames; emitter small result output is a numeric temporary-slot ID, RaggedFacts snapshots compile-wide descriptors, local instance decisions are immutable fixed snapshots. Specialization MappingSink and CodeProjection still need their cycle-local descriptor-reference correction, coordinated with evaluator ownership. No verification has run.

Emitter writing has advanced through effectHandle (source around 8090): templates/factories, requests and request loops, static closure preparation/application, universal carriers, guarded numeric call targets, resource transfer and scopes, every task operation including descriptor adapters/movers and split views, usage preparation/borrow, provider values and effect scopes/handlers are written. Each new recursive path uses fixed scratch records or actual typed pooled buffers and explicit named cleanup continuations. Resolver/dictionary/call/control/binding/expression sections after this frontier, scoped Generator, Wasm assembly and remaining leaf modules are still pending. This is an unverified writing frontier, not a source inventory claim.

Opaque authority lookup now returns a borrowed `const Authority?` rooted in Resolver.entries. Recursive nominal storage inference uses a bounded fixed Frame[256] owner and numeric parent indices, preserving its proof-depth decline without storing references to recursive-local Context records. EffectEvidence.Store constructors in layout use the new fixed pooled owner; mutable table access uses `.items` while immutable Snapshot/View access retains slices.

The backend_emission first writing pass now reaches the source module's final production function, mergeBranch (around source line 11200). New sections include named/dictionary dispatch, pipeline fusion proof and emission, typed carriers for collections/nominals/callables/ownership, package conversion, complete expression/suite dispatch, branch roots, loop inputs and list walks, carry publication and exit cleanup, scalar/operator selection, ordinary/packed/static patterns and match alternatives. pipeline_builder and identity_array also have full production writing passes. This does not certify declaration coverage or compilation: remaining earlier cleanup scopes and native ownership/API alignment are still pending, along with scoped_backend, Wasm assembly and missing backend leaves. No verification has run.

Provider Store now exposes reset(Store&) -> Error for evaluator retries: release retained frame authorities first, clear frame/cell/owner maps, clear the authority owner frontier and its counters, and retain caller backing table references. Pure dictionary proof helpers preserve the emitted initializer prefix on a later forwarding decline; internal proof_analysis_limit is translated back to the source complexity diagnostic before returning from emission.

Provider and effect-authority ownership now use durable global typed metadata leases. Both expose initPooled/init -> (Store,Error), initPooledRef -> (Store?,Error), reset(Store&) -> Error, and physical deinit of capacity runs/state/reference slots. Provider frames/cells and authority owners expose .items/.len; provider Activation owns a fixed pooled Scopes descriptor and reserves cleanup before publishing a new authority. This supersedes the earlier caller-table provider constructor. Reset keeps the canonical borrowed Store address and refreshes process-local owner identity; guest/source authority handles remain exact numeric IDs. These native ownership changes are source-written and unverified.

Additional full production leaves now written: linear_cursor, dictionary_layout, startup_emission_facts, provider_origins and storage_type_arguments. Generic storage_type_arguments.Stack<A> borrows a compile-wide Pools<A> record of actual typed pool owners; it implements linked latest heads, exact undo/snapshot rollback, compact inheritance, immutable captures and saturating statistics. Snapshot owner_id is a process-local derived identity for environment interning, excluded from portable layouts. Scoped Generator still awaits its Metadata/descriptor construction and engine methods.

Detached late views now have full first production passes in cohort_candidate, region_candidate and source_origins. Their native constructor mapping is prepare/checked/extend/detached -> prepareInto/checkedInto/extendInto/detachedInto; test-only extensionForTest is deferred with all tests. cohort.init(Module&) constructs the fixed destination; origins.init(cohort Extension&) and region.init(cohort Extension&) retain compile-wide caller contexts. Each origins/region/replay view must have a distinct destination Module and cohort Extension.

IR Function has derived borrowed_body/borrowed_locals/borrowed_instructions metadata. Immutable Module getters read those slices; addLocal/emitReference/own materialize before mutation, and preparedView/publishFunctionBody clear them. publishInstructions replaces only code. Direct assignments after publishBody must clearBorrowed. Portable/source views must omit these derived fields. The native detached representation copies metadata containers/type table into destination owners while borrowing untouched instruction bodies; first-write body copying and rewrite order follow source intent, with allocation behavior unverified.

Projection and substitution ownership writing now uses lazy globally typed
metadata heads for all substitution_buffers families; fixed descriptor copies
share mutable items/storage while inert absent defaults allocate nothing.
MappingSink/RowSink pooled variants copy those descriptors. physicalProjection
returns (PhysicalProjection,Error), Service stores Option<CodeProjection>, and
OwnedProjection flattens the actual physical callback to avoid recursive value
type storage. The evaluator owner is adapting its CodeProjection variants and
stored request fields. Cycle-local Tape/Observation borrowing is still pending.
The complete production storage_deferred_join algorithm is also source-written,
with real typed lane/hole runs and explicit physical deinit; scoped controls must
release those runs during their corresponding lifetime cleanup. No checks run.

Scoped writing now includes compile-wide Metadata ranges/IDs, durable method
selection sessions, descriptor-call stores, fixed pooled generator containers,
binding/transport snapshots, root cleanup, semantic type-environment capture and
resolution, complete structural type mapping, fixed layout construction and
opaque nominal producer lookup, storage shape/variant joins, and inline payload
loads/stores. It is still an incomplete engine: storage element/read-frame,
transport, calls/control/task emission and its public compile entry remain.
The standalone storage_layout and storage_collections production passes are
written. storage_span_dominance now owns fixed typed pooled active/stack runs
and returns explicit errors from scope scans. No verification has run.
Scoped production writing now reaches collection dispatch (source around 2215):
fixed/grow/resize owner reservation, scalar literal payload copies, complete
packet conversion and host callback calls, persistent application initialization
with retry handles and final global publication, every storage operation,
SIMD loads/stores and all supported collection/cursor builders are written.
New recursion paths use fixed local descriptors and explicit cleanup. Reusable
call admission/emission, remaining source dispatch/control and scoped compile
construction remain unwritten; the full backend is still incomplete/unverified.
Scoped type/member refinement, primitive callable construction and application,
selected-data admission, symbolic getter/partial/call/closure/product/record
planning and owner-graph reads are now written through planValue (source around
2820). Captured callable vectors and environments publish immutable ranges into
compile-wide Metadata; no recursive-local descriptor references are retained.
MethodSelector uses core_eval.initOwnedSession/deinitOwnedSession. Source-shaped
metadata default/constructor alignment and later engine sections remain pending.
The complete storage_field_plan cache is also written, including negative
recipes, saturation, and exact spelling probes. No checks have run.
The storage_transport production Index is now written in full: immutable Core
merge/carry indexes, bounded whole-value canonicalization, exact field-lane
identities through record merges/updates, all break/continue edge checks and
building/changed/invariant memoization. create(Module&) returns a stable typed
pooled Index handle; deinit reclaims every map, exit run and metadata slot.
Scoped native map wrappers now alias the exact pooled_map.Map instantiations,
matching nominal Goose types. Earlier custom map wrappers elsewhere still need
that source API alignment. No verification has run.
Refinement recording now obtains canonical global TapeOwner/ObservationOwner
borrows, restores prior Session references, then releases Observation and Tape
owners. The selected-type key Builder now owns fixed typed pooled word/node/map
descriptors; init(remaining:i64,options={}) stores the private budget by value,
all descriptor/DAG/height/collision/word-work algorithms and SDK1 encoding stay
explicit. Words.toOwned/release transfer exact typed runs and deinit releases
capacity. No recursive-local Grow/budget reference is stored by this builder.
Scoped callback admission, concrete/nominal inline evidence and structural-field
ambient handling are now source-written through source around 2990. Later
admission/evidence/call generation/control/compile sections remain pending.
Scoped admission now includes descriptor/plain evidence selection, cached exact
height receipts and saturating hit/publication counters, numeric body admission,
primitive/reference aliases, associated partial callbacks, and selected-call
substitution/goal/binding rollback through source around 3180. numericExpression
and subsequent call/evidence/emission/compile sections remain pending. All work
in this note is an unverified source-writing pass; no build, test, formatter or
compiler invocation has run.
Scoped numericExpression now has its full production admission walk (source
through roughly 3485), with explicit terminal-result handling for direct getter,
partial-call and associated-call proofs. Added full storage_parameter_fields
production pass, including bounded field footprints, nominal projection catalog
checks and pooled canonical Walk contexts. Scoped helper writing now extends
through readerWordParameter (source roughly 3820): context counters, small
return-register ABI, inline/reader word schemas, barrier traces, reader argument
admission, exact layout-evidence encoding and physical parameter rebinding.
Remaining scoped sections begin readerParameter and include descriptor graphs,
call generation, source expression/control emission and compile construction.
No verification has run.
Scoped writing now reaches readerCallEvidence (source around 4035): child
parameter roots, immutable environment graph retention with completed-copy memo,
reader-result provenance retention/remapping, masked ABI slot stores, aliased
loads and exact call evidence are written. All child Generators share the
compile-attempt Metadata owner; independent immutable vectors publish fresh
ranges, so retained compile-local plans do not borrow a child descriptor.
Cross-attempt retained artifacts still require the existing portable projections.
The remaining scoped source begins descriptorType and continues through owner
graph summaries, reusable-call emission, main lowering and compile construction.
Scoped descriptorType/body/value evidence, closure qualifier checks, optional
shared-evidence rollback and retained descriptor schemas now reach source around
4185. Metadata also owns copied spelling bytes used by compile-local schemas.
Next source section is optionalWriterEvidence / writer owner-graph key encoding.
The engine's later reusable-call emission and top-level compile are unfinished.
Scoped writer/owner-graph evidence and graph input/result/caller remapping now
reach source around 4385. storage_owner_graph has its full production pass:
canonical breadth-first owner numbering, bounded typed edge visits, fresh-owner
result donor checks, all-payload provenance and exact ordinal edge encoding.
Graph<Value> takes the immutable metadata accessor context at traversal/encoding
calls; it never stores a reference to a recursive-local descriptor. Production
result donor checks call the same context's plainInlineValue method. Its typed owner
and ordinal runs are physically released by deinit. No verification has run.
Scoped projected-argument field footprints, bounded diagnostic word counts and
publication counter snapshots/rollback now reach FunctionMark (source roughly
4545). PreparedArguments.values is a Metadata Range, read with preparedValues;
its input vector is published into compile-wide typed storage before it can
escape a recursive caller. This preserves selected fields/words and diagnostics
while making native allocation timing a pending qualification item. FunctionMark
restores the exact source publication field set and counts discarded projection
calls before resetting the module tail. tryFunctionPlan and following emission
sections are still pending. No verification has run.
Scoped completed-plan retry/rollback and construction input stages are now
written: fixed FunctionPlanInput ranges, canonical rejection flag slots,
addressed/direct/buffered signature choice, helper/cache insertion, child owner
contexts, global catalog rebinding, addressed bundles, parameter aliases and
provisional recursive contracts (source through roughly 4825). Construction is
still WIP: output serialization, demand rewrites, summary publication and later
call/expression/compile methods remain. No compiler or checks have run.
Scoped construction now includes helper body invocation, fresh-result owner
roles, retained graph result schemas, inline register publication, buffered
result serialization and unchanged-input result aliases (source around 4880).
Added full storage_result_alias production pass with exact write/annotation
rejection and typed run cleanup. Wasm also has u32 function-ID overloads for its
immutable parameters/locals/instructions views. Demand rewriting and final plan
publication still await writing before constructFunctionPlan can be completed.
Result publication ownership is source-written in result_publication and core
hooks. Result defaults are inert empty views. A canonical driver binds a numeric
workspace Owner before compile; the facade stamps its result, and four-argument
pinResult retains catalog/unit/seed journals, copies Core headers and rebinds
Capture ModulePins before publication. Public pinning revokes workspace reuse.
Result.deinit cleans output contexts then marks the lease released; the driver
must destroy all workspace contexts before result_publication.destroy(ownerKey)
releases Core/header/input pins. The canonical driver factory is root-owned and
still pending; these hooks alone do not complete public emission integration.
array_cost_explanation now has the complete production report/snapshot/JSON pass,
using the same owned_arrays proof, entry-first site order, UTF-8 truncation,
16384-site cap and explicit clone/deinit. owned_arrays itself remains pending.
addressed_input_demand, direct_input_demand and packed_input_demand now have
complete production passes against Module/function-ID views. They stage full
replacements, preserve instruction origins/logical locals, retain exact read
masks and release typed scratch/returned masks. Scoped construction demand
validation and rewriting is written through the machine-bound checks (source
around 4995); final summary publication and constructFunctionPlan orchestration
remain the immediate frontier, before later reusable-call and main lowering.
Publication inputs are held until canonical driver workspace teardown, with
only numeric owner/epoch state in Result; driver factory integration remains
pending and no end-to-end ownership or compilation qualification is claimed.
The full constructFunctionPlan algorithm is now source-written through final
summary/counter publication (source around 5050), split into fixed construction
stages with explicit cleanup. This includes addressed/direct/packed demand,
parameter promotion and alias retry, recursive access contracts, fresh result
owner summaries, retained event/region/schema runs and exact publication order.
Later prepared/reusable-call emission, bundle snapshots, scalar/source lowering
and scoped compile construction remain. No verification has run.
