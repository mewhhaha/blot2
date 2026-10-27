# Blot K1 — Implementation-agent execution and qualification plan

**Specification ID: K1-EXEC. Edition: K1 revision 1, 26 October 2026.**
**Parent and full handoff:** [Language design program — issue #37](https://github.com/mewhhaha/blot2/issues/37). Read K1-LANG, K1-MEM, K1-CORE, and K1-EXEC together; the parent links every part.

**Edition:** K1 revision 1. **Status:** executable work specification; no implementation or new qualification is claimed here.
**Reviewed source:** `1e39b5d8a4268b9edf769c2813d5231abe1c963b`.

## I01. Instructions to the implementing agent

Implement the K1 language, memory and compiler contracts in their stated order. The tracking issue is the index; its linked specification parts are the normative handoff. “Should be safe” is not acceptance evidence. A successful baseline must establish required contracts without optional optimization, runtime reference counting or a legacy fallback.

Before editing, inspect the actual checkout, current branch, working-tree status and `AGENTS.md`. Read `compiler/guide.md`, `zig-native/CONTRACT.md`, the linked specification and the current qualification documents. Record the starting commit and any differences from the reviewed pin. Preserve unrelated changes. Use an isolated branch/worktree when needed; do not overwrite the user's existing work or reset it to the reviewed commit. Repository instructions in force at implementation time still apply. [I-S1]

Create an implementation ledger with task IDs, changed files, passed laws, remaining limitations and exact command evidence. Proposed new files below are organization targets, not a demand to duplicate equivalent existing abstractions. Prefer extending an existing owned representation when its invariants fit. Explain any renamed target in the ledger so another agent can find it.

Do not solve a hard contract by silently widening the proof fragment, inserting a trap, introducing RC, increasing a required budget, deleting a negative test, changing an operation's identity or depending on release optimization. A normative contradiction requires a small explicit specification amendment and corresponding laws. Ordinary naming, local data-structure choices and equivalent implementation details need no interruption.

K1 must be an explicit language/ABI edition in the request, project metadata and every artifact key. The initial CLI selection is `--language=k1`; legacy remains the existing default until I10's migration gate. Imported K1 and legacy managed objects cannot cross the typed boundary implicitly. The existing `--require-collector-free` flag retains its current meaning; it is not renamed into a no-RC certificate. Unknown edition or incompatible import diagnoses before body lowering.

## I02. Baseline and source map

At the reviewed pin, Blot already has immutable Core, principal interfaces, numeric proof infrastructure, owned reuse records, destination builders, numeric aggregate layouts, rectangular pipeline fusion, collector-free certification and memory-cost attribution. The last group closes existing work including #28/#32/#33/#35/#36. Preserve their regressions; do not reopen them as features K1 has yet to invent. Their current runtime still includes managed allocation/RC assumptions. [I-S2]

Use this implementation map:

| Concern | Existing entry points | Proposed K1 ownership |
| --- | --- | --- |
| Source grammar | `parse/lexer.zig`, `parse/parser.zig`, `parse/ast.zig`; `compiler/parser_source.ts`, formatter, editor grammar | Edition-aware syntax and source diagnostics |
| Checking/Core | `check/check.zig`, `check/core.zig`, `check/frozen_core_validation.zig` | `check/k1_contracts.zig`, `check/k1_core_validator.zig` |
| Numeric proofs | `check/numeric_proof_terms.zig`, `numeric_proof_contracts.zig`, `numeric_proof_core.zig` | Required evidence consumer and versioned budgets |
| Portable completion | `reuse/principal_interface.zig`, `principal_type_graph.zig`, `declaration_dependencies.zig` | `reuse/k1_checked_function.zig`, `reuse/k1_artifact_format.zig` |
| Evaluation | `eval/core_eval.zig`, `eval/specialization.zig` | Completion phase guard and explicit static evaluator |
| Lowering | `backend/resolved_body.zig`, `runtime_ir.zig`, `runtime_pipeline.zig`, `wasm.zig` | `backend/k1_lowering_plan.zig`, scoped roles and fixed ABI adapters |
| Storage | `runtime/runtime_layout.zig`, `region_runtime.zig`; exact/ragged/pipeline builders | New `runtime/k1_scoped_pool.zig` and `runtime/k1_scoped_runtime.zig` |
| Reuse | `reuse/semantic_query_table.zig`, `revision_inputs.zig`, `retained_revision.zig`, archive/import modules | Completed-artifact admission, precise dependencies and atomic publication |
| Qualification | Native suites, `zig-native/tests/`, `scripts/dev_check_areas.ts`, `scripts/test_compiler.ts` | Explicit K1 inventories, guests, faults and reports |

Paths in the middle column are relative to `zig-native/src/` unless explicitly prefixed otherwise. The new scoped runtime is deliberately separated from old helper contracts; reusing algorithms is permitted, inheriting incompatible ownership roles is not.

## I03. Work order and integration rule

The sequence is **admission → completion → proofs → storage → relational packages → closures → ownership → generics → reuse/optimization → rollout**. Each stage ends in executable positive and negative laws. A stage may implement a narrow coherent subset, but cannot publish a successful K1 artifact containing promises delegated to a future stage.

Delegate disjoint work after the common contracts are frozen: one agent owns language/proofs, one runtime/ABI, one artifacts/lowering, and one integration/tests when capacity permits. Give each agent exact files and test IDs. Shared schema edits have one owner. Integrate the schema first, then consumers, then guests. Parallel branches must not independently invent operation IDs, source syntax or owner transitions. The integrator reruns affected laws after conflict resolution.

### K1-00 — Freeze admission, schemas and diagnostics

Add edition and semantic/ABI/policy IDs to request configuration and artifact headers. Write the operation registry, diagnostic catalogue, supported/deferred feature table and a compact normative contract document under `zig-native/`. Expose `K1-SEM-POLICY-1`, `K1-OPT-POLICY-1` and `K1-WASM32-ABI1` in the compiler, not scattered magic constants.

Create K1 fixture builders and register their inventory in the existing native/guest harness. Add a phase trace with completion, static evaluation, validation, optimization and lowering. The stage is complete when an admitted scalar function compiles and executes, unsupported syntax diagnoses, and both edition mismatches and forged artifact headers fail before unsafe decoding. No collection or closure feature is advertised yet.

### K1-01 — Coherent syntax and explicit completion

Implement the specified `fn`, `return`, `do`/`break`, binding, call, type-application and array spellings in native parsing, formatter and editor grammar. Source spans and lexical return/break targets must survive elaboration. Do not fix the generated parser output manually; regenerate it from its source.

Implement completion judgments before optimizations: all reachable normal exits return; `Unit` functions also use explicit return; a value block has its own break target. Specify left-to-right operand order. Add accepted nested-return/block examples and rejected implicit-tail, wrong-target and missing-path examples. Formatter round trips preserve the same AST/targets, not just visually similar text.

### K1-02 — Complete functions and a checked scalar core

Introduce the three owned artifact schemas and independent validator. Admit constants, products/sums, explicit branches/joins, scalar operations and direct acyclic calls. Freeze types, effects, selected operations, origins and resource contracts. Validate artifacts after their mutable checker state is destroyed in a test.

Install the general-inference prohibition at `ClosureRegion.initWithSolverAllocatorAt`, not only a top-level compiler entry. Record active regions and completed-region deltas. Force the old specialization fallback in a negative internal test and verify that admitted lowering rejects it. A successfully reused body must not invoke `bodyEvidencePartialFullCode` or `closureEvidencePartialCapturesCode`. Test higher call-site counts independently of body completion counts. [I-S3], [I-S4]

### K1-03 — Required proofs and storable indices

Extend the existing bounded term/fact machinery with the specified K1 transfer rules. Implement required versus optional consumers separately. Required indexing must produce evidence or a diagnostic; it cannot retain a hidden runtime trap as success. Cover exact SSA versions, guarded branches, early exits, short circuiting, join intersections, checked arithmetic and canonical loops.

Add `Index<D,N>` as an ordinary stored U32 refinement, distinct from erased proposition leaves. Its validated constructors, projected loads and ABI schema preserve authority. Implement proof policy receipts and exact limits; enumerate work charged by each traversal. This stage is complete only when the same source judgment holds in check/build, default/release, cold/warm and single/multiple-worker tests.

### K1-04 — Scoped pool, destinations and the particle vertical slice

Implement the memory specification's fixed pool/frame arenas, owner slot/generation metadata, byte checks, placement, destinations, append builder, read-only view, freeze and scope cleanup. Begin with Plain U32/F32 rows, then the bounded product/sum layouts. Reservation failure and capacity failure must preserve the exact capability state required by their result types.

Add distinct runtime-IR roles for scoped addresses/descriptors. Compile and execute the particle workload described in I08 with optimization disabled. It must use scalar field loads, scalar arithmetic and direct destination stores. No hidden row allocation, counted heap helper, retain/release or per-element backing reservation is permitted. This is the first useful no-GC/no-RC storage milestone; zero legacy counters alone does not qualify it.

### K1-05 — Relational graph packages

Implement package introduction/elimination, rigid fresh domains, stored endpoint refinements and complete imported package contracts. Build frozen nodes, validate raw endpoints once, construct edges in a disjoint destination and seal a graph. Traversal consumes the stored invariant without validating every endpoint again.

Test repeated constructor calls at the same source site, loop iterations, opening two packages, imported constructors, endpoint failure halfway through construction and zero-node graphs. Equal numeric lengths/layouts cannot equate domains. Required laws are scope/identity laws, not only correct output on one graph.

### K1-06 — First-class functions and finite frames

Implement the fixed code/environment pair, Share-only captures, lexical environment placement, complete `Many`/`Once` call contracts and direct-call adapters. Captures use immutable value versions. Destination-returned closure environments must satisfy their enclosing lifetime; no managed closure box is an escape hatch.

Every callable carries `resources {depth: D, frame: S}`, closed integer bounds in public/parameter interfaces. K1 has no symbolic resource polymorphism. Reject named recursion and validate that every direct/indirect call decreases the available depth bound, within the target profile's depth cap of 128. Compute conservative local frame storage before admission and compose it with callee bounds. Test callback-hidden cycles, widened resource contracts, insufficient arena capacity and closure contracts imported from artifacts. A leaf has positive depth; a finite range loop does not consume another machine frame each iteration. Frame bytes are K1 linear-memory storage, with engine stack capacity stated separately in the host envelope. Nominal data definitions remain acyclic even through Fn/View fields.

### K1-07 — Whole-region ownership and host bridges

Implement the memory chapter's affine `Owned<P>` operations, single-backing restriction, scoped borrow and explicit cleanup. Captured owners and owner-containing array elements remain rejected. Test moves through branches/results, all early exits, valid owned immutable closures, forbidden `Owned<FnOnce>`, and borrow-before-close conflicts.

Start exported execution with the scalar ABI, then complete the mandatory copy-only Plain-array host bridge. Validate host descriptors and raw bytes before creating typed values, and copy results before closing the owner. The host never fabricates a scoped pointer, index brand or closure code handle. Reentrant/asynchronous/zero-copy host extensions remain unsupported unless separately specified and qualified.

### K1-08 — Rank-1 generics and explicit staging

Implement explicit binders and dictionaries, monomorphic locals, uniform indirect baseline calls and fixed adapters. Generic `T:Type` is conservatively affine; copying requires the stated Share/Plain contract and dropping cannot be smuggled into a dictionary. Qualify aggregate results, callback result slots, fixed layout bounds and type/region/domain substitution across imports.

Add the required static evaluator and its deterministic depth/step/byte limits. Complete called static interfaces first; reject runtime identities and host effects. Static success/failure must not depend on whether ordinary code generation later uses the declaration. Show that many type/length/domain uses share the promised baseline body and that no caller invents a new representation class.

### K1-09 — Local optimization, reusable artifacts and transactions

Implement the compiler chapter's finite rewrite catalogue and deterministic schedule. Revalidate each changed candidate. Add exact dependency observations, negative reads, canonical serialization, source-origin rebinding and bounded cache admission. A body-only edit with unchanged complete interface must cut off semantic caller recompletion; consumers of body/static/ABI facts still invalidate.

Inject interruption, backing OOM, corrupt cache entries and publication failure. Preserve the last successful revision and all owned storage. Optional budget/cache decline uses valid fresh/baseline work. Invalid freshly generated artifacts and unsound rewrites are compiler errors, not silently ignored cache misses. Release-only transforms are separate optional tasks after the default kernel qualifies.

## I04. Diagnostic and law inventory

The names below use the language chapter's closed diagnostic catalogue. Tests assert the exact category, relevant source span and invariant, without snapshotting incidental prose. Accepted tests assert semantic/Core/runtime properties as appropriate, not merely process exit zero. The implementing agent does not choose alternative categories for the same law.

| ID | Fixture | Required result |
| --- | --- | --- |
| SYN-A01 | Both short and block functions explicitly return | Accepted; identical result and lexical target |
| SYN-R01 | Normal function path ends with a value expression | `k1_missing_return` |
| SYN-R02 | `break` targets an unavailable value block | `k1_bad_control_target` |
| BND-A01 | `if i<a.length` then direct `a[i]` | Accepted; required evidence precedes lowering |
| BND-A02 | Guard's false path returns before indexing | Accepted; continuing path retains the fact |
| BND-R01 | Unconditional unknown `a[i]` | `k1_bounds_not_established` |
| BND-R02 | `a.length<N` and `i<N` used as index proof | `k1_bounds_not_established`; include `n=3,i=7,N=10` control |
| BND-R03 | Facts from one continuing branch used after join | `k1_bounds_not_established` |
| BND-R04 | A similarly named Boolean helper has no predicate contract | `k1_bounds_not_established` |
| BND-R05 | Fact belongs to old rebound/shrunk view | `k1_bounds_not_established`; identify invalidated version |
| BND-R06 | Source index is below capacity but outside/unproved against initialized prefix | `k1_bounds_not_established` |
| PRF-R01 | Required evidence exceeds the specified finite fragment or charged limit | `k1_unsupported_fact` or `k1_proof_limit`; never runtime-trap fallback |
| NUM-A01 | Checked increment after a sufficient no-overflow guard | Accepted; distinct result identity |
| NUM-R01 | Unproved checked U32 arithmetic | `k1_arithmetic_not_established` |
| NUM-A02 | Explicit wrapping addition | Accepted; no unsound monotonicity fact created |
| MEM-A01 | Fill exactly N slots, then freeze | Accepted; initialized prefix equals N |
| MEM-R01 | Validator fixture publishes a partially initialized typed product | `k1_incomplete_initialization` validation cause; required external artifact reports `k1_invalid_artifact` with that cause |
| MEM-R02 | Reuse a consumed destination/builder/owner | `k1_use_after_move` |
| MEM-R03 | Mutation, freeze, reset or close conflicts with a live loan | `k1_loan_conflict` |
| MEM-R04 | Return a view/closure into a local dead region | `k1_lifetime_escape` |
| MEM-A02 | Failed reservation/append handled by its result | Accepted; exact promised predecessor state restored |
| MEM-A03 | Zero-size Plain row and zero capacity | Accepted without bogus address arithmetic or division |
| ERR-R01 | Fallible result is silently ignored where the language requires handling | `k1_unhandled_result`; no lost affine payload |
| DOM-A01 | Validated graph endpoints stored and loaded | Accepted; no repeated traversal validation |
| DOM-R01 | Endpoint from another same-sized graph, including same constructor site | `k1_domain_mismatch` |
| DOM-R02 | Open-package brand escapes without repackaging | `k1_lifetime_escape` |
| FN-A01 | Borrowed immutable closure through a higher-order loop | Accepted; one scoped environment, no per-element box |
| FN-R01 | Ordinary closure captures affine authority | `k1_invalid_capture` |
| FN-R02 | Invoke `Once` twice | `k1_use_after_move` |
| FN-R03 | Named recursive binding component | `k1_recursive_call` |
| FN-R05 | Callback-hidden cycle under finite contracts | `k1_resource_bound` |
| FN-R04 | Unknown/undersized callable frame or depth contract | `k1_resource_bound` |
| FN-R06 | Implicit frame environment carried beyond its loop/block activation | `k1_lifetime_escape`; explicit longer-lived EnvDest is the alternative |
| OWN-A01 | Move an owner, borrow its Share payload, close after borrow | Accepted; one backing release |
| OWN-R01 | Multi-backing payload or `Owned<FnOnce>` | `k1_invalid_owned_payload` |
| OWN-R02 | Alias/duplicate an already moved owner | `k1_use_after_move` |
| GEN-A01 | Generic affine identity and Plain map | Accepted; fixed body count and correct logical consumption |
| GEN-R01 | Copy or silently drop unconstrained generic T | `k1_usage_not_permitted` |
| GEN-A02 | Generic Result<T,E> whose declared LayoutFits premises hold | Accepted; bounded dictionary calculation, no body recheck |
| GEN-R02 | Result around an already 256-byte generic T | `k1_layout_limit` before admission |
| STA-R01 | Required static budget exhausted in unused declaration | `k1_static_limit` in all modes |
| ART-R01 | Required artifact with invalid span/evidence/domain/substitution | `k1_invalid_artifact` |
| ART-A01 | Same malformed object supplied only as optional cache | Cache rejected, valid fresh result produced |

Boundary fixtures include 0, 1, maximum U32, exact length, length minus one, full capacity, alignment boundaries, maximum Plain geometry and the first unsupported geometry. Do not generate impossible huge host arrays merely to test arithmetic; exercise checked planners and bounded guest fixtures separately.

## I05. Compiler and optimizer laws

**CMP-01:** after semantic sealing, solver creation is forbidden, the active-region count balances and completed-region count is unchanged. Run direct calls, indirect calls, closures, generic arrays, packages and imported functions through this test.

**CMP-02:** check/build and every optimization tier agree on acceptance/diagnostic category. A warm cache, work queue order or worker count cannot make an exhausted required proof pass. Add exact-at-limit and one-over-limit fixtures for every required policy quantity.

**CMP-04:** total semantic traversal, source-size/nesting and import-graph limits charge helper work and report `k1_semantic_limit`/`k1_source_limit`. Repeated type/effect/usage/layout visits cannot evade the total by staying below stored-node caps. Required static NaN results are deterministic under the fixed canonical policy.

**CMP-03:** destroy producer scratch before validation/emission. Relocate imported artifact table IDs, force hash collisions, vary unrelated declaration order and retain/reopen the session. Output and authority remain correct. No host pointer or solver ID is serialized.

**CTL-01:** carry `next` checks the successor invariant; `stop` checks the current-iteration invariant. A stopped builder cannot acquire the exhausted range's final length. Existential packages preserve their explicit Nat prefix across calls/imports; payload field moves and affine Result handling cannot be erased by aliases or projection.

**OPT-01:** differential execution of baseline and each enabled rule preserves integer/non-NaN scalar bits, sum tags, branches, returned bytes and specified failure/capability traces. F32 controls include signed zero, infinities, NaNs and rounding-sensitive arithmetic. Arithmetic NaN tests validate the allowed result set; copies/loads/stores preserve NaN bits and negation changes only the sign. Do not use epsilon comparisons to excuse a forbidden rewrite.

**OPT-02:** zero-iteration loops do not execute hoisted failing work; dead-code removal preserves reservation/failure/generation/cleanup; fusion preserves callback count/order and early failure. A map/filter predicate with effects provides a negative fusion control.

**OPT-03:** force each optional budget to exhaust before and during a rewrite. The emitted baseline remains correct, no allocation leaks occur and source acceptance is unchanged. A deliberately malformed candidate is an internal validation failure and never publishes.

## I06. Artifacts, attacks and failure injection

Treat external bytes as untrusted structure. **SEC-01** mutates lengths, offsets, counts, tags, versions, operation IDs, cycles in purported DAGs, duplicate definitions, forged signatures, foreign owner indices, resource bounds and proof prerequisites. Decode with checked arithmetic and bounded allocation before following any table span. Fuzzing may supplement these deterministic laws; it does not replace them.

**SEC-02** forges valid-looking evidence for the wrong value version, domain, region, edge or generic substitution. A reused digest/header cannot excuse validation. **SEC-03** points a K1 callable/helper at legacy RC or a mismatched code signature; transitive helper-role validation must reject it. Host buffers exercise pointer-plus-size overflow, incorrect element geometry, invalid Bool/sum tags and stale owner generations under the memory protocol.

**SEC-04** supplies a valid-looking cheap work receipt for source that exhausts fresh checking: untrusted disk/cache bytes cannot bypass required admission. **SEC-05** attaches altered executable bytes to a valid CheckedCore/interface/hash; the compiler ignores/rebuilds those bytes or requires independently trusted build provenance. Structural Core validation must not be presented as machine-code authentication.

**OOM-01** sweeps compiler allocation failures through artifact construction, decoding, proof completion, lowering, caching and publication. **OOM-02** exhausts guest pool slots, frame preflight and destination capacity through their specified error paths. **OOM-03** fails after each initialized prefix length and on every relevant exit. The surviving state, released backing regions and live loans match the protocol, with no partial published result.

**REV-01** performs valid edit → invalid edit → valid revert, cancellation during completion and concurrent independent-module work. The previous successful revision remains usable until a new successful transaction replaces it. **REV-02** changes a callee body, public contract, negative lookup, static initializer, ABI geometry, capture set and source origins separately; only justified cutoffs occur. Cold rebuilding agrees with every retained result.

## I07. Repository gates

Before each build batch, run `zig version` and verify Zig 0.17.0 or the repository's subsequently authorized requirement. Development/native tests use `-Dllvm=false`, including full native inventory compilation. Start with:

```sh
deno task check:dev --list-areas
deno task check:dev --area body-checking
```

Choose the actual affected explicit area; extend `scripts/dev_check_areas.ts` with K1 laws rather than assuming an old area covers new behavior. Development sampled faults remain partial evidence. For focused native work, run from `zig-native/`:

```sh
zig build test -Doptimize=safe -Dllvm=false --prefix zig-out-native-dev -Dtest-filter="exact test family"
```

Prefer compiling the complete installed inventory once and selecting `--test=EXACT_INVENTORY_NAME` at runtime. Before committing compiler changes, run:

```sh
deno task lint:zig
deno task test:compiler
```

The full gate is unfiltered, checks exact inventories/shard completion and runs exhaustive native allocation-failure sweeps. An interrupted, sampled or incomplete run is not a pass. `--resume` may reuse only the gate's verified matching evidence. Final release builds and performance measurements use `deno task build:compiler`, whose release compiler uses LLVM; this does not permit LLVM for native test compilation. Run generated-parser/editor checks when affected. Record commands, tool versions, commit, exit status and gate artifacts. [I-S1], [I-S5]

## I08. First runtime acceptance workload

Use a particle projection with `N` initialized Plain records `{x:F32,y:F32,vx:F32,vy:F32}`, scalar time step `dt` and a caller-supplied destination of capacity `C>=N` for `{x:F32,y:F32}`. Each iteration computes `x + vx*dt` and `y + vy*dt`, then appends one completely initialized output row. The canonical invariant is:

```text
0 <= i <= N <= C
initialized_length(output_builder) = i
input is the same immutable View<R,Particle,N,D>
```

On the body edge, `i<N` proves every input read and `i<C` proves the append. The step publishes `i+1` only after the complete row is initialized. At exit, freeze publishes exactly N rows. Output can live in another region; no same-region alias assumption is needed.

The expected baseline code shape is one counted loop with four F32 field loads, two multiplies, two additions and two F32 stores per element, plus bounded descriptor/cursor updates. There must be no row box, per-element backing reservation, retain/release, collector/root helper or repeated dynamic bounds validation justified by the admitted loop evidence. These are source-level operation targets, not a claim about final engine machine instruction counts. Record actual emitted operations and helper reachability.

Also execute empty, singleton, full-capacity, insufficient-capacity and early-failure variants. An explicit higher-order `map_into` variant tests a statically known closure and an admitted indirect callback separately. The direct baseline need not rely on inlining that callback to satisfy memory safety or no-RC promises.

## I09. Performance and scalability methodology

First establish semantic equivalence and resource accounting. Use existing benchmark infrastructure where suitable; add a K1 corpus manifest and machine-readable raw results instead of one-off timing anecdotes. Record CPU/OS, Zig/Deno/Wasm-engine versions, compiler build options, commit, policy, instrumentation, cache state and thread count.

Measure fresh-process/fresh-project compilation, repeated unchanged checks, retained single-body edits with unchanged interfaces, interface edits, static/ABI edits, rejected edits and restart-cache imports separately. Workloads should include chains/diamonds, many independent modules, many calls to one generic body, many closures/domains of the same layout, proof-dense branches and near-limit artifacts. Scale source size through multiple points and report work counters as well as wall time/RSS/retained bytes. “Fast” is not one tiny warm sample.

Use paired, counterbalanced repeated runs of the pinned current baseline and the candidate where programs have equivalent semantics. Keep instrumented attribution separate from uninstrumented timing. Publish sample counts, medians and dispersion; preserve outliers with explanations instead of silently discarding them. For runtime, report throughput/latency plus output checksums, backing reservations, bytes initialized/copied and scratch/result high-water usage. Existing optimized Blot may already perform well; a regression is evidence to investigate, not permission to weaken K1's contracts.

No numeric speedup is promised by this design. Initial hard gates are bounded work, zero downstream inference, one baseline generic body per declared ABI, no hidden managed helpers, resource correctness and stable reuse cutoffs. Record measured performance regressions with attribution. Introduce a timing threshold only after repeatable measurements define both the workload and acceptable variance.

## I10. Migration and final handoff

### K1-10 — Qualify the edition and migrate its first users

After K1-09, migrate one end-to-end example, its standard helpers and host bridge. Publish a syntax-aware migration report identifying implicit returns, changed checked arithmetic, unsupported captured authority, unproved indexing, unavailable features and explicit storage requirements. Auto-fix only semantics-preserving syntax changes. An inserted guard must expose a user-chosen failure policy; migration cannot invent it.

The default edition changes only after the full K1 corpus, host bridge, formatter/editor, documentation and package/import story qualify. Legacy remains separately selectable for a documented transition; mixed ABI calls require an explicit copying bridge. Remove old K1-prototype text and contradictory guide claims when replacing them, while retaining historical qualification as historical evidence.

Stop a milestone if no unoptimized representation satisfies its contract, a required algorithm depends on unbounded search, frame/resource composition is unknown, an artifact needs mutable checker handles, or a new path reaches managed helpers. Complete unaffected work, produce a minimal counterexample and propose the smallest explicit amendment. Do not label the entire implementation complete while a mandatory bridge, failure path or gate is pending.

The final implementation report must list the exact commit/toolchain, completed task and test IDs, normative deviations, supported/deferred features, full gate evidence, accepted/rejected examples, generated-code inspection, helper certificate, memory traces, zero-inference counters, cache/edit results, malformed-input/fault results and paired performance data. Current repository test counts are baseline context only; new K1 qualification is identified by its own inventory and run. Written contracts and tests support the claim; they do not constitute a mechanized proof of the compiler or host.

## Pinned implementation references

[I-S1]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/AGENTS.md
[I-S2]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/RUNTIME_MEMORY_QUALIFICATION.md
[I-S3]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/eval/core_eval.zig#L7001-L7048
[I-S4]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/eval/specialization.zig#L250-L274
[I-S5]: https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/scripts/test_compiler.ts
