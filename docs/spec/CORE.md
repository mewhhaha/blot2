# Blot K1 — Compiler, checked artifacts and optimization

**Specification ID: K1-CORE. Edition: K1 revision 1, 26 October 2026.**
**Parent and full handoff:** [Language design program — issue #37](https://github.com/mewhhaha/blot2/issues/37). Read K1-LANG, K1-MEM, K1-CORE, and K1-EXEC together; the parent links every part.

**Edition:** K1 revision 1. **Status:** normative implementation target, not a claim about current Blot.
**Source baseline:** `1e39b5d8a4268b9edf769c2813d5231abe1c963b`.
The K1 language and memory specifications define source semantics and the physical ABI. This part defines how the compiler must establish, preserve and reuse those semantics. MUST, MUST NOT and SHOULD have their ordinary normative meanings. A later experimental optimization does not amend this contract.

## C01. Architectural boundary

K1 keeps the existing immutable, flat-table Core approach, dense owner-local IDs, typed stack IR, Wasm encoder and transactional revision publication. It introduces a completed semantic boundary before representation lowering. It does not require a new general-purpose backend.

There are three outputs, in this order:

1. A **CheckedInterface** states the complete callable/data contract.
2. A **CheckedFunction** implements that interface and contains all semantic choices and required evidence.
3. A **LoweringPlan** realizes an admitted representation without discovering omitted source semantics.

A compilation may calculate target layout feasibility while completing a function. It MUST NOT mark a function complete until all representation-dependent promises can be implemented by the unoptimized K1 baseline. Final physical registers, locals and offsets may be chosen later.

A failed optional optimization leaves a valid baseline implementation. An unsupported source construct, missing proof or unimplementable declared resource contract is a diagnostic before admission. The compiler MUST NOT silently fall back from K1 to the legacy language or counted-heap ABI.

Current `principal_interface.zig` is a useful owned, pointer-free foundation. Current `resolved_body.zig` is explicitly Generator-local; `code_artifacts.zig` contains one pinned backend run's IDs. Serializing either unchanged is not the new portable boundary. [C-S1], [C-S2], [C-S3]

## C02. Identity and ownership of compiler data

Every table index is relative to an explicit immutable artifact owner. Zero is reserved for “absent” only where the schema says so; a zero operand never supplies evidence. Cross-artifact references use a stable producer identity and validated table projection, not a process address, frontend interning number or hash-table insertion order.

A declaration identity comprises package identity, logical module path and declaration path. Nested functions add a structural path beneath their owning declaration. Whitespace does not alter that path; a structural edit may legitimately change it. A declaration's semantic identity is separate from the digest of its current implementation.

A generative domain or region in an artifact is an **abstract binder or introduction site**, never a concrete runtime-instance nonce. Substitution and package opening introduce fresh scoped identities according to the language rules. Reusing an artifact cannot make two dynamic graph constructions share endpoint authority. Canonicalizing equal layouts cannot equate their domains.

Artifact contents are immutable after sealing. Mutable unification state, worklists, hash indexes and temporary annotations belong to one completion job. They are destroyed or recycled as scratch; they never become durable evidence. Published artifacts own every variable-length table they expose. Diagnostic origins may point into a separately owned immutable source map, with its exact source identity recorded.

## C03. Small typed core

K1 uses typed A-normal computations: operands are already evaluated values; nontrivial computations name their results. Evaluation order is explicit. The grammar below is a semantic schema, not required Zig declarations or source syntax.

```text
Function   = binders, parameter_values, proof_parameters, contract, Blocks
Block      = label, typed_value_parameters, affine_state_parameters,
             evidence_parameters, Operations, Terminator

Operation  = results = constant(type, bits)
           | results = product(fields) | variant(tag, fields)
           | results = project(value, field)
           | results = destructure(value)
           | results = primitive(operation_id, arguments, evidence)
           | results = call(declaration_id, instantiation, arguments, evidence)
           | results = invoke(callable, arguments, evidence)
           | results = closure(code_id, environment, capture_contract)
           | results = pack(binders, witnesses, payload)
           | results = open(package, fresh_binders, lexical_scope)
           | results = refine(value, target_refinement, evidence)
           | results = ownership_or_storage(operation_id, arguments, evidence)

Terminator = jump(label, values, affine_states, evidence)
           | branch(condition, true_edge, false_edge)
           | switch(tagged_value, exhaustive_edges)
           | return(value, discharged_scope_state)
           | unreachable(required_reachability_evidence)

Value       = owner_local_value_id | immutable_global_constant_id
Type        = Unit | Bool | U32 | F32 | bound_type_parameter
            | Product(fields) | Sum(tagged_fields) | Result(success,error)
            | RegionOwner(R) | OwnedConstruction(R) | Space(R, state) | Dest(R,T,C)
            | EnvDest(R,C) | Builder(R,T,N,C,Mode)
            | View(R,T,N,D) | Index(D,N)
            | Fn(R,Mode,A,B,complete_contract)
            | Owned(payload_schema) | Package(binders,payload_type)
Evidence    = rule_id, conclusion, exact_value_arguments,
              scope_or_edge, prerequisite_evidence_ids
```

A function has one source parameter pattern; elaboration may introduce several Core parameters for its product fields and explicit hidden contracts. That transformation preserves source operand evaluation order. Explicit currying remains an actual function-producing stage.

Every operation has a registry entry containing operand/result schemas, effect/behavior classification, required propositions, ownership and initialization transition, failure representation, target feasibility rule and evaluator/lowering implementation. An operation ID names this entry and its semantic version. A familiar source spelling is not an operation ID.

Affine state parameters are the capability-typed subset of block parameters, not a second copy. Ordinary calls copy Share arguments and move affine arguments. Physical read-only input slots do not grant logical copying. Registered builtin observations may borrow. Affine product moves destructure the whole product; projection cannot invent partial-move state. Result is a distinct affine must-handle type, never Plain/Share. Packages separate stored Nat witnesses from erased Domain binders; source existential Type/Region is unsupported. Region reservation and OwnedConstruction introduction are internal structured-scope operations.

The registry includes the following normative families. `S` denotes an exact Space state, `B_n` an initialized-prefix builder, and `V_n` an exact immutable view. The memory specification owns detailed result variants and byte transitions; these schemas specify what the core must retain.

| Operation family | Inputs, evidence and output/state |
| --- | --- |
| Scalar compare / Boolean | Fixed scalar operands produce Bool; only the named intrinsic transfer rule creates edge facts |
| Checked U32 add/subtract/multiply/divide | Exact operands and required fits/nonzero evidence produce U32; wrapping variants have distinct IDs and facts |
| F32 arithmetic | Exact F32 operands, specified rounding/NaN policy; no implicit fast-math contract |
| `region.reserve` | Byte request produces failure or fresh owner plus Space; records reservation and identity generation |
| `region.try_alloc<T>` / `env.try_alloc` | Consume S; success returns successor Space plus Dest/EnvDest, failure returns unchanged S and error |
| `dest.split` | Consume parent destination; checked disjoint extents produce child destinations; no parent permission survives |
| `builder.begin_append` / `begin_resize` | Consume Dest and produce B_0 with fixed capacity/mode |
| `builder.append` / `try_append` | Consume B_n and element; required `n<c` or explicit failure; success B_(n+1), failure unchanged builder and unused element |
| `builder.set` / `truncate` | Exact initialized index or Resize mode with shortened extent; preserve initialization and invalidate incompatible versions/loans |
| `builder.freeze` / `discard` | Consume builder, require ended loans; publish initialized immutable extent or discharge construction permission |
| `view.read` / `try_read` | V_n plus refined index/required bounds or explicit fallible branch; never read reserved-but-uninitialized bytes |
| `view.slice` / `index.try_make` | Checked subrange/position validation; only the success branch gains the precise extent/domain refinement |
| `space.end`, `region.reset` / `close` | Discharge Space/derived permissions as specified; reset creates a fresh successor state, close ends owner authority |
| `owned.begin` / `seal` / `abort` | Begin a capsule-reserved construction with internal OwnedConstruction authority; seal its closed Share payload or release on failure; ordinary RegionOwner cannot substitute |
| `owned.open` / `close` | Lend a sealed owned payload lexically or consume/release the backing; no owner duplication |
| `fn.place` | Consume a statically sufficient EnvDest; copy admitted Share captures and attach checked code/resource contract |

Each family expands into a finite named registry entry per supported scalar/mode case. An admitted CheckedFunction stores exact entries and substitutions. No backend chooses an unrecorded overload. There is no user-accessible “assume safe,” raw pointer-to-capability conversion or unchecked `Index` constructor.

Effect classification separates at least observable effects, read/write regions, possible failure or divergence, reservation, ownership consumption, identity generation and cleanup. “Pure” is not a sufficient duplication, movement or deletion predicate. Immutable reads can be stable only for an exact validated view/version.

## C04. Core validation judgments

Validation is a checker over explicit information, not a second inference engine. It MUST establish:

- Every operand, table span, producer reference and operation ID is well formed.
- Types and kinds are fully bound. Call instantiations use explicit checked substitutions; no unresolved inference variable remains.
- Nominal data definitions are acyclic, including dependencies through Fn and View; a reference-shaped field does not legalize a recursive type.
- Every used value dominates its use. Block parameters bind incoming values before dependent propositions are checked.
- Each edge supplies exactly the destination's parameters and compatible ownership states.
- Every required proposition has a valid derivation in scope for the exact operands and versions.
- Every affine capability has one continuing owner path, or is discharged by the memory contract's move/close/authorized scope cleanup. It cannot disappear through a branch or duplicate through a product.
- Loans end before conflicting writes, consumption or reset. Returned values and captures satisfy their region/owner bounds.
- Initialization facts apply to the bytes actually accessed. Capacity is not initialized extent.
- Package openings and generative binders cannot escape their scopes except by an explicit valid package.
- Every normal source completion returns. Unreachable edges use the required reachability rules, not optimizer guesses.
- Calls preserve the advertised effects, failure and resource guarantees.

At a join, incoming identities are substituted into explicit join parameters. Only facts valid on every continuing predecessor may become join evidence. Returning predecessors do not contribute. Ownership joins are structural; a capability consumed on one continuing path cannot appear available afterward.

A K1 loop is an explicit finite-range header/backedge/exit with saved bounds, carries and capability states. Validate the declared invariant at entry, at `next` with iteration `i+1` and successor carries, and at `stop` with current i and supplied carries. Natural exhaustion establishes i=end; a possible stop does not. Exit joins introduce fresh local Nat witnesses where needed and retain the invariant intersection. Unstructured backedges and inferred fixed points are unsupported. A destination-building range records `initialized_length(builder)=i`, `i<=N<=capacity`, and body-edge `i<N`.

Evidence is a compact DAG. Nodes identify rule ID, proposition, exact operands, defining edge/scope and prerequisite evidence IDs. Operand substitution must be capture-avoiding and kind-correct. A Boolean “proved” flag, source assertion text or old optimizer receipt is not evidence. Rule checking may share validated subderivations, but sharing cannot change authority.

The validator is part of the trusted compiler implementation. A successful validator test is not itself a proof that the validator, allocator or encoder is correct. The qualification record separates those obligations.

## C05. Completed artifact schemas

### CheckedInterface

A CheckedInterface MUST own:

| Field | Required information |
| --- | --- |
| Header | K1 edition, semantic-policy version, interface schema version and producer identity |
| Binders | Ordered type, region, shape/domain and permitted contract parameters |
| Signature | Parameter/result types, call mode, capture/lifetime contract and required pre/postconditions |
| Effects/resources | Complete effects, reservation/cleanup properties, finite call-depth and peak K1 frame-byte bounds |
| Dictionaries | Explicit operation/layout requirements and their checked signatures |
| Layout premises | Mechanically derived LayoutFits requirements for declared aggregates, results, packages and environments |
| Data identities | Nominal identities, package/domain relationships and visibility rules needed by consumers |
| Dependencies | Exact semantic observations used to construct or validate the interface |
| Digest | Digest of canonical semantic bytes, separate from source origins and ABI realization |

A complete interface may be quantified. “Complete” means every remaining obligation is an explicit parameter or requirement, not that all types or lengths are concrete.

### CheckedFunction

A CheckedFunction MUST own:

| Field | Required information |
| --- | --- |
| Interface link | Exact producer/interface identity and digest |
| Body | Typed named values, explicit blocks/joins/exits and selected operations |
| Calls | Selected declarations or explicit dictionary/callable parameters; complete substitutions |
| Captures | Environment fields, source-value versions and usage/lifetime contracts |
| Ownership | Required region, destination, loan and cleanup transitions |
| Evidence | Finite derivation DAG and exact operation obligations |
| Staging | Required static results and their complete dependencies |
| Reuse | Body digest, semantic observations and required-work receipt |
| Origins | Rebindable source-origin map, distinct from semantic identity |

No selected call, capture layout class, obligation or implicit completion remains unresolved. An artifact cannot contain a mutable solver ID, Generator pointer, current-session nonce or permission to re-run overload selection.

### LoweringPlan

A LoweringPlan owns target ABI ID, representation-class substitutions, fixed call/result adapters, layout geometry, executable/static dependencies, resource realization and code-generation policy. It is target-specific. It MUST NOT change nominal/domain identity or reopen the source body.

The ABI is the memory specification's versioned K1 ABI. The plan validates every concrete adapter: parameter mode, result-slot layout, alignment, initialization, environment lifetime and no-backing-allocation obligations. A machine `i32` does not establish either a heap reference or a scoped address.

## C06. Required pass order

The compiler MUST expose these phases in tracing and work counters:

1. Parse and resolve source names, lexical targets and explicit declaration boundaries.
2. Check types against complete interfaces; instantiate calls and resolve operations.
3. Establish required numeric, data, ownership, initialization and resource invariants.
4. Evaluate explicit static work under the static policy.
5. Seal candidate interface/body artifacts; validate them independently of mutable completion state.
6. Publish completed semantic results transactionally to the current compilation attempt.
7. Optionally normalize/optimize validated bodies under the selected optimization policy.
8. Select validated representation parameters/adapters and lower to typed runtime IR.
9. Validate typed runtime roles and transitive helper dependencies; encode/assemble.
10. Publish the new successful revision atomically.

Required static evaluation can trigger prerequisite declaration completion, but cannot create a semantic feedback edge from ordinary emission. A deterministic dependency DAG orders those prerequisites. A cycle lacking a permitted explicit declaration rule is diagnosed, not handled by repeated speculative evaluation.

A closed-invalid declaration is rejected even if emission would later omit it. Optional constant folding cannot rescue missing source evidence or completion. Unsupported syntax receives a K1 diagnostic; it is not interpreted with legacy semantics.

## C07. Zero downstream general inference

After phase 6, the admitted-body path MUST forbid creation of a general inference region. Place the guard at the central creation seam, not merely one public lowering entry.

The current source has the appropriate counter and seam: `ClosureRegion.initWithSolverAllocatorAt` creates the solver; `Session.inquiry_regions` tracks active regions; `Session.counters.inference_regions` increments during destruction. Therefore qualification MUST enforce all three:

1. A creation attempt in admitted lowering is an internal error.
2. The active-region count is balanced at entry and exit.
3. The completed-region counter does not increase.

Counter delta alone could miss a still-open region. [C-S4]

The new path MUST NOT reach `bodyEvidencePartialFullCode` or `closureEvidencePartialCapturesCode` through the current specialization fallback. A missing semantic slot is a boundary bug, not permission to infer. [C-S5]

Moving repeated per-use inference earlier and renaming it “completion” does not meet this specification. Record body completions, interface instantiations and semantic versus executable instances separately. A body is completed once for its declared semantic parameters; ordinary calls consume that artifact.

## C08. Generics, dictionaries and staging

K1 generic functions use the language specification's explicit rank-1 binders. Their bodies are checked once under abstract parameters and explicit operation requirements. Ordinary locals do not silently generalize.

The baseline generic ABI uses **uniform indirect bounded values**, caller-provided result slots and immutable layout dictionaries. `T:Type` is conservatively affine: forwarding consumes its logical owner; copying requires an explicit Share/Plain constraint. A read-only slot does not implicitly authorize a logical copy. There is no hidden drop vtable. Plain array elements have the separate narrower layout cap. Required operations are explicit checked function records. Dictionaries originate from admitted type/layout/callable information; source code cannot fabricate one. The memory specification fixes byte fields and bounds.

Declared type constructors generate explicit `LayoutFits` well-formedness premises: every aggregate/result/environment fits 256 bytes and every Plain element fits 64 bytes. At generic instantiation, evaluate the fixed declared layout schema against admitted dictionary sizes and reject incompatible uses with `k1_layout_limit`. This is bounded layout calculation, not an arbitrary user theorem or source-body recheck. A generic `Result<T,E>` is available when its sum layout fits; `T` occupying all 256 bytes plus a result tag does not fit. Generic frame planning may reserve a 256-byte slot only after these premises are established. Packages count reified witness storage as part of their layout.

A generic `map_into` may pass a borrowed initialized input-element slot to its callback and an exclusive output-element slot as the callback result destination. The callback contract must establish complete initialization on success and preserve the failure/capability protocol. No per-element box is required. A callback with a reservation effect cannot satisfy a no-backing-allocation interface.

There is one baseline executable generic body per declaration and target ABI. Ordinary length, capacity and domain arguments do not create machine instances. Concrete nominal identity stays in semantic substitution even when code representations are shared. K1 revision 1 does not add speculative representation stenciling; adapters are keyed by declared callee and fixed ABI transition, never by a caller's incidental layout request.

Known monomorphic scalar calls can use the scalar ABI declared in their completed summary. Aggregate parameters/results use the memory ABI's by-reference/result-slot convention. No baseline tuple flattening, implicit uncurrying or caller-driven layout discovery is required. Later flattening changes need a new qualified ABI summary and executable dependency.

Every callable has `resources {depth: D, frame: S}` with closed integer upper bounds at its public/parameter interface. K1 has no resource polymorphism. Local acyclic functions/lambdas can synthesize these bounds. A leaf has depth at least one; each direct or indirect call requires `caller.depth >= 1 + callee.depth`. Callable coercions may widen bounds, never claim a smaller unchecked bound. Named recursive binding components are rejected. Higher-order cycles cannot satisfy a strictly decreasing finite depth, even if the named dependency graph is acyclic.

Before admission, compute a conservative own-frame bound including aggregate temporaries, result slots, adapters and environment storage, then require `own_frame + max(callee.frame) <= caller.frame`. Scoped region allocations are accounted separately from this frame sum. Generic frame planning uses supported worst-case geometry if an exact size is unavailable. `frame` measures K1-managed linear-memory frames, not an engine's machine stack. The K1 target profile caps depth at 128. Export wrappers preflight the fixed frame arena and supported call-depth envelope; host/engine capacity is an explicit deployment assumption. Optional slot reuse/inlining cannot rescue an inadmissible baseline frame contract.

Explicit static evaluation is deterministic and sandboxed from I/O, clocks, host allocation observations, foreign callbacks and mutable runtime state. Its permitted subset is closed constants, admitted pure scalar/product/variant operations, finite loops and calls to static-compatible complete functions. Static code cannot manufacture runtime owners, addresses or witnesses for future mutable values. Results own canonical bytes; captured runtime identities are rejected. Required-static F32 NaN-producing arithmetic selects positive canonical quiet NaN `0x7fc00000`, a permitted member of the runtime Wasm result set; this choice belongs to the static policy. Non-NaN rounding remains exact.

Required-static Plain array literals are admitted constant data, charged by element evaluation and produced bytes. Their immutable storage belongs to the module's static memory map; their Domain is an abstract module-instance identity. This does not grant runtime placement, mutable storage or captured foreign region authority.

A source-required static initializer is checked and evaluated whether or not runtime code generation later uses it. Static failure or exhaustion is a diagnostic for that declaration. Optional constant folding may decline and preserve runtime computation; it must not execute additional source-visible effects.

## C09. Versioned work limits

These are initial engineering limits, not performance predictions or mathematical complexity claims. They form `K1-SEM-POLICY-1`; changing a required limit changes the policy ID and admission keys.

| Required completion quantity | Per-declaration maximum |
| --- | ---: |
| Total charged semantic traversal visits | 1,048,576 |
| Core operations, including terminators | 65,536 |
| Core blocks | 4,096 |
| Frozen type-graph nodes | 8,192 |
| Type/structural nesting | 64 |
| Explicit generic binders | 32 |
| Proof term nodes | 4,096 |
| Combined fact/evidence edges | 16,384 |
| Charged proof visits | 65,536 |
| Required static primitive steps | 100,000 |
| Required static call depth | 128 |
| Required static produced immutable bytes | 4 MiB |

A limit exhaustion reports the obligation/declaration and the relevant measured quantity. Invalid, insufficient, unsupported and exhausted reasoning remain distinct diagnostic categories. There is no automatic optimizer-mode-dependent retry with a larger required budget. Explicitly changing a semantic policy is a configuration change, not a cache trick.

Charge the total before every AST/Core/type/effect/usage/exhaustivity/layout/constraint node or edge visit, including helper loops and repeated visits. Proof work charges both its dedicated limit and this total. Hitting the total reports `k1_semantic_limit`; it cannot hide in an uncharged subroutine. Stable work accounting prevents worker scheduling from allocating different leftover budgets. Complete declarations in deterministic acyclic order; no unbounded effect/type fixed point is inferred.

Input limits are 16 MiB UTF-8 per source module, syntax nesting 64, 4,096 modules and 65,536 import edges per project. Enforce byte/nesting limits before recursive parsing/walks and graph limits during deterministic import traversal; report `k1_source_limit`. Module/name work uses input-bounded tables/worklists, not repeated path enumeration. These limits belong to the same versioned semantic policy.

A retained result includes its policy ID and deterministic logical-work receipt. A verified cache hit is equivalent to the same successful fresh algorithm under that policy. Cache warmth cannot make previously unsupported reasoning legal. Artifact validation checks required structural limits even when no expensive source work is repeated.

Hard input/artifact byte bounds are validated before allocation: 16 MiB per serialized interface/function object and checked table-span arithmetic. Oversized source-derived objects diagnose; oversized optional cache objects are discarded. An external required artifact outside supported limits diagnoses. Process OOM is reported separately from semantic budget exhaustion and must preserve the previous successful revision.

Optional optimization uses `K1-OPT-POLICY-1`. Let `N` be the admitted operation count before optional rewriting:

| Work | Default limit |
| --- | ---: |
| Local optimization visits, including helper traversals | `8*N + 1024` |
| Successful local rewrites | `N + 256` |
| Local normalized output | At most `N + 64`, also within hard Core bounds |
| Release inlining callee size | 32 operations |
| Release inline depth | 2 |
| Release inline sites per caller | 16 |
| Total inline growth | At most 25% of caller, capped at 256 operations |

Optional limits are checked before allocating expanded state. Exhaustion keeps the last validated candidate or the admitted baseline. Revalidation exhaustion also discards the optional candidate; it cannot reject an otherwise admitted source. An invalid transformation is an internal compiler error and a failing regression, not an ordinary budget decline to hide.

The new retained completed-artifact cache has a default 128 MiB payload cap, 16,384 records, and 4,096 candidate/dependency visits per lookup. Existing cache families remain separately reported and bounded. Cache saturation/eviction declines reuse and performs correct fresh work. These cache limits never alter source acceptance.

## C10. Default optimizer and rewrite laws

The default optimizer is one deterministic function-local schedule:

1. Establish explicit def-use and selected-operation facts once.
2. Traverse blocks in deterministic reverse-postorder; use a stable FIFO rewrite worklist.
3. Apply the finite local catalogue below.
4. Revalidate changed ownership/evidence and origin mapping.
5. Lower once; run only ABI-compatible typed-stack cleanup.

There is no module-wide saturation loop, general theorem search, implicit partial evaluation or unbounded specialization. Region ownership and no-RC properties are true before optional optimization.

| Rule ID | Transformation | Mandatory premises |
| --- | --- | --- |
| R01 | Empty administrative block/target elimination | Same exit target, no meaningful cleanup/loan/package boundary |
| R02 | Returned block value to direct return | Correct lexical target and identical exit obligations |
| R03 | Known identity forwarding | Arguments already evaluated once; preserve captures and authority transitions |
| R04 | Product projection forwarding | Preserve all operand evaluation and required cleanup; no discarded fallible work |
| R05 | Known branch selection | Preserve condition evaluation; retain only the actually unselected computation's elimination |
| R06 | Copy/constant propagation | Exact immutable value identity; no duplication of capability or identity generation |
| R07 | Literal numeric evaluation | Exact selected scalar semantics, including checked U32 validity and F32 bits/rounding policy |
| R08 | Immutable length reuse | Same view/version and no repeated effectful accessor |
| R09 | Exact store/read forwarding | Same exclusive place/version, established initialization and no intervening disturbing operation |
| R10 | Descriptor elimination | Preserve view extent/domain, construction consumption and every required validation |
| R11 | Known callable direct invocation | Known code identity and identical environment/capture contract; no fresh inference |
| R12 | Dead primitive removal | Whitelisted total, effect-free, nongenerative operation without ownership/cleanup obligation |

An overloaded or similarly named function does not inherit these laws. K1 checked arithmetic cannot use wrapping identities unless their preconditions establish equivalence. F32 identities such as `x+0=x` are not universally valid; no reassociation, relaxed contraction or FMA substitution is enabled by default.

Private placement can be removed/reused only when source-visible logical capacity, cursor and failure behavior is unchanged. Explicit reservation/capacity failure and destruction/resource actions remain observable according to the memory specification. Profiling counters are diagnostic, but are not permission to erase semantic events.

CSE cannot merge fresh domains, unique owners or reservations. Loop motion cannot execute failing work on a path with zero iterations. Slot reuse cannot extend a view/closure lifetime or authorize uninitialized reads. Implicit frame environments have their defining block/iteration activation lifetime; loop-carried escaping closures require explicit longer-lived placement.

Release-only inlining, scalar replacement, fusion and SIMD use individually qualified rules under the same bounds. A producer-into-destination API already specifies interleaved construction. Replacing two eager maps with that API requires proof of callback order, failure/divergence, intermediate observation and resource behavior. Unknown-size filter counting cannot execute an arbitrary predicate twice. Current exact/pipeline builders are useful bounded-pattern references, but their legacy allocation roles must be requalified. [C-S6]

## C11. Dependency and cache semantics

Maintain separate dependency identities for semantic interface, implementation body, required static value, ABI/layout summary, capture graph, selected operation/provider and source origins.

A body edit with an unchanged complete interface MUST preserve callers' semantic judgments unless they consumed that body or another changed semantic fact. Inlined code and ABI/static consumers still invalidate. Negative lookup observations are dependencies: adding a formerly absent declaration/provider can change a decision. Imported nominal and operation producers remain exact.

The query engine records ordered observations actually read, including declaration dependencies, recursion-admission facts and compiler-policy identity. A lookup hash selects candidates only. Exact supported comparison and dependency admission establish validity. Unsupported comparisons decline reuse. Reuse cannot widen an allowed proof fragment or substitute one region/domain for another.

Canonical artifact encoding is versioned and deterministic: explicit tag values, length-delimited UTF-8 strings, fixed-endian integers, sorted external-reference tables and canonical owner-local numbering. It includes all semantic and ABI versions; diagnostic origins are separately keyed. Host pointers, hash iteration order and private solver cursors are forbidden. Use the repository's BLAKE3 infrastructure for fingerprints; digest equality alone does not authorize unsafe decoding or bypass structural validation.

A work receipt is authority only when retained in an immutable object sealed by the trusted current completion process. Untrusted disk/imported bytes cannot assert a cheap required-work history. For source-backed cache candidates without trusted provenance, recompute required source admission under the same policy before promotion. Otherwise a forged small receipt could make a warm cache accept a source that fresh checking exhausts. A required source-less CheckedCore import is instead validated as an explicit artifact input under the artifact policy; it does not assert fresh source-check parity for unavailable source.

Executable trust is separate. An accepted interface, hash or structural Core certificate does not validate arbitrary attached Wasm/native bytes. K1 v1 ignores and locally rebuilds externally supplied executable payloads from admitted CheckedCore unless trusted build provenance independently authorizes those exact bytes. No new signature system is required. Current-process encoded artifacts remain immutable and tied to the exact validated lowering input.

A malformed or stale optional cache entry is dropped and rebuilt from source. A malformed required source-less import receives `k1_invalid_artifact` or `k1_incompatible_artifact`. A compiler-generated invalid fresh artifact receives an internal error and is never published. These outcomes are intentionally different.

Compilation attempts publish atomically. Interrupted work, OOM, failed validation and failed edits cannot replace the last successful revision. Retained results are immutable and may be shared between jobs. Parallelism follows independent completed interfaces; no worker owns mutable solver state shared with another worker.

## C12. Backend and trusted boundary

The K1 backend consumes scoped-pointer provenance and ownership contracts distinct from existing RC references. Machine type equality is insufficient to cross that boundary. It MUST validate transitive helper dependencies and reject a K1 module path reaching legacy retain/release, graph-collection, root-journal or counted-allocation helpers.

No-backing-allocation calls must reach only helpers with the corresponding admitted contract; a wrapper does not hide reservation or a closure box. Required checks cover initialization, byte-size/address overflow and object extent, not merely global Wasm linear-memory bounds.

The existing typed stack emitter and pure local passes may be reused after their assumptions are checked. Current region helpers require RC/root machinery, and current runtime optimization performs lifetime/RC work even in development. They are not the new scoped implementation. [C-S7], [C-S8]

Proof erasure occurs only after the validator and ABI checks establish the corresponding operation contract. Runtime integers, lengths, capacities and descriptors needed by execution remain. A debug defensive check may remain, but source validity cannot depend on its presence or optional elimination.

The compiler's preservation obligations are separate:

1. Elaboration produces a well-typed, initialized and ownership-valid core.
2. Each rewrite preserves observations and required invariants.
3. Lowering implements the core's arithmetic, memory and control operations.
4. Runtime primitives and host wrappers meet their declared contracts.

K1 revision 1 requires written operational rules, tests and explicit trusted assumptions. It does not claim a mechanized whole-compiler proof. Research such as ANF/join points, bidirectional checking, ISLE/VeriISLE and CakeML informs these obligations without becoming mandatory runtime machinery or global SMT search in ordinary builds.

## C13. Required telemetry and acceptance

Report source completion count, general inference region creations/active balance/nodes, interface instantiations, proof terms/edges/visits, static steps/bytes, semantic versus executable instances, adapter count, rewrite visits/applications/declines, generated size, dependency invalidations, cache admission work and retained bytes.

Guest telemetry separately reports backing reservations/failures, region reset/release, result/scratch high-water bytes, initialized/copied bytes, calls/loops and any RC/collector/root-helper dependency. Legacy heap counters cannot see all new region storage; zero old counters alone is not a certificate.

The implementation plan defines concrete laws and workloads. Acceptance requires the same source judgment across check/build, tiers, cache states and worker schedules; zero downstream inference; no hidden managed path; valid failure cleanup; bounded optional work; and source/ABI identity-correct reuse. Measurements must separate instrumented attribution from uninstrumented paired timing. No speedup is claimed from this specification alone.

## Pinned implementation references

[C-S1]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/reuse/principal_interface.zig
[C-S2]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/backend/resolved_body.zig
[C-S3]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/reuse/code_artifacts.zig
[C-S4]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/eval/core_eval.zig#L7001-L7048
[C-S5]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/eval/specialization.zig#L250-L274
[C-S6]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/backend/pipeline_builder.zig
[C-S7]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/runtime/region_runtime.zig
[C-S8]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/backend/runtime_pipeline.zig

