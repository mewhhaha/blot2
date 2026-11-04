# Language qualification

The 15 October source freeze `3548546c…` passes 2,223 native laws, 1,404
guest/client tests and 1,366 complete allocation-failure sweeps, with zero
analyzer findings across 455 Zig files. Release SHA-256 is
`6a83bad5560ec1a82220dc834dd366646fb8ab10370f82b26a2bcb775111ae6b`. Exact
source, toolchain, executable, bundle, handshake and test pins are in
`build/bench/complete-program-20261015/final-proof-repaired-gate/qualified-pins.json`.
Later compiler changes require their own combined qualification.

The executable acceptance index is
`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`
(SHA-256 `8a7191ec053504d927b3b7df5cd2f840a8aacedb520b8c0da6ace08babeee009`). It
checks all 2,223 distinct native test names and the successful guest JUnit
report, then records the exact passing laws and guest source hashes for each row
below. Counts overlap between rows; they are not additional tests. That file was
removed with `build/`; the [row-to-law index](#row-to-law-index-17-october-2026)
replaces it.

| Contract             | Qualified requirements                                            | Native laws | Guest tests |
| -------------------- | ----------------------------------------------------------------- | ----------: | ----------: |
| Scoped identities    | Fresh owners, routing, shadowing, forwarding, symbolic rows       |          96 |          14 |
| Scoped identities    | Aliases, dependent/generative contracts, multi-input callbacks    |          48 |          12 |
| Scoped identities    | Requests, cancellation, revocation, imported recovery             |          28 |           7 |
| Capability lifetimes | Closures, demands, aggregates, projections                        |          27 |          13 |
| Capability lifetimes | Sinks, opaque contracts, bounded diagnostics                      |          28 |           9 |
| Usage                | Moves, aliases, branches, loops, once/many                        |          39 |           9 |
| Usage                | Loans, sharing, qualified polymorphic calls                       |          28 |           5 |
| Resources            | Return/break/trap, host failure, suspended cancellation           |          36 |          10 |
| Resources            | Transfer, retirement, persistent journal, structural host roles   |          37 |          12 |
| Higher rank          | Structural rank, annotated recursion, skolems, bounded rejection  |          30 |          10 |
| Higher rank          | Row/region binders, predicates, associated evidence, dictionaries |          67 |          13 |
| Packages             | Sealing, heterogeneous carriers, openings, stored evidence        |          38 |          27 |
| Packages             | Resealing, associated payloads, captures, affine ownership        |          38 |          12 |

Source/archive/checkpoint/restart, failed edits, recovery, both compiler tiers
and sync/JSPI are exercised by the recorded guest groups. The index includes the
explicit affine universal identity, region-quantified loan reader, dynamic
universal dictionaries, qualified package destruction and ABI 7 structural
host-cleanup controls. Earlier subset notes in individual implementation records
describe their historical checkpoints.

Unannotated higher-rank inference, affine values hidden in unrestricted type
binders, unknown cleanup termination and unproved storage lifetimes remain
intentional rejections under the normative designs. A type spelling or physical
layout supplies no missing evidence. The separate typed-staging continuation
still needs closed pure scope evaluation and its final combined gate.

## Row-to-law index, 17 October 2026

This index was regenerated from the passing gate at commit `05401a9` (17 October
2026). Its sources are the native run's log of 2,355 distinct law names (two
shards, zero failures, zero leaks) and the guest JUnit report (1,501 tests, zero
failures). Every law named below appears in that gate output and is declared in
the committed source. The earlier gate at `23a934f` (2,354 native laws, 1,486
guest tests, zero leaks) also passed. Tasks 058, 059, 061, 062, 064 and 065
closed against these rows on 17 October 2026.

Each of the 51 requirements names native laws and, where one exists, an executed
guest test that exercises it: 145 distinct native laws and 96 distinct guest
tests in all. Rows share laws. Unlike the removed index, this is not a census of
every law that touches a row. Because every native law and guest test in the
gate passed, any further law attributable to a row passed too. Paths are
relative to `zig-native/`. A native entry names its Zig `test`; a guest entry
names its `Deno.test`, where a parenthesized suffix selects one tier or mode
variant of a parameterized test.

### Scoped identities: fresh owners, routing, shadowing, forwarding, symbolic rows

```text
Fresh owners
  native src/check/capability_lifetimes_tests.zig: immutable scope lifetime graph reconstructs fresh owners and rejects returned authority through OOM
  native src/check/check_effect_tests.zig: scoped effect request clauses preserve a fresh owner
  native src/check/effect_authority.zig: effect authority exhaustion never recycles released identities
  guest  tests/scoped_effect_execution.test.ts: scoped same-typed effect owners route independently on repeated entries
  guest  tests/scoped_parameter_execution.test.ts: quantified capability parameters route fresh instances through compiled imports and JSPI (optimized)

Routing
  native src/check/check_effect_tests.zig: scoped effect nested same typed capabilities retain independent exact rows
  native src/check/check_effect_tests.zig: scoped effect different instance provider leaves exact requirement visible
  native src/backend/provider_chain.zig: scoped provider keys route same-typed owners and revoke before retirement
  guest  tests/scoped_effect_execution.test.ts: scoped routing forwarding and aliases survive retained edits and checkpoints (optimized)

Shadowing
  native src/check/check_effect_tests.zig: scoped effect ordinary provider shadowing cannot license a State storage lifetime
  native src/check/check_effect_tests.zig: scoped effect closures do not inherit construction time State handlers
  guest  tests/builtin_state_execution.test.ts: builtin State readers and writers retain residual effects and shadow exact instances
  guest  tests/scoped_grouped_product_execution.test.ts: grouped curried product footprints preserve imported capability ordinals and shadowing

Forwarding
  native src/check/scoped_effect_backend_tests.zig: forwarding invocation reconstructs producer bodies and rejects cycles missing owners and order forgery
  native src/check/check_effect_tests.zig: reader witnesses do not invent result links and forwarding implementations retain outward effects
  guest  tests/scoped_forwarding_callback_execution.test.ts: forwarded callbacks retain exact no store and ordered scoped owners (development)
  guest  tests/effect_execution.test.ts: nested providers forward unrelated operations and exclude younger callback scopes

Symbolic rows
  native src/check/check_effect_tests.zig: scoped effect symbolic family arguments preserve inherited payload shapes
  native src/check/check_effect_tests.zig: scoped effect selected symbolic payload normalization preserves the same instance edge
  native src/check/generative_relocation.zig: symbolic scope-owner relocation shares only the same unresolved instance term
  native src/check/types_tests.zig: scoped effect identity survives normalization and preserves multiplicity
  guest  tests/scoped_generic_execution.test.ts: symbolic scoped factories preserve source dependency and retained specialization identity
```

### Scoped identities: aliases, dependent/generative contracts, multi-input callbacks

```text
Aliases
  native src/check/check_effect_tests.zig: scoped effect operation aliases and local callbacks remain usable
  native src/check/check_effect_tests.zig: scoped effect request aliases reject duplicate owner clauses
  native src/check/effect_authority.zig: effect authority aliases survive revocation without retaining permission
  guest  tests/scoped_effect_execution.test.ts: scoped capability operation aliases retain their owner in local callbacks
  guest  tests/aliases_execution.test.ts: aliases retain underlying effect identities in written rows and operation arguments

Dependent/generative contracts
  native src/check/generative_relocation.zig: captured scoped relocation preserves concrete owners and invocation versions
  native src/check/generative_relocation.zig: quantified scoped relocation preserves owner correspondence across descriptors and rows
  native src/check/scoped_effect_backend_tests.zig: scoped effect public flow contracts validate bodies and release failed allocations
  native src/reuse/dependency_interface_tests.zig: returned invocation binders retain declaring arrows and captured versions through OOM
  guest  tests/scoped_public_flow_execution.test.ts: owned scoped public flow survives dependencies edits JSPI and checkpoints (optimized)
  guest  tests/scoped_generation_execution.test.ts: invocation generations preserve provider records captured versions and retained recovery (optimized)

Multi-input callbacks
  native src/check/check_effect_tests.zig: scoped effect multiple input invocation summaries preserve exact callback rows
  native src/check/scoped_effect_backend_tests.zig: multi input invocation reconstructs ordered owners and named callback no store
  native src/check/scoped_effect_backend_tests.zig: scoped effect multiple input invocation claims validate callback ordinals and OOM
  guest  tests/scoped_invocation_flow_execution.test.ts: multi-input Unit invocation preserves exact callback owners (parameter, optimized)
  guest  tests/scoped_multi_input_callback_execution.test.ts: multi input callbacks retain exact no store and ordered scoped owners (development)
  guest  tests/scoped_pair_execution.test.ts: paired scoped capability inputs retain positional identities through compiled imports and JSPI (arrow, optimized)
```

### Scoped identities: requests, cancellation, revocation, imported recovery

```text
Requests
  native src/check/check_effect_tests.zig: scoped effect request clause for another owner leaves its requirement
  native src/check/scoped_effect_backend_tests.zig: scoped effect request evidence rejects missing and foreign-owner selectors
  native src/check/scoped_effect_backend_tests.zig: scoped effect request selectors survive lowering emission and failed allocations
  guest  tests/scoped_request_execution.test.ts: scoped request keys forward cancel retry and survive checkpoints (optimized)

Cancellation
  native src/backend/runtime_operation_backend_tests.zig: private provider flow covers captured request cancellation and memoized source cycle bodies
  native src/eval/core_request_tests.zig: Requests: an outer cancellation unwinds an inner handler and its invoking clause
  guest  tests/scoped_request_execution.test.ts: scoped request keys forward cancel retry and survive checkpoints (development)
  guest  tests/callback_row_execution.test.ts: mixed Foreign Requests factories preserve captures cancellation and callback recovery

Revocation
  native src/backend/provider_chain.zig: scoped provider keys route same-typed owners and revoke before retirement
  native src/check/effect_authority.zig: effect authority aliases survive revocation without retaining permission
  guest  tests/scoped_authority_runtime.test.ts: scope activation journal revokes retained identity before teardown on success and failure
  guest  tests/scoped_request_execution.test.ts: scoped request owners remain active through JSPI callbacks and revoke on rejection (optimized)
  guest  tests/suspended_ownership_execution.test.ts: a ready memo retains its original host closure without rebinding a revoked capability

Imported recovery
  native src/check/check_effect_tests.zig: imported generic runners preserve producer identity and independently freshen state and residual rows
  native src/check/check_effect_tests.zig: foreign interfaces remap colliding operation IDs and preserve exact family arguments and multiplicity
  native src/reuse/dependency_interface_tests.zig: capability import keeps producer graph ordinal distinct from relocated external target
  guest  tests/scoped_effect_execution.test.ts: scoped source consumes the same imported effect declaration through compiled dependencies
  guest  tests/scoped_effect_execution.test.ts: scoped providers survive host suspension and clean up rejection/trap (optimized)
  guest  tests/scoped_value_flow_execution.test.ts: value footprints preserve imported callable containers aliases and failed edits (optimized)
```

### Capability lifetimes: closures, demands, aggregates, projections

```text
Closures
  native src/check/check_effect_tests.zig: scoped effect closed source closure footprints distinguish captures from effects
  native src/check/check_effect_tests.zig: scoped effect boundary rejects direct capability and handled closures
  native src/check/capability_lifetimes_tests.zig: scoped partial applications derive residual captures and reject younger substitution despite omitted catalogs through OOM
  native src/check/scoped_effect_backend_tests.zig: scoped effect closure footprint survives lowering emission and failed allocations
  guest  tests/scoped_closure_footprint_execution.test.ts: returned source closure footprints preserve data and longer lived captures (optimized)

Demands
  native src/check/check_effect_tests.zig: demand construction capture proof admits local values and rejects fresh authority independently of scalar result
  native src/check/check_effect_tests.zig: scoped effect rejects operation aggregate demand and generic authority escapes
  native src/check/capability_lifetimes_tests.zig: immutable lifetime forced scalar Memo retains its actual producer captures through OOM
  guest  tests/scoped_demand_capture_execution.test.ts: scoped demand construction capture proof survives archives and recovery (development)

Aggregates
  native src/check/check_effect_tests.zig: scoped effect pure product helpers retain every exact input footprint
  native src/check/check_effect_tests.zig: scoped effect record constructors retain exact named input footprints
  native src/check/scoped_effect_backend_tests.zig: scoped effect pure product input footprints validate exact bodies and release OOM
  guest  tests/scoped_aggregate_flow_execution.test.ts: owned parameter product footprints preserve imported capabilities and lifetimes (optimized)
  guest  tests/scoped_lifetime_execution.test.ts: nested scope exit preserves longer lived structural authority (optimized)

Projections
  native src/check/check_effect_tests.zig: scoped owned projections retain pure hidden captures independently of latent effects
  native src/check/scoped_effect_backend_tests.zig: scoped effect outer authority projection survives lowering emission and failed allocations
  native src/check/scoped_effect_backend_tests.zig: projected callable provenance owns producer bodies receiver binders and closed constructor execution
  guest  tests/scoped_projected_callback_execution.test.ts: projected callbacks retain exact no store and ordered scoped owners (development)
```

### Capability lifetimes: sinks, opaque contracts, bounded diagnostics

```text
Sinks
  native src/check/check_effect_tests.zig: scoped effect static generic operations cannot transfer authority to longer lived storage
  native src/check/check_effect_tests.zig: scoped effect older State cells reject younger source captures
  native src/check/check_effect_tests.zig: scoped effect partially applied identity cannot hide a storage sink
  native src/check/capability_lifetimes_tests.zig: immutable lifetime short circuit and branch Memo state cannot erase alternate storage sinks through OOM
  guest  tests/scoped_capability_diagnostics.test.ts: explicit generic operations reject shorter authority at source and compiled storage sinks
  guest  tests/scoped_storage_execution.test.ts: local State storage retains scoped captures through suspension and compiled imports (optimized)
  guest  tests/scoped_older_cell_execution.test.ts: direct scope callback retains older State installation (development)

Opaque contracts
  native src/check/capability_invocations.zig: input invocation inspects storing conditions and opaque callback owners
  native src/check/capability_invocations.zig: input invocation cannot hide opaque input transfer in discarded Unit request payloads
  native src/check/capability_contracts.zig: owned capability recipe substitution preserves precise paths and rejects live authority publication
  native src/reuse/dependency_interface_tests.zig: typed input invocation independently reconstructs callback no store authority through OOM
  native src/backend/runtime_operation_backend_tests.zig: callable result ownership edges reject changed returns later stores and opaque sinks through OOM
  guest  tests/scoped_public_flow_execution.test.ts: owned scoped public flow survives dependencies edits JSPI and checkpoints (development)

Bounded diagnostics
  native src/check/capability_lifetimes_tests.zig: immutable scope rejection shares one work budget across repeated scope DAG roots
  native src/check/capability_lifetimes_tests.zig: immutable scope rejection ignores unrelated owner and ordinary node population in its semantic budget
  native src/check/capability_lifetimes_tests.zig: immutable boundary lifetime work ignores unrelated catalog and ordinary node population
  native src/check/capability_contracts.zig: owned capability recipe unknown indices preserve nested alternatives and budget rollback
  guest  tests/scoped_capability_diagnostics.test.ts: explicit generic operations reject shorter authority at source and compiled storage sinks
```

### Usage: moves, aliases, branches, loops, once/many

```text
Moves
  native src/check/usage_check_tests.zig: usage qualifiers preserve affine moves aliases and branch ownership
  native src/check/usage_check_tests.zig: usage immutable break operands retain executable owner moves
  native src/check/usage_check_tests.zig: usage fresh scalar inputs preserve ownership without casting existing bindings
  guest  tests/usage_execution.test.ts: usage exit and exact loop contracts execute across imports and failed retained edits

Aliases
  native src/check/usage_check_tests.zig: usage qualifiers preserve affine moves aliases and branch ownership
  native src/check/usage_check_tests.zig: usage portable calls reject hidden loan capture arguments through aliases
  native src/check/usage_check_tests.zig: usage immutable Core rejects repeated owners independently of source and capture catalogs
  guest  tests/usage_sharing_execution.test.ts: explicit sharing preserves ownership across imports archive retained restart and once captures

Branches
  native src/check/usage_check_tests.zig: usage failed guards retain outer moves and cannot consume pattern owners
  native src/check/usage_check_tests.zig: usage closures discover guard and if let capture ownership
  native src/check/usage_check_tests.zig: usage immutable control flow reconstructs nested return guard fallthrough and break moves
  native src/check/usage_check_tests.zig: usage nested do returns restore the enclosing owner flow

Loops
  native src/check/usage_check_tests.zig: usage exact one iteration bounds admit outer owners and reject later reuse
  native src/check/usage_check_tests.zig: usage loop breaks and returns carry moves without creating a backedge
  native src/check/usage_check_tests.zig: usage range bounds execute once before loop ownership joins
  guest  tests/usage_execution.test.ts: usage exit and exact loop contracts execute across imports and failed retained edits

Once/many
  native src/check/usage_check_tests.zig: usage once calls cannot repeat or hide in many closures
  native src/check/usage_backend_tests.zig: once public entry guards retain exact multiplicity through replay and failed publication
  native src/reuse/dependency_interface_tests.zig: usage captured once factory keeps its ownership boundary in portable Core
  guest  tests/usage_execution.test.ts: usage once contracts survive imports retained failures restart and sync JSPI execution
  guest  tests/usage_once_entry_execution.test.ts: public once exports consume native and guest invocation authority (development)
```

### Usage: loans, sharing, qualified polymorphic calls

```text
Loans
  native src/check/usage_check_tests.zig: usage lexical loans restore owners and reject result capture and conflicting access
  native src/check/usage_check_tests.zig: usage immutable loan reads retain lexical region ownership and reject retired reads
  native src/check/usage_check_tests.zig: usage loan callbacks cannot pass captured region authority to unknown callees
  native src/check/usage_backend_tests.zig: borrow backend preserves loan identity and rejects malformed read descriptors
  guest  tests/usage_execution.test.ts: usage loan regions execute imported reads and survive failed edits restart and JSPI
  guest  tests/usage_backend_execution.test.ts: borrow backend preserves scalar machines captured callbacks and owner order (optimized)

Sharing
  native src/check/usage_check_tests.zig: usage sharing consumes unique owners and permits repeated immutable scalar collection views
  native src/check/usage_check_tests.zig: usage sharing reconstructs portable consumption and rejects owning result forgeries
  native src/check/usage_backend_tests.zig: usage sharing backend preserves managed owners replay and rejects unsealed conversion authority
  guest  tests/usage_sharing_execution.test.ts: explicit sharing preserves ownership across imports archive retained restart and once captures

Qualified polymorphic calls
  native src/check/package_contracts_tests.zig: qualified package interfaces retain owner moves operations and lexical borrow through all allocation failures
  native src/check/usage_check_tests.zig: usage qualified returned callbacks preserve lambda and declaration header capture boundaries
  native src/reuse/module_frontend_tests.zig: shared dependency validators retain exact rank usage and numeric foreign owner graphs through OOM
  guest  tests/usage_forall_execution.test.ts: explicit affine forall preserves resource moves through imports archives and restart (development)
  guest  tests/rank_region_execution.test.ts: region forall readers preserve loan owners across imports edits archives and restart (development)
  guest  tests/dependency_owner_memo.test.ts: shared dependency validation owns actual foreign rank usage and proof inputs across archives edits rollback and restart
```

### Resources: return/break/trap, host failure, suspended cancellation

```text
Return/break/trap
  native src/check/usage_check_tests.zig: usage owning capture and control flow preserve cleanup on every allocation failure
  native src/check/usage_check_tests.zig: resource scalar scopes check finite pure cleanup and fresh loans
  native src/check/usage_backend_tests.zig: resource backend cleanup journals preserve replay and every failed allocation
  guest  tests/resource_execution.test.ts: resource scalar scope executes finite cleanup across sync JSPI failures and retained restart
  guest  tests/resource_execution.test.ts: resource typed journal drains compiled traps and suspended failures with flat roots and memory in both tiers
  guest  ../compiler/resource_journal.test.ts: resource journal takes each owner before cleanup and drains LIFO after failures

Host failure
  native src/check/usage_check_tests.zig: resource host cleanup accepts exact synchronous descriptor roles and excludes ordinary callbacks
  native src/check/capability_lifetimes_tests.zig: resource lifetime cleanup failure grants no complete report and unknown terminating callbacks decline through OOM
  guest  tests/resource_reference_execution.test.ts: reference resource journals own payload roots through cleanup traps host rejection and suspension
  guest  tests/resource_host_cleanup_execution.test.ts: host cleanup descriptors remain synchronous and drain every attempt (development)
  guest  ../compiler/resource_journal.test.ts: resource journal preserves drop failures and never retries an explicitly released owner
  guest  ../compiler/resource_guest.test.ts: resource publication allocation failure attempts cleanup once and leaves no phantom owner

Suspended cancellation
  native src/check/usage_check_tests.zig: resource request cancellation admits invocation owners without closing unrelated effects
  native src/check/usage_check_tests.zig: resource request cancellation rebuilds suspension and protocol contracts independently
  native src/check/usage_check_tests.zig: resource request cancellation publication releases every allocation failure
  guest  tests/resource_request_execution.test.ts: resource request cancellation retires owned frames and preserves exact cleanup order (development)
  guest  tests/resource_transfer_execution.test.ts: resource transfer retirement preserves roots through cancellation cleanup failures and warmed recovery
```

### Resources: transfer, retirement, persistent journal, structural host roles

```text
Transfer
  native src/check/usage_check_tests.zig: resource transferred owners preserve explicit contracts and reject captured loan cleanup authority
  native src/check/usage_check_tests.zig: resource transfer publication reconstructs owned effects and releases every allocation failure
  native src/check/usage_backend_tests.zig: resource acquired owners execute through exact Core and backend contracts
  guest  tests/resource_transfer_execution.test.ts: resource transfer keeps acquired boxes through source moves sharing captures and explicit release
  guest  tests/resource_transfer_execution.test.ts: resource transfer preserves source archive checkpoint restart and failed revisions
  guest  ../compiler/resource_guest.test.ts: resource transfer validates live box identity before journal mutation and commits exactly once

Retirement
  native src/backend/runtime_flags_tests.zig: resource retirement enables only an exact typed import and ordinary Wasm has zero hook overhead
  native src/backend/runtime_flags_tests.zig: resource retirement final lowering and publication release every allocation on OOM
  guest  tests/resource_retire_execution.test.ts: owning retirement enqueues once after child accounting and before box free
  guest  tests/resource_retire_execution.test.ts: owning cycle retirement enqueues once at exhausted heap with no cleanup reentry
  guest  ../compiler/resource_journal.test.ts: resource retirement defers callbacks and drains newly retired captures at a safe point

Persistent journal
  native src/check/usage_check_tests.zig: resource transferred owners cannot enter persistent module startup storage
  native src/check/usage_backend_tests.zig: public owner leases and owned cleanup roles survive replay and allocation failure
  native src/check/usage_backend_tests.zig: owning entry bridges box fresh inputs and publish typed persistent leases
  guest  ../compiler/resource_journal.test.ts: persistent resource registrations survive invocation leave and release once on retirement or disposal
  guest  ../compiler/resource_journal.test.ts: persistent cleanup bindings follow each registered attempt through compaction and failures
  guest  tests/public_owner_execution.test.ts: public owners retain exact native lifetimes and synchronous cleanup bindings (development)

Structural host roles
  native src/check/usage_backend_tests.zig: structured host cleanup schemas retain source roles through replay and every failed allocation
  native src/check/usage_check_tests.zig: resource host cleanup immutable role rejects metadata promotion before indexed reads
  native src/check/usage_check_tests.zig: resource host cleanup publication releases every failed allocation
  guest  tests/structural_host_cleanup_execution.test.ts: closed data cleanup descriptors preserve exact source and persistent lifetimes (development)
  guest  tests/structural_host_cleanup_execution.test.ts: scoped structured cleanup needs no persistent owner ABI
  guest  tests/resource_host_cleanup_execution.test.ts: host cleanup imports preserve exact roles through archives and restarts
  guest  ../compiler/cleanup_data.test.ts: cleanup data schemas reject missing edges false roles hidden features and unsupported cycles
```

### Higher rank: structural rank, annotated recursion, skolems, bounded rejection

```text
Structural rank
  native src/check/package_contracts_tests.zig: structural rank introductions reconstruct multiple binders products records and concrete instances
  native src/check/package_contracts_tests.zig: structural rank introductions preserve immutable admission and ABI through every allocation failure
  guest  tests/rank_structural_execution.test.ts: parametric rank templates execute structural results nested captures and independent dynamic instantiations
  guest  tests/rank_carrier_execution.test.ts: rank two annotated record fields retain their universal storage interface

Annotated recursion
  native src/check/package_contracts_tests.zig: structural rank introductions reconstruct multiple binders products records and concrete instances
  native src/check/check_tests.zig: annotated higher rank callbacks use fresh rigid scopes and per-call instances
  guest  tests/rank_structural_execution.test.ts: parametric rank templates execute structural results nested captures and independent dynamic instantiations
  guest  tests/rank_carrier_execution.test.ts: rank two callbacks execute one parametric carrier across U32 and F32 instances

Skolems
  native src/check/check_tests.zig: annotated higher rank callbacks preserve scope ownership under every allocation failure
  native src/check/types_tests.zig: owned higher rank binders alpha compare instantiate and reject rigid assignments
  native src/check/check_tests.zig: existential package source checks seal witnesses open rigid identities and reject lexical escape
  guest  tests/rank_carrier_execution.test.ts: rank callbacks reject concrete-only implementations

Bounded rejection
  native src/check/check_tests.zig: annotated higher rank callbacks reject unsupported sorts and evidence with diagnostics
  native src/check/package_contracts_tests.zig: canonical package body walking shares admission budget across a forged DAG
  native src/reuse/dependency_interface_tests.zig: portable identity binder owners reject ordinal sort and distinct owner reuse
  guest  tests/rank_carrier_execution.test.ts: rank callbacks preserve fresh retained failed edit and revert results in both tiers
```

### Higher rank: row/region binders, predicates, associated evidence, dictionaries

```text
Row binders
  native src/check/types_tests.zig: owned higher rank row binders retain alpha scope substitution and independent solving through OOM
  native src/check/check_tests.zig: annotated higher rank row callbacks retain fresh instances sorted scopes and conservative rows through OOM
  native src/check/package_contracts_tests.zig: sorted universal row carriers retain owned formal rows dynamic calls and Foreign publication
  guest  tests/rank_row_execution.test.ts: quantified row carriers preserve independent pure and Foreign instantiations across dynamic calls and archives

Region binders
  native src/check/types_tests.zig: owned higher rank region binders keep sorted inference and scope through all allocation failures
  native src/check/check_tests.zig: annotated higher rank region callbacks check introduction calls and loan escape
  guest  tests/rank_region_execution.test.ts: region forall readers preserve loan owners across imports edits archives and restart (optimized)

Predicates
  native src/check/types_tests.zig: quantifier predicates retain alpha equality exact contract identity scope and rollback through OOM
  native src/check/universal_dictionary_tests.zig: universal predicate introductions own lexical method givens through complete allocation failures
  native src/check/universal_dictionary_tests.zig: universal predicate eliminations independently discharge caller evidence through complete allocation failures
  native src/check/package_contracts_tests.zig: ordinary inferred predicate schemes coexist with annotated universal bodies through OOM
  guest  tests/rank_inferred_predicates_execution.test.ts: ordinary constrained helpers execute beside universal values
  guest  tests/rank_inferred_predicates_portable_execution.test.ts: ordinary inferred predicate schemes retain exact publication through archives checkpoints and restart

Associated evidence
  native src/check/package_contracts_tests.zig: associated package and universal projections require exact active goals and independent opening substitutions through OOM
  native src/check/package_contracts_tests.zig: ordinary projection endpoints require their exact owning scheme contract through OOM
  guest  tests/rank_ordinary_projection_execution.test.ts: ordinary scheme projections keep each selected associated type beside forall
  guest  tests/rank_inferred_predicates_execution.test.ts: ordinary associated helpers retry a compatible right owner beside forall

Dictionaries
  native src/check/universal_dictionary_tests.zig: universal library implementation givens require the exact owning method and head through full OOM
  native src/backend/runtime_operation_backend_tests.zig: universal dictionary forwarding keeps exact lexical evidence through every backend allocation failure
  native src/backend/layout.zig: universal dictionary layouts preserve exact ordered slots and empty ABI through owned snapshots and complete allocation failures
  guest  tests/universal_dictionary_execution.test.ts: stored universal dictionaries select each actual caller witness
  guest  tests/universal_dictionary_portable_execution.test.ts: universal dictionaries preserve exact evidence across dependency archives checkpoints failure recovery and warmed ownership
```

### Packages: sealing, heterogeneous carriers, openings, stored evidence

```text
Sealing
  native src/check/check_tests.zig: existential package source checks seal witnesses open rigid identities and reject lexical escape
  native src/check/package_contracts_tests.zig: package sealing proves latent captured identity even when result types are closed
  guest  tests/package_execution.test.ts: closed existential witnesses survive constant opening and resealing before Wasm emission
  guest  tests/package_runtime_execution.test.ts: package abstraction rejects direct reflection and hidden value escape

Heterogeneous carriers
  native src/eval/core_eval_tests.zig: runtime structural packages adapt stored operations over heterogeneous witnesses
  native src/eval/core_eval_tests.zig: runtime identity packages emit mixed scalar carriers and lexical resealing
  native src/check/package_sequence_tests.zig: small package collection carriers preserve complete replay and emission allocation failures
  guest  tests/package_runtime_execution.test.ts: runtime existential operation adapters preserve heterogeneous payloads
  guest  tests/package_sequence_execution.test.ts: package adapters convert Array elements and packed rows in both directions
  guest  tests/package_static_execution.test.ts: static package arrays and Lists retain each abstract element

Openings
  native src/check/package_contracts_tests.zig: package lexical owners reject stolen slots inactive openings and unsealed witnesses
  native src/check/package_contracts_tests.zig: checked multi binder package Core reconstructs pack and lexical opening substitutions
  native src/eval/core_eval_tests.zig: owned existential values carry independent witnesses through lexical opening and resealing
  guest  tests/package_runtime_execution.test.ts: runtime package adapters carry references floats records and independent openings
  guest  tests/rank_nested_opening_execution.test.ts: universal bodies execute nested existential openings with distinct witnesses

Stored evidence
  native src/check/package_contracts_tests.zig: predicate package packing records the exact checked dictionary and callable member through OOM
  native src/backend/runtime_operation_backend_tests.zig: static package carriers and stored methods preserve owned emission replay through every allocation failure
  native src/reuse/dependency_interface_tests.zig: portable two binder packages publish checked producer operations
  guest  tests/package_dictionary_execution.test.ts: predicate package methods follow each runtime witness
  guest  tests/package_dictionary_portable_execution.test.ts: predicate package goals preserve independent stored methods across source archives restart and recovery
  guest  tests/package_portable_execution.test.ts: portable two binder packages execute source archive checkpoint restart and failed edit recovery
```

### Packages: resealing, associated payloads, captures, affine ownership

```text
Resealing
  native src/check/package_contracts_tests.zig: package lexical resealing discharges only witnessed abstract identities
  native src/check/package_contracts_tests.zig: dictionary resealing preserves exact opening and universal evidence through complete OOM
  guest  tests/package_dictionary_resealing.test.ts: dictionary resealing rejects changed witnesses and unsealed method captures
  guest  tests/package_dictionary_resealing_portable.test.ts: dictionary resealing transports exact lexical and universal evidence across archives restart and recovery

Associated payloads
  native src/check/package_contracts_tests.zig: package associated payloads reject ambient missing and incompatible evidence through OOM
  native src/check/package_contracts_tests.zig: package payload projections use only their own selected type members through OOM
  native src/check/package_contracts_tests.zig: associated package representation uses only the exact pack selected type member through OOM
  guest  tests/package_associated_payload_execution.test.ts: associated package payloads retain heterogeneous representations across resealing
  guest  tests/package_associated_payload_portable.test.ts: associated package payloads retain exact equations across source archives restart and recovery

Captures
  native src/check/package_contracts_tests.zig: immutable closed dictionary captures require exact goal witness resealing through OOM
  native src/check/package_contracts_tests.zig: package immutable result footprint sees hidden closure references despite forged capture lists
  native src/check/package_contracts_tests.zig: source dictionary closures retain scoped goals with closed signatures and allow exact witness resealing through OOM
  guest  tests/package_dictionary_capture_execution.test.ts: closed dictionary calls and exact witness resealing execute
  guest  tests/package_static_execution.test.ts: static package products adapt callbacks and retain ordinary captures

Affine ownership
  native src/check/package_contracts_tests.zig: qualified package interfaces retain owner moves operations and lexical borrow through all allocation failures
  native src/check/package_contracts_tests.zig: qualified package interfaces reject erased owner qualifiers and forged pure resource bodies
  native src/check/usage_check_tests.zig: usage nominal phantom package witnesses cannot erase affinity before payload traversal
  guest  tests/package_owned_execution.test.ts: explicit owning package interfaces preserve resource cleanup through retained checkpoint recovery
  guest  tests/package_owned_execution.test.ts: imported owning package operations retain their principal and cleanup in archives
  guest  tests/usage_nominal_execution.test.ts: nominal and opaque affinity preserve source archive and restart owner flow (development)
```

## Measured scope cost

Both controls return `[11,102,10,100]`: two closed static families versus two
fresh scoped State owners. Seven alternating compiler pairs use five fresh
processes per variant, disabled persistence and child user plus system CPU.
Median fresh CPU is 1.6322 ms static and 1.7874 ms scoped (ratio 1.0951).

Thirty-one warmed guest pairs per execution mode use 2,048 calls per sample,
including identical result copying. Median sync call cost is 1,181.7 ns static
and 1,489.6 ns scoped (ratio 1.2605); JSPI is 2,532.6/2,737.1 ns (1.0807). All
result checks pass and warmed memory stays flat.

Seven repetitions also separate retained-project phases. These wall times
include IPC and do not qualify the captured-project CPU targets:

| Workload       | Population ms | First edit ms | Revert ms | No-op ms | Restart ms |
| -------------- | ------------: | ------------: | --------: | -------: | ---------: |
| Static State   |        2.5374 |        2.1689 |    1.9133 |   0.8259 |     2.3010 |
| Scoped State   |        2.5223 |        2.5023 |    2.1602 |   0.8633 |     2.6269 |
| Resource scope |        1.8337 |        1.6419 |    1.4306 |   0.7313 |     1.8615 |

All phases preserve fresh/revert bytes. Exact inputs, executable identity and
every raw sample are in
`build/bench/finish-rest-20261015/language-contracts-v2/`.
