# K1 implementation and qualification ledger

The K1 source, runtime, artifact, reuse and optimizer implementations pass the
frozen release gate: **116 native entries, 92 Deno integration tests and the editor
gate**. The candidate is identified by input manifest
`27e9627f595ffe94ff0a2955c600ef977cd1262638152326700716c8fb85d67e`
and executable SHA-256
`94b3d24012f8868a8eb7e8e6351edcfea9529c3d7de36845d10b0b2e47f032bd`.
**I09 measurements and the initial K1-10 handoff are complete.** The
[runtime follow-up](benchmarks/RUNTIME.md) records register-only phi scratch
omission and four-byte payload copy lowering, after the earlier
[structural](benchmarks/STRUCTURAL.md) and [parity](benchmarks/PARITY.md) work.
Its [latest evidence](benchmarks/results/runtime/manifest.json) binds all 197
qualified inputs, raw records and the gate to this candidate.
The [preceding parity package](benchmarks/results/parity/manifest.json),
[Sol review](benchmarks/SOL_REVIEW.md) and [initial report](benchmarks/RESULTS.md)
remain immutable historical evidence. Qualification does not imply universal
performance parity or authorize replacing the installed compiler.

Baseline: `main` at `1e39b5d8a4268b9edf769c2813d5231abe1c963b`.
Implementation branch: `rewrite/goose-k1`.
Goose pin: `a108677d300cb0e8bbb842c35a353abe67a20c6c`.
Normative snapshots and digests: [provenance.json](docs/spec/provenance.json).
Stage and law IDs below refer to [K1-EXEC](docs/spec/EXEC.md).

The user authorized replacing the tracked tree on an isolated branch with a
Goose implementation. This overrides the legacy coexistence/default-edition
rollout and Zig-specific paths/build commands. K1 is the sole edition here; the
old compiler remains on `main`. Semantic, memory, ABI, artifact and qualification
requirements remain. This ledger does not authorize merging, issue closure or
replacement of the user's installed compiler.

## Stage ledger

“Implemented; frozen gate passed” binds the representation and executable
positive/negative laws below to the recorded source manifest and binary.
The I09 report completes the measured handoff for this Linux candidate.

| Stage | Implementation and evidence | Status |
| --- | --- | --- |
| K1-00 | Edition/policy/ABI hash and flat schemas in [model.goose](src/model.goose); generated [registry](docs/REGISTRY.md) and [diagnostics](docs/DIAGNOSTICS.md); phase guard in `test_model`; scalar execution in `test_wasm`/[wasm_runtime_test.ts](tests/wasm_runtime_test.ts); hostile headers in `test_artifact`. | Implemented; frozen gate passed |
| K1-01 | Parser/checker in [frontend.goose](src/frontend.goose), [tooling.goose](src/tooling.goose), [editor grammar/tests](editor/). `test_frontend`, `test_frontend_semantics`, `test_tooling`, `test_frontend_finite_reachability`, `test_frontend_guide_examples`: explicit targets, formatter AST preservation, completion and rejected implicit tails. | Implemented; frozen gate passed |
| K1-02 | Owned Core/interfaces/ABI plans, independent [validator](src/validate.goose), sealed completion and exact SSA/CFG/type/effect/resource admission. `test_validator`, `test_validator_source`, `test_artifact`, `test_frontend_work_independence` and [concurrency_test.ts](tests/concurrency_test.ts). | Implemented; frozen gate passed |
| K1-03 | Required finite proofs, exact short-circuit/contract/capture evidence, versioned observations, Index authority and canonical loops. [frontend_conformance_test.goose](tests/frontend_conformance_test.goose), [frontend_proof_work_test.goose](tests/frontend_proof_work_test.goose), [frontend_limits_test.goose](tests/frontend_limits_test.goose), `test_validator_loops`, `test_validator_boolean_paths` and validator budget laws. | Implemented; frozen gate passed |
| K1-04 | [runtime.goose](src/runtime.goose)/[wasm.goose](src/wasm.goose) fixed pool, owners/generations, frames, destinations/builders, placement and initialized Views. `test_runtime`, [wasm_runtime_test.ts](tests/wasm_runtime_test.ts), [wasm_particle_test.ts](tests/wasm_particle_test.ts) and storage laws in [wasm_lifecycle_test.ts](tests/wasm_lifecycle_test.ts). | Implemented; frozen gate passed |
| K1-05 | Existential introduction/opening, fresh brands, explicit Nat prefixes and imported graph construction/traversal. `test_frontend_graph_domains`, `test_validator_static_packages`, [graph.blot](examples/graph.blot), [graph_demo.blot](examples/graph_demo.blot) and executed graph package laws. | Implemented; frozen gate passed |
| K1-06 | Scoped code/environment pairs; Share captures and captured facts; Many/Once; placed environments; finite depth/frame bounds; adapters and forwarded witnesses. [wasm_closure_test.ts](tests/wasm_closure_test.ts), closure/resource source laws, `test_validator_static_capture`, `test_validator_ambient_nat`, `test_wasm_validation`. | Implemented; frozen gate passed |
| K1-07 | Single-backing Owned construction/seal/open/close and copy-only Plain-array bridge. [host/blot.ts](host/blot.ts), [wasm_bridge_test.ts](tests/wasm_bridge_test.ts), [host_bridge_test.ts](tests/host_bridge_test.ts), [wasm_lifecycle_test.ts](tests/wasm_lifecycle_test.ts). External unbound Index domains and `Owned<FnOnce>` reject. | Implemented; frozen gate passed |
| K1-08 | Shared rank-1 bodies, dictionaries/realizations and independent coverage; LayoutFits premises; lexical forall/captured witnesses; required-static evaluation and immutable arrays/packages/nested closures. [layout_premise_test.goose](tests/layout_premise_test.goose), [frontend_generic_test.goose](tests/frontend_generic_test.goose), `test_dictionary_coverage`, [evaluate_test.goose](tests/evaluate_test.goose), [wasm_static_test.ts](tests/wasm_static_test.ts) and generic runtime laws. | Implemented; frozen gate passed |
| K1-09 | R01–R12 optimizer and bounded release inlining; canonical portable tables; exact dependencies/origin relocation; process-local receipts; bounded retained sessions; corruption, cancellation, OOM and publication rollback. Optimizer, artifact, relocation, retained/session and failure laws below. | Implemented; frozen gate passed |
| K1-10 | [Migration report/example](docs/migration.md), imported generic helper and copy host in [migration_test.ts](tests/migration_test.ts); [guide](docs/guide.md), [scope](docs/features.md), README and measurement harnesses. | Implemented; gate and measured handoff complete |

The compiler, evaluator, validator and emitted runtime are Goose. The small
[platform.h](src/platform.h) supplies bounded OS I/O/publication operations;
TypeScript supplies host, test and measurement clients. Python generates explicit
Goose codec/relocation/ordering tables, without implementing compiler semantics.
These are the clean-rewrite equivalents of EXEC's proposed Zig ownership paths.

## Source and runtime laws

These references identify assertions, not merely examples or successful process
exits. The conformance helper checks exact diagnostic categories and nonempty
source spans. Independent-validator source-origin laws additionally exercise
loan, ownership and resource failures; required malformed artifacts keep opaque
diagnostics instead of following attacker-controlled origins.

| Laws | Evidence |
| --- | --- |
| SYN-A01, SYN-R01/R02 | `test_frontend_semantics` in [frontend_test.goose](tests/frontend_test.goose); `test_tooling` in [tooling_test.goose](tests/tooling_test.goose); [editor/test.mjs](editor/test.mjs). |
| BND-A01/A02, BND-R01–R06 | `test_frontend_exec_bounds_laws` and `test_frontend_collection_transition_bounds` in [frontend_conformance_test.goose](tests/frontend_conformance_test.goose): insufficient bounds, stale shortened View, branch-only facts, unchecked helpers and initialized prefix versus capacity. |
| PRF-R01, NUM-A01/A02, NUM-R01 | Unsupported-fact/arithmetic laws in [frontend_test.goose](tests/frontend_test.goose); `test_frontend_checked_and_scalar_control`, `test_frontend_short_circuit_proofs`; [frontend_limits_test.goose](tests/frontend_limits_test.goose); [numeric_test.goose](tests/numeric_test.goose). Wrapping arithmetic supplies no monotonicity authority. |
| MEM-A01/A02/A03, MEM-R01–R04, ERR-R01 | [runtime_test.goose](tests/runtime_test.goose), `test_validator_consumed_observation`, `test_validator_incomplete_product` and type corruption in [validator_test.goose](tests/validator_test.goose), `test_frontend_exec_owned_and_loan_laws`, lifecycle/affine/Result source laws, [wasm_lifecycle_test.ts](tests/wasm_lifecycle_test.ts) and [wasm_particle_test.ts](tests/wasm_particle_test.ts). |
| DOM-A01, DOM-R01/R02 | `test_frontend_graph_domains` in [frontend_graph_test.goose](tests/frontend_graph_test.goose) rejects same-sized packages, repeated constructor sites and foreign endpoints in loops. Source conformance rejects brand escape. Executed imported graph construction covers zero nodes and endpoint errors; static package corruption rejects false shared slice domains. |
| FN-A01, FN-R01–R06 | Capture/recursion/resource laws in [frontend_test.goose](tests/frontend_test.goose), [frontend_lifecycle_test.goose](tests/frontend_lifecycle_test.goose) and [frontend_conformance_test.goose](tests/frontend_conformance_test.goose); [wasm_closure_test.ts](tests/wasm_closure_test.ts), higher-order particles and resource/signature controls in [wasm_test.goose](tests/wasm_test.goose)/[wasm_validation_test.goose](tests/wasm_validation_test.goose). |
| OWN-A01, OWN-R01/R02 | Owned/loan/category source laws; repeated release/open/placed-closure/generic schema crossings in [wasm_lifecycle_test.ts](tests/wasm_lifecycle_test.ts); negative [runtime_external_index_owned.blot](tests/runtime_external_index_owned.blot). Payload witnesses must be closed by the package schema. |
| GEN-A01/A02, GEN-R01/R02 | `test_frontend_generic_layout_obligations`, `test_validator_layout_premises`, `test_validator_compound_plain`, unconstrained copy/drop laws, `test_frontend_local_forall_shares_body`, `test_dictionary_coverage`, and executed generic/compound/affine/Owned callback laws. A 256-byte generic payload wrapped in Result rejects before runtime admission. |
| STA-R01 | `test_required_static_boundaries` in [evaluate_test.goose](tests/evaluate_test.goose): 128/129 call depth, 100,000 steps and 4 MiB output. [admission_test.ts](tests/admission_test.ts) requires unused-static exhaustion to reject in check and all optimizer tiers. F32 evaluation and canonical NaNs have exact-bit controls. |
| CTL-01 | `test_validator_loops` in [validator_source_test.goose](tests/validator_source_test.goose) rejects self-proved entry and stop-as-exhaustion; carry/particle laws preserve successor initialization. `test_relocation_proofs`, static packages and generic affine Result guests retain obligations through transport/calls. |
| I08 particle baseline | [wasm_particle_test.ts](tests/wasm_particle_test.ts) parses actual Wasm: one loop, four element loads, two F32 multiplies, two separately rounded adds, two stores, no loop helper/indirect calls or bulk-copy spills. Empty/singleton/full/insufficient capacity and callbacks execute. Failure covers every prefix 0–8, including full-prefix failure, with exact reservations/releases and no published result. |

## Compiler, artifact and failure laws

| Laws | Evidence and boundary |
| --- | --- |
| CMP-01, C01/C06/C07 | `test_model` refuses completion after sealing and checks active-region balance. `test_frontend_work_independence` proves caller work does not scale with the callee implementation. [concurrency_test.ts](tests/concurrency_test.ts) checks zero active/downstream completion and identical work/artifacts for one versus four independent jobs. The rewrite contains no legacy solver/specialization fallback. |
| CMP-02/CMP-04, C09 | [frontend_limits_test.goose](tests/frontend_limits_test.goose), `test_frontend_operation_limit_includes_terminators`, [loader_test.goose](tests/loader_test.goose), `test_validator_helper_budget`, `test_validator_declaration_budgets`, `test_validator_type_definition_budget` and static boundaries. Nested closures/staging/local forall share the source Definition's budget; independent declarations do not share one semantic allowance. Helper traversals and proof work charge required accounts. |
| CMP-03, C02/C05/C11 | `test_artifact` destroys producer scratch before decode. [artifact_order_test.goose](tests/artifact_order_test.goose) permutes names/evidence/block order and checks exact bytes/fresh validation; `test_artifact_static_pattern_fingerprint` preserves captured static-pattern identity after owner reordering. [relocate_test.goose](tests/relocate_test.goose) selects current dependency implementations. `test_retained_digest_collision` forces identical stored digests across distinct contracts and still rejects reuse by exact comparison. |
| ART-R01, SEC-01/SEC-02 | [validator_test.goose](tests/validator_test.goose), [validator_source_test.goose](tests/validator_source_test.goose), [layout_premise_test.goose](tests/layout_premise_test.goose), `test_dictionary_coverage`: checked extents/sentinels/tags, foreign IDs, duplicate definitions, cyclic types/proofs, incorrect fields/versions/edges/domains/substitutions, stripped LayoutFits and missing dictionary realizations. Checksum-valid corrupt bodies still reject. |
| ART-A01, SEC-04 | `test_retained_optional_corruption` rejects malformed encoding and checksum-valid invalid Core, destroys scratch and executes equivalent fresh completion. `test_retained_external_receipt` supplies structurally valid Core claiming one visit for source requiring 65,537 operations; external provenance cannot authorize reuse, so the exact cold `k1_core_limit` rejection remains. Provenance is supplied outside serialized bytes. |
| SEC-03/SEC-05, C12 | [wasm_validation_test.goose](tests/wasm_validation_test.goose) checks actual encoded stack/control/call signatures, missing roles, malformed LEB/immediates and changed final code bytes. Certificates bind ABI hash, memory map, code, function roles and transitive calls. [artifact_cli_test.ts](tests/artifact_cli_test.ts) removes source files and rebuilds local Wasm from independently admitted Core; external code is never promoted by a Core digest. |
| M12 host boundary | [wasm_bridge_test.ts](tests/wasm_bridge_test.ts), [host_bridge_test.ts](tests/host_bridge_test.ts), [host_test.ts](tests/host_test.ts): malformed geometry, overflow, Bool/sum/padding bytes, private memory/descriptors, reentry, poison-after-trap, output copying and small output windows. Scalar requires/Bool entry checks pass before source execution. |
| OOM-01 | [oom_test.ts](tests/oom_test.ts) and [session_oom_test.ts](tests/session_oom_test.ts) sweep observed Linux arena reserve/protected commit boundaries through construction/validation/lowering and retained decode/reuse/publication. [arena_fault.c](tests/arena_fault.c) uses reservation-relative commit chunks so ASLR cannot change fault ordinals. Coverage is actual OS arena failures, not every libc allocation or every source feature; fatal process OOM leaves previous Wasm usable. |
| OOM-02/OOM-03 | Native/emitted runtime laws exhaust owner slots, fragmented pool space, placement arithmetic, destination capacity and frame preflight. Generation retirement and failed predecessor-state preservation are asserted. Particle failures cover every initialized prefix and successful recovery, with no live backing or partial result. |
| REV-01/REV-02 | [retained_test.goose](tests/retained_test.goose), [session_test.ts](tests/session_test.ts), [session_edits_test.ts](tests/session_edits_test.ts), [cancellation_test.ts](tests/cancellation_test.ts), [concurrency_test.ts](tests/concurrency_test.ts), [artifact_cli_test.ts](tests/artifact_cli_test.ts): valid/invalid/revert, mid-module cancellation, body/contract/namespace/import/static/capture/origin/ABI edits, cold agreement, malformed bounded requests and output-pair rollback. No cross-file crash-atomic visibility to arbitrary readers is claimed. |

The retained cache holds one bounded current-process revision. Unsupported
comparisons or oversized entries decline to fresh work. Source restarts perform
fresh admission; required source-less artifacts use independent Core admission
and local executable reconstruction. There is no persistent trusted source
receipt import. Explicit module declaration order survives canonical table
renumbering.

## Enabled optimizer qualification

[optimize.goose](src/optimize.goose) implements a deterministic bounded R01–R12
catalogue: terminal/join forwarding, an exact identity-call case, product
projection, literal branches, scalar propagation/folding, immutable View length,
exclusive successor store/read forwarding, known descriptor observations,
closed callable direct calls and whitelisted total dead primitives. Proof
producers stay pinned unless their exact justification is preserved. Effects,
generative identities, reservation/failure and cleanup are not erased.

- **OPT-01:** [optimizer_differential_test.goose](tests/optimizer_differential_test.goose)
  asserts every R01–R12 counter fires and emits baseline/candidate guests.
  [optimizer_differential_test.ts](tests/optimizer_differential_test.ts) executes
  boundary inputs and exact capability traces, plus signed-zero, infinity,
  rounding and NaN-bit controls. [admission_test.ts](tests/admission_test.ts)
  compares tiers on scalar, generic and ownership programs.
- **OPT-02:** the executed R09 fixture includes empty/success/capacity/reservation
  paths and compares calls, failures and releases. There is no enabled loop
  hoisting/fusion rule to qualify. Particle and lifecycle laws preserve failure
  order without optimization.
- **OPT-03:** `test_optimizer_budget_controls` and `test_optimizer` force visit,
  rewrite and output refusal before/during work. Optional decline preserves the
  baseline/source admission; malformed candidates fail validation and cannot
  publish.

`--opt=fast` uses the R01–R12 kernel. `--opt=release` additionally transports
small direct scalar callees under the existing C10 size, depth, site and work
budgets, then independently validates the candidate. Immutable templates,
preflighted SSA transport and reserved finalization work preserve a valid prefix
when optional analysis stops. Scalar replacement, fusion and SIMD remain future
optional work. See [inlining contracts](docs/CONTRACT.md#bounded-release-inlining).

## Qualification commands and remaining work

[scripts/test_inventory.ts](scripts/test_inventory.ts) discovers the complete
native inventory. A historical fixed count cannot replace inventory verification.
The frozen release candidate must pass:

```sh
GOOSE=/tmp/blot-k1-goose/build/goose \
GOOSE_HOME=/tmp/blot-k1-goose-home scripts/check.sh --release
```

The gate runs nonmutating generated-file checks, debug Goose native tests,
release compiler build, pinned editor checks and all Deno/guest/host/session/fault
laws. [gate_manifest.py](scripts/gate_manifest.py) records before/after input
hashes, tool metadata and binary identity in `test-results/qualification.json`;
native/editor/Deno logs and fault-boundary reports accompany it. Changed inputs,
interruption or incomplete inventory invalidate the run. Focused tests do not
replace that gate.

Scalar exports now validate preconditions and canonical Bool inputs before source
execution. The Linux allocation adapter uses reservation-relative commit chunks,
so ASLR cannot shift its injected fault ordinals. The C13 report includes proof,
static, generic, body/adapter, rewrite, generated-size and cache-work counters;
[concurrency_test.ts](tests/concurrency_test.ts) checks their source/runtime split
and that attribution leaves generated bytes unchanged.

The initial measured handoff is complete. [RESULTS.md](benchmarks/RESULTS.md) records
paired compile/runtime scaling, retained revisions, exact operation boundaries,
source-less artifact inspection/rebuilding, guest storage telemetry and isolated
compiler iteration. It includes the rejected 128-depth chain and accepted 127-depth
control, the unchanged-reuse regression, and slow compiler rebuilds. The raw
package preserves all samples and source inputs; no outliers were discarded.
All 178 initial qualified input blobs were verified against implementation commit
`4d5fe60343d1916ec99baa452f2727c48a408f27`; `commit-binding.json` is archived.

Serve timing separates `cache_admit_ns` (optional decode/validation),
`cache_encode_ns` (canonical encoding and retained buffer copy), and
`publication_ns` (atomic output write). Serve `total_ns` remains the candidate
pipeline clock; request wall time includes these additional phases plus
protocol/cleanup. `ReuseStats.admission_visits` includes attempted validation of
accepted/rejected optional Core. `dependency_invalidations` counts a rejected
reuse candidate caused by dependency presence/namespace/body or non-budget
relocation incompatibility; ordinary missing/source-text candidates and budget
declines are separate. Instrumented guest attribution is separate from normal
runtime timing.

This is qualification of the recorded implementation and Linux corpus,
not a main-branch release or a mechanized proof. Optional future work remains
explicit in [scope](docs/features.md); the remaining performance work in
[STRUCTURAL.md](benchmarks/STRUCTURAL.md#legacy-comparison-and-next-decisions) is explicit. The
recorded qualification and measurement batches are complete; all-workload
performance parity remains an open target.

## Sol review regression coverage

The current full gate includes `test_validator_affine_scratch` and
`test_validator_unrelated_value_work` for sparse ownership state,
`test_canonical_growth` for adaptive exact-key indexes, and
`test_relocation_sparse_growth` for bounded sparse remapping and row order.
Two executed-Wasm laws in `wasm_runtime_test.ts` cover zero-byte source frames
and generic Unit adapters, mixed framed calls, public preflight, repeated
frontier restoration and exact telemetry. Source syntax, ABI and limits remain
unchanged. See the review report for measured improvements and their scope.

## Parity investigation regression coverage

The full gate additionally covers `test_layout_scratch_epochs`,
`test_dictionary_coverage_function_work`, CFG/producer/dominance indexes,
`test_validator_layout_owner_indexes`, strict proof SCCs and lazy evidence,
and cross-module scratch parity/rebinding/failure laws. Matching-owner layout
rows remain fully checked; indexed lookup never grants authority by itself.
Emitted-Wasm tests exercise borrowed generic inputs, structured returns,
compacted I32/F32 locals, zero initialization and exact floating-point bits.

`artifact_cli_test.ts` injects zero, partial and failed writes, interrupted/short
writes, close/chmod/rename failure and absent/existing destination cases into
ordinary Wasm publication. It checks executable contents, old mode/new umask,
symlink/nonregular rejection and staging cleanup. Core/pair/source-format
writers retain their existing synchronization behavior. Ordinary Wasm publication
is atomically visible but does not acknowledge durable storage; see
[the contract](docs/CONTRACT.md#transport-publication-and-observations).
`concurrency_test.ts` checks nonoverlapping CLI timing fields and byte-identical
output with attribution enabled. Retained failure, cancellation, allocation
fault and pair rollback suites also pass with the new path.

## Structural work and release inlining

Validator attempts borrow the immutable Core view; their budgets and scratch
remain private. `test_validator_immutable_attempt_isolation` checks isolation,
and frozen before/after controls preserve exact work accounts and diagnostics.
Frontend contradiction SCCs use an iterative forward-only Tarjan traversal;
`test_frontend_tarjan_component_boundaries` covers weak/strict component edges,
merges, cross/back edges, removed closing edges and bounded deep traversal.

The nine native laws in [inline_test.goose](tests/inline_test.goose) cover empty
and earlier returns, fresh SSA identities, immutable-template depth, 32-node
callee cutoff, per-caller/global growth, site limits, pinned producers, physical
artifact preflight, optional fallback and retained prefixes. A 256-limit sweep
exercises multi-block cleanup; missing SSA mappings stay internal errors.
[Executed guests](tests/inline_test.ts) compare exact wrapping-U32/F32 behavior
and reservation/release counts. The release session-edit law in
[session_edits_test.ts](tests/session_edits_test.ts) verifies that a changed callee
updates an inlined result while the caller's semantic judgment is reused, and
that rejected revisions retain the prior output.

[Structural measurements](benchmarks/STRUCTURAL.md) separate isolated changes,
combined compiler results and release/fast runtime behavior. The two new loop
workloads have independent integer/F32 reference models and varying inputs.

## Bounded runtime follow-up coverage

Frame allocation and emission share `edge_in_registers`; scalar/flat edges no
longer reserve unused physical phi scratch. The new executed law in
[wasm_runtime_test.ts](tests/wasm_runtime_test.ts) checks joins, loops, mixed/F32
parallel swaps, nonflat fallback, telemetry, frontier restoration and unchanged
public/source envelope rejection. Owned sealing retains separate scratch.

Four-byte copies use integer load-before-store, with a guarded path for dynamic
sizes and bulk fallback for all other sizes including zero. The native fixture
in [wasm_copy_test.goose](tests/wasm_copy_test.goose) and three executed laws in
[wasm_copy_test.ts](tests/wasm_copy_test.ts) compare memmove behavior over 0–256
bytes, unaligned overlaps, signed-zero/NaN word bits, bounds failures without
partial writes, typed generic/fixed paths and exact byte/call counters.

[Runtime measurements](benchmarks/RUNTIME.md) contain one fixed before/after
pass with fresh engine processes: generic integer/F32 kernels improve, aggregate
and ordinary controls remain roughly unchanged. The pass is complete; there is
no ongoing optimization search or pending required check.

## Direct comparison with main

[MAIN_COMPARISON.md](benchmarks/MAIN_COMPARISON.md) adds 209 measurements of the
unchanged qualified compiler against main `1e39b5d`, with its installed release
hash verified against committed provenance. The charts expose generic runtime
regressions as well as compile-time gains and gaps. This benchmark/documentation
addition changes no qualified compiler input; the 116-native/92-integration gate
and 197-input manifest remain valid. It does not extend the implemented language
or establish application-wide parity.
