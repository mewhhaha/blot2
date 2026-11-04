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
