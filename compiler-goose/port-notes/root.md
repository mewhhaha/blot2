# Support, runtime and retained-state writing

Writing only. No port build, test, lint, formatter or execution has run.
Zig source, installed binaries and the normal toolchain remain intact.

Production writing passes completed, all unverified:

- Root execution_policy, compilation_tier, inference_limits, work_counters.
- Runtime runtime_layout, storage_packets, task_abi, resource_safepoints,
  task_safepoints, runtime_cleanup, request_runtime, public_owners, task_context.
- Reuse resolution_cache, epoch_resolution_cache, composite_resolution_cache,
  projection_cache, declaration_origins, source_overlays, zig_project_frames,
  code_expectation, substitution_keys, purity_diagnostics, principal_interface,
  semantic_query_table, principal_query, principal_type_graph, code_artifacts,
  specialization_receipt, refinement_receipt, principal_inputs, constant_receipt,
  artifact_emitter, artifact_capture, executable_query, shared_query_gate,
  dispatch_explanation, principal_reuse_gate, declaration_dependencies,
  declaration_projection, dependency_certificate, validation_image,
  mismatch_display, code_body_validity, completed_core_validation,
  frozen_dependency, independent_call_proof and source_value_template.
- Check frozen_core_validation, with bounds, mixed graph and staging/scope
  helpers in frozen_core_bounds, frozen_core_graph and frozen_core_scopes.
- Support explicit error labels, fixed Option, byte codecs, exact Wyhash,
  portable Blake3, structural field streams, finite postfix recipe emitter,
  native scalar/OS services, file IO, explicit packed host footprints and
  complete typed Core worker packet codecs.

Artifact import now has full first writing passes for constructor admission,
request and representation transport, closed semantic imports, principal maps,
static graph correspondence and solved-job transport. Its immutable Core remap
comparison and knowledge walk live in artifact_import_core and
artifact_import_knowledge; dependency_symbol_slots is written too. All are
unverified. importSolved receives the source Context explicitly because job
substitutions are retained typed ranges. Pooled cleanup stacks use numeric
generation-checked global frames, so recursive callers retain no local links. All other runtime/reuse modules and the main CLI/session
driver remain required and unwritten. An implementation's presence does not establish import/API
integration, source parity, runtime qualification or acceptable performance.

Representation contracts:

- Artifacts use fixed ranges into caller-owned journal tables. Inline/static read sets reserve real typed spans with their own capacity;
  nested writes keep these spans stable until the span itself grows.
- Pinned Core retains an exact fixed header view. Composite slice-field
  identity replaces Zig's pointer-address hash; no pointer integer is exposed.
  Full structural stream equality retains float bits and excludes padding.
- Module stamp streams exclude derived owner IDs and package_payloads through
  Core.stampView. Tokens and allocation_owner are process-local only.
- A compiler/session heap supplies one nonzero allocation_owner to Generator,
  metadata Context and completed-query state. This replaces source allocator
  ptr/vtable identity. Unknown zero declines reuse. It is not a wire identity.
- Generic query tables use concrete Adapter record pools and actual reusable
  Link/Bucket runs. Preparing capacity publishes no record. Candidate/table
  identities and positions bind publication; bounded cursors preserve order.
- Query aliases explicitly bind Key, Dependencies, Value, Adapter type arguments.
  Adapter provides fingerprint, complete, bytes, allocateRecords,
  releaseRecords and recordBytes. Query handle type includes its Adapter.
- Reusable typed runs own retained receipts and metadata. Failed candidates
  release runs; last leases release their concrete pool allocation.
- Frozen snapshots have const slices. Fresh owned SolvedEvidence and receipt
  copies keep mutable slices while being relocated, and publish only afterward.
- Native hooks call Generator through a typed borrow. No runtime function
  pointers, untyped heap casts, Zig subprocess or source interpreter is used.
- Constant Query/Judgment clone returns nullable typed reference plus Error;
  successful callers assert presence. Query/Event/Record ownership transfers
  to typed reusable pools before a lexical recorder ends.
- Tape owns six fixed pooled buffers; initPooled supplies their descriptors.
  push/append and len remain buffer APIs, while slice users read items. finish
  checks every sticky buffer failure before publishing retained observations.
  Constant/principal recorders still expose typed RecorderTables and lexical
  withRecorder helpers; recursive callers need pooled ownership conversion.
- bytes_of is used only on serializable arrays of address-free elements.
  support.host_layout records C.2 packed 64-bit host footprints independently
  of wire schemas. No metadata pointer is serialized to measure its size.
- Native scalar atomics use memcpy under a mutex because C.2 packs fields;
  taking a u64 reference does not imply native atomic alignment. Native builds
  must link platform.c with pthread and libm support and target a 64-bit host.

Pending target-language qualification:

- Builtin Goose array growth currently aborts on physical OOM; recoverable OOM
  and allocation-fault parity are not established. Explicit logical errors
  propagate, and no allocation-fault qualification is claimed.
- Current sibling bootstrap lacks parts of the specified reusable/native
  threads/encoded-reference language. The source uses the full specification;
  toolchain selection and any required runtime work follow the complete write.
- Copied native worker packets must encode every immutable compilation input
  and decode owned outputs. Source packet callbacks and the main driver still
  need complete integration. Their cost is unmeasured.
- The source-pointer-free host footprints need qualification alongside the
  final record schemas, and every external archive needs exact typed codecs.
- Goose section 7.8 forbids local growing owners on a recursive call cycle.
  Cleanup Stack and specialization Tape now have fixed pooled ownership.
  Recursive generator, layout, checker and evaluator owners are still being
  converted; first writing passes do not establish this qualification.
- Capability reconstruction's native 1 MiB allocation policy needs its typed
  private budget adapter aligned. Frozen validation calls deriveWithOwnersBudget;
  neither source acceptance parity nor allocator-fault parity is established.

Artifact emission constructs its Recorder from five typed caller arrays. freeze
returns complete owned FunctionArtifact/Local/SymbolicInstruction runs. Exact
replay and relocated replay take a driver-owned destination Module; materialize
uses that same explicit destination. Runtime operation capture receives the
whole Store to resolve key ranges. Native resource IDs remain symbolic until
replay maps them; unsupported arena composition fails before mutation.

Lexical withRecorder/withCopy callbacks use named functions and return locally.
They must return their Error through the helper so explicit retained-pool
cleanup executes; do not use a block's nonlocal return to leave that helper.

Job inline_capacity/static_capacity record real reserved range lengths. Growth
uses the pinned Zig 0.17 ArrayList minimum + minimum/2 + max(1,64/sizeof(T))
policy for these address-free element types. Artifact job views emit the
original {items,capacity} fields, excluding the private range/capacity fields.

Native scalar helpers include memcpy signed/unsigned i32 representation and
C fmaf for explicitly fused binary32 multiplication/addition. A separate multiply
and add must not replace that one-rounding operation.

Frozen validation uses ModuleRef {value:const Core.Module&} for borrowed foreign
owner catalogs, keeping Session.units as its original contiguous Module slice.
Graph vertex/item operations have validated-bounds preconditions; edge returns
an optional vertex. Typed reusable linear scratch is released on every return.

Core worker packets encode all source Core data, including type certificate
bytes, through 96 concrete record/enum codecs and 59 typed allocation families.
The private packet header includes version, schema, payload length and content
digest. Size/value/depth limits bound decoding; failure releases the allocation
journal. Module and Types owner IDs and package_payloads are derived locally,
never sent as thread identities. Decoding checks data shape and enum ordinals;
the complete foreign Context must still pass frozen validation before evaluation.
Worker transport integration and packet costs remain unmeasured.

Source value transport owns fixed pooled visit pages, sparse anchor/position
buffers and output runs. It preserves multi-root aliases, source operation and
closure ownership, collection buffer frontiers, cumulative quotas and precharged
debts. All representation imports and reservation occur before value publication.
Non-scratch mapped outputs use releaseMapped; scratch outputs remain borrowed.
Independent call rechecking uses withSharedSession and layout.withStore, records
only source/scalar premises and publishes through its enclosing query. The
shared copied-worker adapters are being written by the evaluator owner.

The remaining retained/project/session modules and runtime collectors are
still required. Artifact import, symbol-role classification, public visibility
and type display have full first writing passes. Constructor and callback alignment is unfinished throughout the
port. The normal Zig compiler is preserved under remote tag
goose-port-oracle-156f84b; writing checkpoints do not select Goose for builds.

Current cleanup linkage: pooled Stack descriptors contain only numeric global
frame keys and generation values. Child emission reads the parent key without
retaining a reference to a recursive caller. Lexical stacks remain available
for nonrecursive owners. No build or runtime verification has run.

Principal evidence reuse, principal input image, prelude admission, public opaque
storage validation and intermediate-module frontend cutoff now have full first
writing passes. Principal input keys shrink translated optional publications by
copying their exact kept prefix into a new typed run; physical copy cost is
unmeasured. Core image comparison erases only canonical scalar literal bits.
All public/current-owner semantic IDs are re-interned before memo replay.
Evidence capture reads the new pooled Store Buffers through their items slices;
this remains source alignment, with verification still deferred.

Cohort, region and shared_rc runtime emitters now have first production writing
passes. Finite source tuple recipes are expanded into ordinary postfix calls
without an expression heap. Shared RC helpers consume the fixed Emitter and
report its first Error; checkedHead also exposes the RuntimeCode adapter used
by region/cohort checks. Successful instruction order is intended to match the
Zig oracle; this has not been verified. Arena, root, cycle, list and data-stack
runtimes remain unwritten. Capability reconstruction in frozen bounds now uses
the checker-owned pooled Store and releases it on every exit.

Arena allocation/free-list emission, root journals and cycle trial deletion now
have full first production writing passes too. The arena source copies the
pinned explicit instruction tables; the root/cycle recipes use the same flat
emitter without a temporary expression heap. Private journal ordering, complete
dead-set classification, lease guards and collector local zero are preserved
in source. Nothing in this checkpoint establishes emitted-Wasm equivalence.
Persistent lists, data stacks, session heap, remaining cache/project/server
modules and the CLI are still required. The whole port remains incomplete.

The data-stack runtime and complete persistent AVL list runtime now have first
production writing passes: all checked/unchecked entrypoints, epoch metadata,
rewind, growth and resizing, list edits/balancing/concat/slice, packed rows,
directories, snapshots and static tree/descriptor serializers. Ownership-aware
list stores/copies preserve the original allocation base in their flat recipes.
The list functionId adapter accepts a source field spelling and returns an
Option; data-stack modeCode preserves ordinals 0/1/2. These passes are unverified.

Project loading now has its first complete production writing pass, including
source/compiled/mixed/library loads, path decoding, aliases, diagnostics, DFS
order, prelude fixities, source budgets and freshOrder. Projects and syntax
Trees own concrete global typed table states; loader scratch stays lexical
outside its iterative traversal. Input providers are compile-time contexts
with canonical/read/resolve output-buffer methods and cause(Error)->bytes.
Diagnostic causes retain source error-name bytes; they do not serialize a
provider address. Lowering/checking io fields record IO presence as a bool.
Phase profiling and dependency relink remain forward dependencies not yet
written, and OS error/stream behavior and source/API parity remain unverified.
The whole port is still incomplete, and normal builds still select Zig.

Solver epoch/composite caches now have generation-checked pooled owner slots,
fixed EntryBuffer descriptors and shared scalar metadata. Their initPooled
returns Cache,Error; entries use .items/.len and restore preserves exact slots.
Epoch growth directly rehashes live entries into the new typed run without a
recursive lexical Grow owner. Checker Types/Effects owners are being aligned.

Principal interface bounds and graph validation have full first production
writing passes, including numeric/capability headers, selected proofs, source
record uniqueness, associated/implementation admission and iterative tri-color
cycle detection. Declaration demand and its shared global-reference walker are
also written: lexical shadowing, operator origins, reexports, namespaces,
conservative whole-unit fallback and source evaluation order remain explicit.
The manifest owns typed declaration runs; it never authorizes checked schemes.
No port compilation, execution, test, checker, lint or format verification has
run. All passes remain unverified and the production port is incomplete.

Public binding relocation, graph correspondence and complete hidden-method
source facts now have full first production writing passes. Typed method
sources borrow retained Core/current Checked owners; returned maps retain only
owned numeric correspondence and provenance spans. Exact sharing, source work
budgets, redacted slots and sparse capability roots remain admission checks.

Evaluator source-owner, body-recipe and lexical-input caches now have durable
pooled metadata. Each recipe record and immutable visit run survives later
cache growth; recipes.at(index) returns its stable record. Lexical input rows
use inputs.items; published key words and semantic mappings own separate runs.
Interfaces is a fixed typed map with explicit cleanup. Exact option-key work
charges occur per option, including partial construction at a limit. Session
factories and remaining consumers are being adapted. These source passes are
unverified, and no compiler/checker/test/lint/format execution has run.
