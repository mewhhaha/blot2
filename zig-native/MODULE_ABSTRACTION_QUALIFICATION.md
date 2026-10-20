# Module abstraction implementation qualification

The implementation follows [module abstraction](MODULE_ABSTRACTION.md).
Declarations remain public by default; sparse AST traits add contextual privacy
and opaque declarations without growing every syntax node. Selective forwarding
uses the existing module graph and preserves declaration kind and original
producer. Opaque declarations reuse ordinary constructor checking, matching and
nominal identity; imported semantic catalogs omit their payloads and
constructors.

Editor queries keep source locations separate from opaque nominal name handles;
imported completion exposes neither private names nor representation fields.

An owned compact descriptor supplies exact machine type and ownership, including
variable selection through public structured type parameters. Bounded proofs
check the defining Core payload; unknown/exhausted recipes decline emission.
Scalar/reference wrappers erase to their payload without a tag, cell or extra
reference. Public graph/predicate scans and delayed generic dispatch enforce
privacy before executable emission. No new solver pointer escapes into Core,
public interfaces, storage contracts or artifacts.

Dependency wire version is 2; dependency settings and backend checkpoint
settings are versioned separately. Old schemas rebuild. Principal snapshots
retain positional tombstones for private declarations but remove their names,
type roots, associated members and private parameter patterns. The executable
owner remains available for legitimate specialization. Artifact admission
rejects private promotion, mismatched opaque identity/ABI, duplicate nominal
identities and forwarding to unreachable producers. Failed candidates retain
last-good owners and output.

## Focused checks

These are the original task 052 focused results; later full qualifications
follow.

Zig 0.17.0 was checked before every build batch. The focused native run passed
37 laws (module abstraction, allocation-budget and editor completion filters),
the LLVM executed- Wasm run passed 31 laws, and the analyzer checked 339 files
with zero findings. The parent owns the mandatory combined full
compiler/analyzer gate before integration; this isolated handoff makes no
full-gate claim.

Focused native laws cover construction, alias/namespace privacy, distinct
producers, forwarding of every declaration kind, public signature/predicate
escapes, fixed nominal name identity, source/compiled ownership, forged storage
contracts and private constructor promotion. Deterministic allocation-failure
sweeps cover decode/validation/re-encoding/relocation and opaque revision
publication; failed publication leaves prior owner pointers, artifact stamp and
revision intact, then succeeds on retry. Existing allocation-budget laws pass.

Executed-Wasm checks cover U32/F32 bits, negative zero/NaN/infinity, generic and
structured parameters, callable constructors, reference aliases/projections,
staged aggregate scalar relocation, scalar-to-reference representation edits
with unchanged public signatures, Foreign callback capture, scalar heap absence,
direct/forwarded source and compiled imports, checkpoint process restart, failed
revisions and recovery. Delayed generic fields and private associated arithmetic
decline outside their producer. Legacy constructor, alias, contract,
shaped-parameter, dependency and checkpoint suites remain exercised.

## Measurements

The release was built in `zig-native/` with Zig 0.17.0 using
`zig build install -Doptimize=fast --prefix zig-out` (LLVM enabled by the build
rules). The incoming release baseline is
`272f028932b0cc563049fe7e5f6f51139304f0ae4cf7213351fd55f5f5f7a127`; the
candidate is `cfafd394694d2394ef299ef9eeab12699949678da5623e5936d3175c67dcfcd6`.

Seven alternating compiler pairs on CPU 6 use `scripts/bench_compile.ts`,
`--workload synthetic --restart-cache --runs 7`. Baseline/candidate and
fresh/retained Wasm are identical; fresh work counters are identical. Median CPU
milliseconds and fresh requested bytes are:

| Workload         | Fresh CPU baseline → candidate | Restart CPU baseline → candidate | Requested bytes baseline → candidate |
| ---------------- | ------------------------------ | -------------------------------- | ------------------------------------ |
| Mono chain 128   | 13 → 14                        | 14 → 14                          | 8,169,536 → 8,178,258                |
| Generic chain 64 | 14 → 14                        | 14 → 14                          | 8,377,859 → 8,378,597                |
| Diamond 8        | 8 → 8                          | 8 → 8                            | 4,169,608 → 4,170,306                |
| Fanout 128       | 25 → 25                        | 25 → 26                          | 16,161,168 → 16,169,866              |

Fresh requested bytes rise 0.009–0.107%; peak live bytes rise 0.007–0.096%.
Retained population/edit median wall ratios span 0.864–1.041; noop medians span
0.415–0.637 ms. Retained CPU ticks are 10 ms, so zero/tied medians do not
establish small gains or losses. Host load was 11.37 → 11.42 while the parent
gate used other cores; these short loaded samples are cost evidence, not a
speedup claim.

`scripts/bench_module_abstraction.ts` compares transparent and opaque F32 sum
and reference alias operations, using 15 alternating pairs, 100 warmups and 64
calls/sample on CPU 6. Scalar median CPU is 83.344 → 83.016 μs/call (paired
ratio median/p90 0.9976/1.0058); reference median CPU is 3.734 → 3.703 μs/call
(paired ratio 1.0000/1.0317). Whole modules differ: 190 → 228 scalar bytes and
3,373 → 3,404 reference bytes. No whole-module parity or runtime gain is
claimed. The scalar no-memory law proves heap absence for that case; exact
operation-body and allocation-traffic qualification across the eligible wrappers
now passes in the final task 053 record below.

Raw distributions, source/Wasm/binary hashes and commands are retained in
`build/bench/module-abstraction/{compile,erasure,pins.json}`. Focused commands
are `zig build test -Dllvm=false -Doptimize=safe` with module abstraction,
budget and editor completion query filters; the ten selected executed-Wasm files
run with `deno test --allow-all`; `deno task lint:zig` uses the qualified
analyzer.

## Limits and next qualification

The original handoff used positional interface/catalog comparisons. The final 20
October continuation below qualifies private insertion, declaration relocation,
alpha changes and bounded public contract/associated/implementation
correspondence for task 053's fixed rows. Unsupported rank, usage,
selected-proof and exhausted forms keep task 024's ordinary-checking limits.
Public contracts and original producer identities still compare exactly;
executable dependencies invalidate independently of semantic caller reuse.

Deep, exhausted or unresolved ABI proofs decline emission rather than guess a
machine/ownership type. Forwarding and public scans retain fixed graph budgets.
Namespace-wide exports are outside the reviewed syntax. These limits preserve
language access rules and artifact admission.

The incoming base predates task 032's result roles and root journals. After
integration, rerun the scalar/reference/callback, aggregate and retained
ownership laws against those new result/capture/root-slot rules; this handoff
cannot qualify that later representation by itself.

## Host syntax and editor compatibility

The separate tooling correction updates `grammar.baba`, Baba island metadata and
same-width contextual markers; it preserves private/opaque/export as ordinary
binding and parameter names outside declaration headers. Constructor-pattern
lambda parameters and typed parameters have distinct recognition paths. The
formatter remains unchanged and verifies the resulting CST before publishing.

Run `deno task generate:parser`, then the syntax/formatter tests with the pinned
052 compiler argument. All 14 laws pass, including original/formatted opaque
source and selective-forwarding project Wasm equality, public example/std
formatting, CRLF/origin preservation, contextual names and reserved-marker
rejection. `deno check` and no-config formatting checks pass.

The qualified Tree-sitter 0.27.1 CLI generates from `grammar.js` with ABI 14.
`deno task check:editor` passes four corpus parses, all 14 highlight fixtures
(including 20 new assertions) and public example parsing;
`deno task test:editor` passes six Helix laws. Contextual highlights preserve
bare export/private/opaque identifiers. No generated output was hand-edited. The
input-only patch requires both generator tasks before host/editor validation.

Fifteen alternating CPU-6 formatter pairs on `examples/syntax.blot` preserve
identical formatted text. Median CPU is 41.636 → 49.008 ms; paired median/p90
ratios are 1.0824/1.5455 (host load 4.86). This short screen includes frontend
creation and variable JIT/GC costs; it shows additional host cost, not a
speedup. The generated parser plan grows 726,137 → 780,662 bytes. Native
compiler sources and the pinned LLVM binary are unchanged by this correction.
Raw commands and samples are in `build/bench/module-abstraction/tooling/`.

## Integrated qualification — 12 October 2026

Local implementation `f184dde` jointly qualifies tasks 052, 033 and 038 and
records the reviewed 054 specification. Its staged tree is
`1431522db1bd9b93b1e0b3f3f69949e2122aa5e6`; the compiler source tree used for
the build is `310d60ce85a8ebe26f3c9f4d48fc35811fd98a94`. The intervening changes
correct the raw dependency-header test to version 2 and format two client tests;
compiler inputs are unchanged. The standard Zig 0.17.0 LLVM Fast build has
SHA-256 `5c689ad5caad6952f1c4643f5c40e10d6e41bcf819bf016f751ac105d82020a1`, size
40,838,704 bytes and compiler identity
`bb6bda62bee29cebe741d9f3baf9b8184cc722a1691c109ecc43e1feef2f1ed5`.

The required `deno task test:compiler` passes all 1,400 native laws and 871
guest/client laws. All eight unchanged release allocation budgets pass.
`ZIG_ANALYZER=build/tools/zig-analyzer/zig-out/bin/zig-analyzer deno task lint:zig`
checks 343 files with zero findings. Host syntax/formatter, generated parser,
Tree-sitter corpus/highlights and Helix checks above also pass. Native
deterministic OOM and executed source/compiled/checkpoint laws exercise the
combined representation, roots, callbacks and privacy rules.

The incoming release is the earlier qualified `2798ff9` artifact, SHA-256
`b802365944a69db01df83442db960a8fd7b717828f7cbb1ac5aba2b661d80d17`. Seven
alternating CPU-6 pairs cover all 13 public examples with restart caching
explicitly disabled and checked absent. Public median CPU ratios range
1.0042–1.0292; requested-byte deltas range −312 to +39,350 and peak deltas +376
to +960. Every teardown has zero live requested bytes. No overall speedup is
established. Twelve modules intentionally change Wasm for counted ownership
helpers; the scalar module stays byte equal, and each variant is stable across
its seven repeats. Semantic/prepared counters match except the exact
`requests.blot` allocation-role correction, 19 → 20, caused by proper
Request/Pair reference classification. The harness permits only that change.

Seven further alternating pairs cover four synthetic graphs through fresh,
population, edit/revert, no-op and checkpoint restart. All cross-variant and
within-variant Wasm comparisons pass, including edited output against fresh
edited builds; the harness reports no problems. Median process CPU is:

| Workload         | Fresh baseline → candidate | Restart baseline → candidate |
| ---------------- | -------------------------- | ---------------------------- |
| Mono chain 128   | 13 → 13 ms                 | 12 → 13 ms                   |
| Generic chain 64 | 12 → 12 ms                 | 12 → 12 ms                   |
| Diamond 8        | 7 → 8 ms                   | 7 → 7 ms                     |
| Fanout 128       | 24 → 23 ms                 | 24 → 24 ms                   |

Retained CPU uses coarse 10-ms ticks; tied/zero phases do not establish small
gains or losses. Public load was 4.09; synthetic load was 3.73 → 3.91. A
separate cached public run remains supplemental evidence, not the cold result.
These combined costs do not replace the focused callback improvement or close
the host-call CPU gate recorded in
[suspended ownership](SUSPENDED_OWNERSHIP.md).

Rejected attempts remain separate: `e2492ea4…` failed native compilation at an
incorrect test result field and exceeded the fanout budget by 4,856 bytes;
`bb85a4e0…` passed budgets but failed two of 1,400 native laws. Removing
redundant export producer-name fields restored allocation headroom without
weakening original-target/visibility checks. The privacy gate now permits unused
public lexical-table growth while rejecting private bits in any unmatched tail;
an old local-name fixture now checks its deliberately redacted name by original
binding ordinal. The first final-binary gate passed native laws but failed four
guest assertions expecting dependency version 1. Updating that raw-wire
assertion to version 2 yields the passing required gate above.

Immutable binaries, complete hashes, correction patches, rejected logs,
allocation results and raw distributions remain under ignored
`build/bench/joint-052-033-038-054/`. Accepted evidence is
`qualified/{binary-pins.json,compiler-gate.log}` and
`final/{analyzer.log,budgets-early.log,public-cold/,public-summary.json,synthetic/}`.
Tasks 024/053 still own broader semantic cutoffs and wrapper-operation
qualification; tasks 034/035 own complete cycle reclamation and final tracing
removal. No push or whole-program completion is claimed.

## Current closed-row screen, 19 October 2026

A release screen on the `0f531509…` compiler uses an opaque producer, an
unchanged forwarding module and an unchanged entry, with persistence disabled.
All seven edits match fresh bytes and execute the expected result. The body
control, parameter alpha-renaming and a private record-field rename each reuse
both semantic callers. Inserting an unrelated private declaration before the
opaque type, relocating a private declaration, changing U32 storage to F32, and
changing it to an Array representation still recheck both callers.

| Edit                                     | Intermediate / entry reused | Body elaborations |
| ---------------------------------------- | --------------------------- | ----------------: |
| Private body control                     | 1 / 1                       |                 3 |
| Private declaration inserted before type | 0 / 0                       |                 6 |
| Private declaration moved                | 0 / 0                       |                 5 |
| Parameter alpha-renamed                  | 1 / 1                       |                 3 |
| Opaque U32 storage changed to F32        | 0 / 0                       |                 4 |
| Private field renamed                    | 1 / 1                       |                 3 |
| Opaque storage gains a reference         | 0 / 0                       |                 4 |

The screen is source-only optimized codegen, not the complete source/archive/
checkpoint acceptance matrix. It does not close task 053. Its raw work records
are `build/bench/task053-current-screen/results.json`.

Current cutoff comparison includes positional principal slots and exact external
binding targets, so declaration movement cannot be admitted merely by ignoring
private fields. The backend layout store resolves opaque physical storage
through the current producer modules (`layout.Store.opaque_sources`). That
boundary is relevant to separating semantic equality from changed ABI and
ownership recipes, but any broader reuse still needs fresh-output, changed
storage, failed-publication and allocation-failure laws. Existing guards remain
in force; no screen result is a reason to relax them.

## Task 053 continuation (19 October 2026, qualification in progress)

This heading preserves existing links to the chronological record and law map.
The [final qualification](#final-task-053-qualification-20-october-2026) closes
the fixed rows on the repaired source.

The continuation separates a known opaque machine recipe from semantic caller
equality. Nominal identity, visibility, public schemes, relationships, graph
sharing and unknown recipes retain their exact checks. A hidden constructor's
AST ordinal may move only under its matched, known opaque parent; its unit,
catalog slot, tag, privacy and remaining facts still match. Artifact and
executable admission retain their original identities and recipes.

A changed recipe stops semantic propagation through ordinary callers, while the
backend consumes the current producer's Core. An unchanged module or entry that
itself defines an opaque representation must republish a derived recipe when its
payload reads the changed producer. This is counted as `storage_rechecks`, not
semantic reuse. Imported recipes come from the current original producer;
forwarding catalogs retained for semantic purposes cannot replace that producer
with an old copied recipe. Locally defined opaque payloads are all visited, so
unrelated local nominal edges do not force a prefix lookup or spurious recheck.
Unknown, scoped, unsupported or exhausted proofs retain ordinary checking.

Small known opaque adapters now use the existing bounded source inliner outside
loops. The 64-node budget, depth six, emitted-code limit, dictionary and erased
layout checks remain, as does the exact `readInlineBody` executable dependency.
Opaque payload binding skips failure control only when a bounded structural
proof finds an irrefutable pattern. Nested literals and ordinary data
constructors keep their tests and failure paths. This exposes an ordinary record
projection to scalar replacement without adding new executable reuse authority.

Artifact validation recomputes derived opaque storage from original producer
Core and parameter shapes. A bounded, iterative proof starts every foreign role
as unknown and admits only roles derived from concrete payloads and already
proved foreign roles. The complete closure's Core graphs validate before these
cross-owner reads. A consumer copy, a forged parameter selector or mutually
asserted foreign recipes cannot authorize a machine role. Positive shuffled
producer chains and immutable-owner allocation-failure sweeps exercise the same
boundary. Numeric check planning also preserves an exact collection operand
through single-constructor, repeatable opaque reference adapters. It reads the
executable construction and unpacking; an arbitrary index still retains its
bounds check.

### Acceptance row to law map

These are implementation and focused-check results. The first forced full run
(`run-a5e748107d1cfcc`) passes 2,476 native laws with zero skips, failures,
leaks or logged errors; 1,570 guest/client checks and 37 harness checks pass
too. Both analyzers and the local uncached check report zero findings over 507
source files and the fixture module on that source.

A subsequent negative control admits a circular foreign recipe assertion at that
release, SHA-256
`8a8cfb7c1f2549bf93f07fdbe78a1b5c6b350def7f2bdef46239dab23aadfb8c`:
`expected error.InvalidArtifact, found void`. The new positive-only closure
proof rejects it and passes the original-producer and parameter-selector laws.
The integrated relocation/closure-proof continuation passes both analyzers and
the activated local uncached check over 510 source files and the fixture module.
Its first full attempt stopped at a harness startup race before release/native
compilation. The test now waits for descendant readiness before triggering the
budget signal and checks the elapsed-time timer independently. The replacement
build (`run-6c8eee0c61e92a8e`) was intentionally stopped to finish the
private-catalog and public-effect correspondence controls. The complete gate on
the integrated source (`run-5ff7fbd61da7a31a`, 20 October) passes **2,484 native
laws executed, 1,574 guest/client checks and 37 harness checks**. Native laws
have zero skips, failures, leaks or logged errors. Wall time is 4,352.67 s; the
native compile and execution phases are cache misses. The native input digest is
`8a673d2a618b86d9d89c7952daa474fb9ae1655953ee63ffbc0ec8c4af2efdce`; the test
executable is
`7593408b9110b701a846539ef0375d990354f726194764f89547a2f4f99425ef`. The timing
report has SHA-256
`f4928e303c17876822447b803f412c4fe84ec8b947b0661a83503df34f1343b1`. The final
compile/CPU qualification below also passes this source. That milestone preceded
the public-contract and catalog follow-ups; the final qualification supersedes
its open task status.

| Row | Laws and observations                                                                                                                                                                                                             | Current result                                                                                                                                                                              |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Native `module interface cutoff reuses opaque callers when every dependency is dirty through OOM`; both-tier `module_cutoff_all_dirty_execution.test.ts`                                                                          | Existing body cutoff; current full gate passes                                                                                                                                              |
| 2   | Native `inert principal suffixes retain opaque callers through private local edits and OOM`, with changed-prefix, omitted-slot and namespace rejection controls                                                                   | Existing suffix cutoff; current full gate passes                                                                                                                                            |
| 3   | Native owned-reference, public-contract, associated and implementation/member correspondence OOM laws; both-tier relocation, public-contract, associated and implementation guests                                                | Full gate passes private binding/type/effect/contract insertion and movement, public contract/catalog correspondence, symbolic getters and bounded original method capability relationships |
| 4   | Native generic parameter alpha and public effect parameter alpha OOM laws; value-alpha storage law and both-tier relocation/effect guests                                                                                         | Type/scheme/value/effect alpha reuse, actual handled effect invocation, fresh/source/archive/checkpoint and failed-edit parity and full gate pass                                           |
| 5   | The same native law and both-tier storage guest law, U32 → F32 → U32                                                                                                                                                              | Focused semantic callers reuse; current machine consumers rebuild                                                                                                                           |
| 6   | The same native and guest laws, equal-layout private record field rename                                                                                                                                                          | Focused callers reuse with fresh executable parity                                                                                                                                          |
| 7   | Those laws plus `opaque derived storage producers refresh their recipes while semantic callers reuse through OOM`; derived-storage guest scenarios                                                                                | Focused scalar/reference transitions, derived module/entry refresh, unrelated opaque reuse, roots, rollback and restart pass                                                                |
| 8   | Native `opaque semantic comparison preserves identities visibility contracts and unknown-storage declines`; project-check module abstraction privacy, producer and forwarding laws; `module_abstraction_import_execution.test.ts` | Identity, visibility, ownership facts and public changes retain conservative invalidation                                                                                                   |
| 9   | Native `module abstraction allocation failure releases every unpublished compiled owner`, forged-interface and publication-OOM laws; storage candidate OOM sweeps and failed-edit/checkpoint guest controls                       | No last-good owner or output mutation on rejection or allocation failure                                                                                                                    |
| 10  | `opaque_wrapper_operations.test.ts`, U32/F32 in both tiers: exact exported signature/body bytes, absence of a memory section, quiet NaN payload bits, signed zero and infinities                                                  | Focused operation and no-heap checks pass                                                                                                                                                   |
| 11  | The same guest file's reference/generic-record allocation laws, including aliases, COW and captured/returned values; five operation benchmark pairs                                                                               | Focused actual allocation/ownership traffic matches the plain programs                                                                                                                      |
| 12  | `scripts/qualify_wrapper_contexts.ts`: four representations × two tiers × plain/opaque × source/archive × initial/edit/revert, with fresh bytes, checkpoint restart, captures, aliases, traps and effects                         | All 96 rows pass exact exported and private function signatures/bodies, non-custom executable sections and allocation comparisons                                                           |
| 13  | Original module abstraction ABI validation, forged recipe and bounded-emission laws; unknown-recipe comparison control; nested literal-pattern guard guest law                                                                    | Unsupported or refutable cases retain ordinary checking, emission or rejection                                                                                                              |

The exact continuation law names make the mapping above reproducible:

- Rows 3, 4, 8 and 9, in
  [binding correspondence](src/reuse/frontend_binding_relocation.zig),
  [graph correspondence](src/reuse/frontend_graph_correspondence.zig) and
  [reference relocation](src/reuse/frontend_reference_relocation.zig):
  `frontend relocation public slot maps own private insertion and reject changed contracts through OOM`,
  `frontend relocation principal correspondence owns injective sharing and budget declines`,
  `frontend relocation typed references preserve nominal and local IDs and preflight incomplete maps`
  and
  `frontend relocation forwarded public catalog positions require a complete producer map`.
- Rows 3 and 4, in [module frontend laws](src/reuse/module_frontend_tests.zig):
  `module interface cutoff relocates owned caller references after private binding insertion and movement through OOM`,
  `module interface cutoff preserves generic parameter alpha correspondence through OOM`
  and
  `module interface cutoff preserves public effect parameter alpha through OOM`.
- Rows 3, 4, 8 and 9 additionally cover
  `module interface cutoff preserves public contract recipes and forwarded catalogs through OOM`,
  `module interface cutoff preserves public associated relationships and original targets through OOM`
  and
  `module interface cutoff preserves bounded implementation catalogs selected callers and original producers through OOM`.
  [Method source laws](src/reuse/frontend_method_sources.zig) require complete
  original public roles, private method names and bounded source context;
  [graph laws](src/reuse/frontend_graph_correspondence.zig) preserve symbolic
  associated producers, members, arguments and arity. The both-tier guests are
  [public contracts](tests/opaque_public_contract_cutoff_execution.test.ts),
  [associated getters](tests/opaque_associated_cutoff_execution.test.ts) and
  [implementation catalogs](tests/opaque_implementation_cutoff_execution.test.ts).
- Rows 3, 8, 9 and 13 include
  `package symbolic nominal getters retain exact public member authority and reject payload guesses through OOM`
  in [package laws](src/check/package_contracts_tests.zig). Associated getter
  guests exercise the same package proof through archives, restart, failed
  privacy edits and last-good recovery.
- Rows 5–9, in that same file:
  `opaque storage changes retain semantic callers and rebuild current executable layouts through OOM`,
  `opaque derived storage producers refresh their recipes while semantic callers reuse through OOM`,
  `opaque semantic comparison preserves identities visibility contracts and unknown-storage declines`,
  `derived opaque recipe validation rejects circular foreign role assertions`,
  `derived opaque recipe validation uses the original producer` and
  `derived opaque recipe validation resolves producer parameter selectors`.
- Rows 10–12, in [numeric proof laws](src/check/core_proof_tests.zig):
  `numeric proof preserves exact collection identity through opaque reference adapters`.
  The executed wrapper file separately retains the refutable-pattern control for
  row 13 in both tiers.

### Allocation observations

`scripts/bench/guest_heap_observer.ts` adds private telemetry exports only;
function bodies, data and ownership metadata retain their bytes. The original
Guest path and a raw original-module control execute too. Every measured raw
call opens and closes the ordinary ownership scope and checks zero roots and
leases after leaving it. Actual private memory pages stay flat after warmup. The
public scalar Guest API can hide that memory and return zero from
`memoryBytes()`; that value is recorded separately and makes no heap-absence
claim. The tiny scalar identity law instead proves no Wasm memory section
exists.

The existing Arena counter measures rounded size-class allocation bytes,
including recycled blocks. It is not requested payload or live bytes. Retain,
release and destruction deltas are recorded separately. Compiler requested,
peak-live and final-live allocation stay in the compiler metric records.

The earlier development-compiler matrix in
`build/bench/task053-wrapper-contexts-all-functions/results.json` has SHA-256
`e30afb6f182617cb5e92978691515d9f362bc046242b1d74900d7a8c82f74b2a` and compiler
SHA-256 `929417b12f6be0f6180fcd056faee5cd294f8ab05a76a268a686d55e785ca813`.
Every row measures 500 warmed calls across `run`, `captured`, `identity`, `trap`
and `effects`, including 100 expected traps and ordered host callbacks. All 96
rows pass; plain and opaque traffic agrees for all 48 pairs:

| Representation/tier         | Rounded allocation bytes | Retains/releases/destroyed | Committed memory bytes |
| --------------------------- | -----------------------: | -------------------------: | ---------------------: |
| U32, both                   |                    9,600 |              0 / 200 / 200 |                131,072 |
| F32, both                   |                   14,400 |            100 / 400 / 300 |                131,072 |
| Reference, both             |                   48,000 |        300 / 1,300 / 1,000 |                131,072 |
| Generic record, development |                   72,000 |        800 / 2,300 / 1,500 |                131,072 |
| Generic record, optimized   |                   52,800 |        600 / 1,700 / 1,100 |                131,072 |

The subsequent release matrix in
`build/bench/task053-wrapper-contexts-release-final/results.json` reproduces all
96 comparisons at compiler SHA-256 `8a8cfb7c…`. Its five operation pairs also
have identical non-custom executable sections and allocation/ownership traffic.
The compile benchmark for that source was intentionally stopped when the new
artifact control failed; `task053-compile-before-cycle-diagnostic` contains
partial samples, not a CPU guard or strict-parity qualification.

These modules intentionally include arrays, captures and host capabilities;
their heap is the program's ordinary storage. The separate five-case operation
benchmark also shows matching allocation and ownership traffic, including zero
heap for the scalar sum and scalar identities. Fifteen alternating CPU pairs are
diagnostic until rerun on the current qualified release.

The first scalar control failed exact body equality because a stored reader call
remained. The first reference controls had extra retain/release operations.
After bounded inlining, an optimized generic record still allocated one extra
48-byte block per invocation because opaque binding introduced redundant failure
control. The irrefutable-pattern change removes that allocation; its negative
literal-pattern test retains the failure branch. The expanded host-call control
then exposed an extra 48-byte scalar callback descriptor. Aliasing the validated
unpack-only adapter prefix removes its redundant control and copies, allowing
the existing callback no-escape proof to succeed. The callback safety proof is
unchanged. Numeric operand preservation removes the remaining proven-singleton
bounds branch in the reference identity operation.

An export-only comparison initially missed extra aliases and a return block in
the private generic reader. The stronger guest control rejects both tiers at
compiler SHA-256
`f1114ef229fe4fe3fe268063ef39cd9f6d45540c6f4b63e2f88f086c72146d1f`. The adapter
proof now reads the prepared structural record and its single ordinary field
plan. Nominal or ambiguous projections retain normal emission.

The final development matrix compares exact signatures and body bytes for all
five exports and every private function. All 96 rows also match every non-custom
Wasm section. The earlier failed probes and the separate 300-call matrix remain
preserved under their original hashes. The 14 focused wrapper/storage guest laws
and the new numeric-identity native law pass on the current development
compiler. The integrated relocation/effect continuation passes four helper laws,
three native/OOM integration laws and four guest tests across both tiers. It
checks 48 retained states across source/archive, private insertions/movement,
generic and effect alpha changes, with fresh bytes, failed edits and checkpoint
restarts (19,200 checked guest calls). The preceding compiler passes both
effect-alpha tests but fails both extended insertion tests at
`insert_effect: module reuse` (0 instead of 1); the new source passes all four.
The replacement complete gate above now passes this continuation. Its pinned
compile/CPU qualification below now passes too; the public-contract case remains
open.

### Remaining public-contract cutoff, 20 October 2026

An additional row-3 control keeps an unused public
`type Public a is contract = {type_rep a}` unchanged before the private
insertion and opaque producer. With that declaration, the `3f9c9275…` compiler
rechecks both semantic callers; without it, both callers reuse. Each case
matches fresh bytes and executes three boundary values correctly. This is a
remaining cutoff gap, and task 053 remains open.

| Producer catalog                        | Intermediate / entry reuse | Fresh bytes / executed witnesses |
| --------------------------------------- | -------------------------: | -------------------------------- |
| Opaque producer without public contract |                      1 / 1 | Same / 3 pass                    |
| Same, with unchanged public contract    |                      0 / 0 | Same / 3 pass                    |

The source-only optimized screen uses one codegen worker and persistence
disabled. Results are
`build/bench/task053-final-20oct-public-catalog-screen/results.json`, SHA-256
`fabadd43c555b87c5a61872eee3bcaf58ec310ec06a0f278c4c3c6160ddb1695`. An isolated
prototype is adding complete public contract recipes and owned catalog maps; it
is not integrated or qualified by the current gate.

### Public-contract follow-up, focused qualification

The local `709237c` milestone and separate `ed3b0af` hash record preserve the
qualified source above. A later continuation fixes the catalog screen in an
isolated source copy and integrates only the reviewed files after focused
checks. The complete gate and exact release wrapper comparisons now pass this
continuation; the remaining CPU and compile-parity status is recorded below.

The correspondence owns injective public-contract catalog maps, including valid
catalog slot zero. It compares every public header, parameter/pattern graph, row
parameter, predicate and member recipe; private slots must remain redacted. The
same exact graph comparison admits source-position changes for authored
qualifications in matched public schemes and contracts. It retains an owned,
unambiguous old/new span map under the original unit and rewrites only
unpublished principal/Core copies. Nameless shared schemes retain exact original
public producer targets, and callee requirements use the complete public binding
map; private/formal targets decline. Selected implementations,
generative/rank/usage authority and unsupported graphs retain ordinary checking.

Eight helper laws pass, including complete allocation-failure sweeps, changed
predicate graphs at identical raw type IDs, ambiguous span mapping, changed
origin units, omitted origins, owned-copy isolation and typed catalog rewrites.
The native integration law sweeps every allocation failure over private binding
insertion, private contract insertion shifting public catalog positions, public
parameter alpha changes and reverts, with both used and unused contracts.

The four new guest laws cover both codegen tiers, source and archived
dependencies, forwarded contracts, fresh bytes, failed-edit rollback and
checkpoint restart. They execute 16,000 boundary-value calls. A valid changed
public predicate forces both semantic callers to recheck and still matches fresh
bytes. The earlier wrapper, storage, derived-recipe and relocation guest groups
also pass on the prototype. No release CPU or full-gate result is inferred from
these focused runs.

The expanded allocation campaign on the integrated source passes 108
observations (54 fresh/retained pairs), including used and unused public
contracts in both tiers. All eight Session groups end at zero requested live
bytes. In optimized mode, private binding insertion beside an unused contract
uses 750,398 requested bytes retained versus 796,461 fresh (four versus seven
elaborations); the used-contract case uses 800,967 versus 874,137 (five versus
eight). Peaks are higher while both accepted and candidate owners are live. This
uses the same SMP-backed Session meter and exclusions as the earlier campaign,
with one worker and persistence disabled; it is not a release CPU measurement.
The report is `build/bench/task053-public-contract-allocation/results.json`,
SHA-256 `e277d4194786c306f6abab82274fc5399d849c5c31638adc43da3432cfe253e4`.

### Integrated public-contract qualification, 20 October 2026

The forced full gate `run-accd6926af4e4b24` passes **2,489 native laws executed,
1,578 guest/client checks and 37 harness checks**. Native shards execute 1,244
and 1,245 laws with zero skips, failures, leaks or logged errors. The gate wall
time is 4613.843 seconds. Both analyzers and the uncached local source/fixture
checks retain zero findings across 510 source files and the fixture module. The
frozen inventory contains 1,161 source, test and configuration inputs;
documentation edits are outside that inventory.

- Release SHA-256:
  `832ea709cab85446a54af9e0ffa6b326bbe19cdd6503e448d758c9994183dadd` (67,652,576
  bytes).
- Native executable SHA-256:
  `6143505f96cf19c4b386542d04d87e71179887c5e50ef2a43ab4015f5ce2134d`.
- Native source digest:
  `4311ab23232f4dac1e7fcbf8b5792c574e5066699706c6cae932ca990d976523`.
- Timing report SHA-256:
  `721f54d5c02b021c7a6ad93b3b65fd45aab18d48cbda2df01b357b05a5c60f14`.
- Frozen-input manifest SHA-256:
  `839f36a62f91356c671f112c1cb761d16005f15b91e332e517152fb02cef4bf0`.

The immutable release in `build/bench/task053-public-contract-release/` passes
all 96 wrapper contexts and five operation pairs, including exact private and
exported signatures/bodies, non-custom executable sections and measured
allocation/ownership traffic. Their result SHA-256 values are
`ea59b0bc271ed12ae8db723dc52d5c4ced362ecafd1039039f308e84e4a88d6d` and
`db5c6edc096e1839773d30ed6129f5e3746eb59393064681a2c03fc582fd890e`. Runtime
timing noise on identical code establishes no speedup.

The first seven-pair fresh game CPU guard against the preceding `3f9c9275…`
release fails: paired median 1.18684, limit 1.05, with individual ratios
1.012–2.471 on CPU 0. Fresh Wasm is identical. This failure is preserved in
`build/bench/task053-public-contract-cpu-guard/results.json`; it is not waived.
The independently pinned seven-pair identity control on CPU 2 passes with paired
median 0.98342 (individual ratios 0.901–1.517). The preselected expanded 15-pair
comparison on that same CPU also passes the unchanged 1.05 guard, with paired
median 1.02124 (range 0.847–1.460). Both disable persistence and use one codegen
worker; all fresh Wasm and deterministic work counters agree. The wide identity
spread and the preserved first failure limit the inference: the expanded
regression guard passes, with no speedup claim. Identity and expanded report
SHA-256 values are
`8058b494d40c93eb2d59f4264064599eaf518281bc8487695d393ed3dd7fedc3` and
`bdb7971564b6290f9870238b0b5ffa5ec10a6c8f65d7320bb6c164291f568d68`.

Strict fresh/retained/edit/revert/restart/shared parity passes all 162 measured
samples and the separate fresh-edited controls in three paired rounds. It uses
the same frozen 583-file snapshot, one worker and restart persistence where
requested, with no output waiver or hash writes. The report is
`build/bench/task053-public-contract-parity/results.json`, SHA-256
`2f804424ec53b06dec85c0828b6ee88e037442c00866b0a76a5f239839ae8c35`. The
unchanged protocol rejection remains expected; these counts are compiler and
parity observations, not executed gdev tests. All 1,161 frozen source, test and
configuration inputs remain exact. This qualifies the public-contract follow-up;
task 053 remains open for the cases below.

### Next fixed-scope controls, 20 October 2026

The bounded mixed implementation and selected-name form already covered by task
024 still blocks row 3. With a private insertion immediately before the opaque
type, both an unused public implementation and one used by the observer recheck
both callers (0/0 reuse), including revert. All four states preserve fresh Wasm
and twelve executed boundary witnesses. The exact compiler is `832ea709…`;
`build/bench/task053-fixed-catalog-screen/results.json` pins the harness and
source hashes. Its isolated correspondence prototype is unqualified.

The associated-method control fails during its initial build with
`InvalidArtifact`, before any edit or reuse observation. An explicit method
signature produces the same failure; the preceding `3f9c9275…` release also
fails the original inferred-signature probe. The sources and logs remain in
ignored `build/bench/task053-associated-cutoff-screen/`,
`build/bench/task053-associated-annotated-cutoff-screen/` and
`build/bench/task053-associated-inferred-baseline/`. This is an existing
artifact-publication issue to diagnose; no passing associated cutoff or
prototype execution is claimed.

### Bounded public catalogs and getter metadata, focused continuation

The counterexamples above describe the qualified `04e41ef` baseline. The next
continuation now integrates the reviewed isolated fix. Public implementation
catalog positions, including zero, have owned injective maps. Matching compares
original identities, visibility, contract heads, parameters, predicates, member
signatures and templates. Symbolic associated type projections compare exact
original contract/member identities, arity and argument graphs with injective
variable sharing; no selected implementation proof is inferred.

A public member's hidden method slot additionally requires its complete old Core
and current Checked owners. Ephemeral callbacks validate the original
implementation/member role and the current generated private name, then compare
flow, positional capability parameters and exact capability-recipe graphs.
Absent context, another producer/name or changed capability facts decline. No
source borrow enters a returned map, and no private binding is unredacted in a
public artifact. Implementation-origin spans relocate only in unpublished
copies, just like matched authored qualification origins. Ordinary diagnostic
spans remain separate. The 64-catalog/4,096-work bounds and ordinary-checking
limits for unsupported row catalogs, rank/usage/generative forms and selected
proof payloads remain.

The initial getter failure came from a symbolic associated access retaining a
physical nominal projection marker in an intermediate module. The checker now
keeps its original receiver identity in the source type and clears only that
physical marker when selecting the method. The existing artifact validator still
rejects foreign opaque payload access. The new native/OOM and both-tier guest
laws pass this repair with source/archive/checkpoint/failed-edit controls; the
three existing import/privacy guest laws also pass.

The combined focused campaign passes thirteen helper laws and six integration
laws, including complete allocation-failure sweeps. Ten guest groups check
43,200 calls across source and archived dependencies, edits, reverts and
restart; 27,200 calls belong to the new associated/implementation groups.
Private binding/type/catalog insertion, alpha changes and same-interface
method-body edits reuse both semantic callers and match fresh bytes. Changed
implementation heads, associated types, losing candidates, visibility and public
method signatures force rechecking and preserve fresh results or diagnostics.
Both analyzers report zero findings over all 511 source files and the fixture
module.

The isolated development compiler is
`98f059e303acf91f31c676a427155980343ea8f9d9b8fcf9edf5ab2e11b98d68`; its focus
log SHA-256 is
`fd0acc2e259e28162ebbce4e9743a0de63ce8a69e99d32dff3bb4a7178cdb41c`. The
implementation is now in the working tree. The forced complete LLVM gate
`run-618a85eed20faf7f` built both LLVM binaries, then passed 2,495 of 2,496
native laws with zero skips, leaks or logged errors. The package
mixed-composition law failed with `InvalidArtifact`: its lexical validator still
classified a zero-nominal getter as an abstract field goal. GDB confirms that
path, while the same isolated law passes on the preceding qualified compiler.
The failed run's 1,165-input manifest is
`0920ce42eb5855cd623ffe217eda125c0576dadd0559cbf9ed71e196016b845c`; its compiler
is `4cdfba0f2abeb6fba40416fe42bbfb64491eef334ba141511196bcfa41cc31a3`.

The targeted repair reconstructs a symbolic getter's nominal receiver from its
checked source type and invokes the existing exact member and scheme proof. It
keeps explicit identity mismatches and physical projection rules unchanged. All
78 focused package laws pass, including the original regression, explicit legacy
receiver metadata, wrong-member/receiver and payload-guess controls with
complete OOM and immutable-Core checks. Eighteen guest groups pass, including a
new opaque-getter/package case through both-tier source/archive, checkpoint
restart and failed privacy edits (800 executed calls). The focused compiler is
`3902038f6b01576b82ec146c5f54f016fdcdde445a0fdf69bd5837261865f955`; source and
log pins are in `build/bench/task053-package-focused/pins.json`.

The replacement full gate `run-94ee2a5814168d09` passes **2,497 executed native
laws, 1,585 guest/client checks and 37 harness checks** on 1,165 frozen inputs,
manifest `73ddc05986cd4e765296e0cea9cc049b7bec973ab87242a49edd0e4a16b673e7`.
Native laws have zero skips, failures, leaks or logged errors; both LLVM builds
and the native execution are cache misses. Wall time is 4,993.391 s. The release
is `1b05518e501b001a972a1815379aa433d697807a6084da3358a3464dd342d294`
(67,705,424 bytes); the native executable is
`6bcc0c1680a61f3c99df3f6f5e02b2a57c8b26e8beb38ea8a61bb24a7d55bfe8`. The timing
report has SHA-256
`1f1b3125fce13aa1afaba35f467ab290ba00470df690561af208b4e693a1a1f1`. Its
replacement allocation campaign passes all 176 observations/88 pairs and
fourteen zero-live Session teardowns; every Wasm hash and work counter matches
the preceding campaign. The new report is
`build/bench/task053-catalog-package-allocation/results.json`, SHA-256
`2cfee1fbc5530ab601622e802c082f6770f4b1fb92496e43b8522bcf380db58c`.

The repaired release also passes all 96 exact wrapper contexts and five
operation comparisons. Reports are
`build/bench/task053-catalog-package-wrapper-contexts/results.json`, SHA-256
`d3ef4ab558779410ad5880ed1b29885b5f30562d67a75affc6f79727b8257d9d`, and
`build/bench/task053-catalog-package-wrapper-pairs/results.json`, SHA-256
`f5f77e917ae4e96de3adfb8a436ce1974dac5e1c4f5216dfa01d553c3d2e00fd`. The
preselected CPU identity/candidate comparisons and strict gdev parity campaign
also pass; their distributions and exact report pins are in the final task 053
qualification below.

The failed gate and immutable binaries remain under
`build/bench/task053-catalog-pre-package-fix/`. Its guest, pack and final
release wrapper/CPU/gdev stages did not run. That failure remains separate from
the passing repaired full gate, wrapper campaign and final CPU/gdev
qualification.

### Expanded Session allocation observations

The integrated standalone campaign passes 176 observations/88 fresh-retained
pairs across both tiers, including associated methods and used/unused public
implementations. Every pair has the same Wasm hash; all fourteen Session groups
end at zero requested live bytes. Edited states reuse both semantic callers. The
SMP-backed meter, empty-seed baseline and exclusions remain as recorded below;
this safe/no-LLVM campaign makes no release CPU claim. Executed values are
covered by the guest laws above.

| Optimized edit                 | Fallback elaborations fresh / retained | Requested bytes fresh / retained | Peak live bytes fresh / retained |
| ------------------------------ | -------------------------------------: | -------------------------------: | -------------------------------: |
| Associated private insertion   |                                  8 / 4 |                818,285 / 757,980 |                437,624 / 805,792 |
| Unused implementation catalogs |                                  7 / 4 |                921,848 / 854,038 |                432,298 / 804,321 |
| Used implementation insertion  |                                  8 / 5 |                960,794 / 892,830 |                443,380 / 815,702 |
| Selected private method body   |                                  7 / 4 |                954,699 / 888,352 |                442,917 / 812,498 |

These rows additionally take one fresh entry elaboration and zero retained entry
elaborations. Retained publication keeps the accepted owner alive while building
its candidate, accounting for the higher peak. The complete report, with source,
benchmark/options and executable hashes, is
`build/bench/task053-catalog-package-allocation/results.json`, SHA-256
`2cfee1fbc5530ab601622e802c082f6770f4b1fb92496e43b8522bcf380db58c`. The
preceding campaign remains in
`build/bench/task053-catalog-allocation/results.json`, SHA-256
`82cb36687e2ffd7fe5d8e3a6c7b8705e27fa8798ea58ff04cc6a0d57bf0b75d7`. Every Wasm
hash and work counter agrees; requested-byte equality is not assumed for other
observations.

### Preceding release erasure screen, 20 October 2026

The new release has SHA-256
`3f9c9275221aa8d1e8a725e97d9b17a673b9bc7e22bf09978ad346ae4af8e45f` and
67,531,544 bytes. The full gate above qualifies this exact compiler source. Its
96 context rows pass exact exported and private function signatures/bodies, all
non-custom executable sections and allocation/ownership traffic. Results are
`build/bench/task053-final-20oct-wrapper-contexts/results.json`, SHA-256
`bf84fac445c973afe70297338358ab66313f68509a99e67e8b1fbd17b52ad868`.

All five operation pairs also match executable sections and allocation traffic
over 15 alternating pairs. Results are
`build/bench/task053-final-20oct-wrapper-pairs/results.json`, SHA-256
`ff08a41a3c1538c6e1e2726e473c7e98d2bdec840a7ebd2bcdc4842e62735db2`. Their CPU
distributions do not establish a runtime gain. The separate pinned gdev compile
comparison passes all within-compiler parity checks in three paired rounds. The
paired median is 0.9786 against the 1.05 limit, with ratios 0.801–1.617; no
speedup is claimed. The one-worker fresh comparison disables persistence. Guard
results are `build/bench/task053-final-20oct-cpu-guard/results.json`, SHA-256
`db6607cf151dccf017d7aeebdfca988dfef2a35a009aad5934f753f41aa750c9`.

The strict fresh/restart diagnostic records only the intended cross-compiler and
recorded-hash differences for six successful entries; same-compiler restart
bytes agree. The protocol test retains its recorded `non_exhaustive_match`
rejection. Diagnostic results are
`build/bench/task053-final-20oct-output-diagnostic/results.json`, SHA-256
`096788038fa1f32869278ccf31e2c4fb847a1d1e595cf659c0092578115f72ce`.

Reversing only the new irrefutable-pattern fast path in an isolated source copy
restores every selected workload's original baseline bytes. This includes the
game and slow tests whose function counts change downstream. The control has
zero verification problems and matches the recorded hashes. Its native
development build is a causal output control, not CPU evidence. The control
compiler is `5296c7a1a53242093e9b4ec3cc257cb97a809fbe04862b4305e192ab86ded86a`;
results are `build/bench/task053-final-20oct-irrefutable-control/results.json`,
SHA-256 `93c7be88e5910dbd37b8390ed690ef51250f8a1794640d987c2fb40731849f54`.

The final compile campaign records 162 timed samples across three game/devtools
pairs and one pair of five selected slow tests, including a shared test session.
Fresh, retained population, no-op, edit, revert, restart and shared output agree
within each compiler. Each game edit also agrees with a fresh build of that
edited source. There are zero unexpected verification problems; the protocol
rejection remains expected. Persistence is enabled for this parity/restart run
and disabled for the separate seven-pair CPU guard above.

Results are `build/bench/task053-final-20oct-parity/results.json`, SHA-256
`6d921e80862afb8439dc4505917f7b35d78b8d2e4b2481ff53dd722970ac4a1f`. The 583-file
snapshot and manifest remain unchanged. The campaign measures 14 recorded
entries (including seven game edits), revises 13 Wasm hashes and keeps the
protocol failure hash. The other 64 recorded entries were not remeasured in this
slice. The hash record has SHA-256
`e449761d69e2fa61c92f9cd51f03268cb2c3787bd9de2fafa7cd0149c121d6f3` and is saved
in its own commit. These are successful compiler invocations and parity checks;
no executed-gdev-test count or whole-program completion is claimed.

### Session allocation observations, 20 October 2026

The standalone `zig-native/bench_module_cutoffs.zig` campaign records 68
observations (34 fresh/retained pairs) over scalar storage, private
binding/type/ effect/contract insertion, movement, value/type/scheme alpha, body
edits, reference and record storage, field renaming and reverts in both tiers.
Every pair has the same Wasm hash, and all four Session groups end at zero
requested live bytes. The full row records include entry-only and total work
separately.

These are safe-mode, self-hosted native measurements with production SMP
backing, one codegen worker, artifact replay enabled and persistence disabled.
Per-revision requests start after the empty 16-byte seed. Peak live bytes
include the old accepted owners and the unpublished candidate; retained
post-result storage is released at Session teardown. Harness/output IO,
allocator capacity and process RSS are outside this meter. This campaign makes
no release CPU claim.

| Optimized case            | Elaborations fresh / retained | Requested bytes fresh / retained | Peak live bytes fresh / retained |
| ------------------------- | ----------------------------: | -------------------------------: | -------------------------------: |
| Private binding inserted  |                         7 / 4 |                779,516 / 736,166 |                427,104 / 793,438 |
| Private effect inserted   |                         6 / 3 |                781,663 / 700,950 |                426,945 / 778,783 |
| Private contract inserted |                         6 / 3 |                783,936 / 707,525 |                426,971 / 778,885 |
| U32 storage → F32         |                         6 / 3 |                784,525 / 710,037 |                427,335 / 790,646 |
| Record field renamed      |                         6 / 3 |                968,345 / 872,601 |              568,908 / 1,054,080 |
| Generic type alpha        |                         7 / 4 |                863,159 / 740,062 |                447,099 / 799,511 |
| Generic scheme alpha      |                         7 / 4 |                865,444 / 760,953 |                447,188 / 799,240 |

Raw records, executable/harness/source pins and the measurement scope are in
`build/bench/task053-cutoff-allocation/results.json`, SHA-256
`072adb8cb652bae0b00a84feb4a2999c0abcb2928703fdafe6592e4e7e22d881`. The higher
retained peak is recorded rather than presented as a memory saving.

### Final task 053 qualification, 20 October 2026

The repaired continuation completes fixed acceptance rows 1–13. The row-to-law
map above includes public-contract, associated-method, implementation/member and
symbolic-getter package controls. Unsupported or exhausted proofs keep the
ordinary checking limits already recorded by task 024; original producer,
nominal identity, visibility, capability and executable dependency checks
remain.

The full LLVM gate `run-94ee2a5814168d09` passes **2,497 executed native laws,
1,585 guest/client checks and 37 harness checks**, with zero native skips,
failures, leaks or logged errors. Zig is 0.17.0. Both release/native compilation
and native execution are cache misses. Wall time is 4,993.391 s. Immutable
executables are in `build/bench/task053-catalog-package-release/`:

- Release: `1b05518e501b001a972a1815379aa433d697807a6084da3358a3464dd342d294`
  (67,705,424 bytes).
- Native suite:
  `6bcc0c1680a61f3c99df3f6f5e02b2a57c8b26e8beb38ea8a61bb24a7d55bfe8`.
- Timing report:
  `1f1b3125fce13aa1afaba35f467ab290ba00470df690561af208b4e693a1a1f1`.
- Frozen 1,165-input manifest:
  `73ddc05986cd4e765296e0cea9cc049b7bec973ab87242a49edd0e4a16b673e7`.

Both CI-pinned and local analyzers report zero findings over 511 source files
and the fixture. The local uncached source, fixture and benchmark checks also
pass. All 96 wrapper contexts and five operation comparisons match exact
executable sections and allocation/ownership traffic; their report pins are
recorded in the repaired-source section above.

The preselected CPU-2 controls use one codegen worker and disable persistence.
Seven identity pairs of the preceding qualified release have paired median
0.923863, range 0.648149–1.556488. The 15 candidate pairs against `832ea709…`
pass the 1.05 regression limit: paired median 0.998133, range 0.493901–1.248983.
The distributions are broad; no speedup is claimed. Reports:

- `build/bench/task053-catalog-package-cpu-identity/results.json`, SHA-256
  `fe8a268bd71a9db820e457f1a6b8e70e5304d59de570d91757d86b3f5992a3a0`.
- `build/bench/task053-catalog-package-cpu-guard/results.json`, SHA-256
  `ffa7da3349ec7cab65a56788c336df8321212dd4272d6bf45f5c16d59ac88b10`.

All 162 strict compile samples and 14 fresh-edited controls pass without output
waivers or hash writes. This covers three paired game/devtools rounds, five
selected test entries, fresh/retained edits and reverts, restart and shared
sessions. The 583-file workload manifest and recorded Wasm hashes match. The
protocol entry retains its expected `non_exhaustive_match` rejection; this
compilation campaign does not claim executed game tests. Report
`build/bench/task053-catalog-package-parity/results.json`, SHA-256
`53e68cf1920eeed90ed326b13475fdccb09b33b0350d4a115d96484dc5cbc444`.

The repaired allocation campaign records 176 observations/88 fresh-retained
pairs with exact Wasm and unchanged work against the preceding campaign. All
fourteen Session groups end at zero requested live bytes. Its safe/no-LLVM,
SMP-backed requested-byte scope, 16-byte empty seed, retained publication peaks
and exclusions are recorded above; it is separate from release CPU and guest
allocation traffic. Report
`build/bench/task053-catalog-package-allocation/results.json`, SHA-256
`2cfee1fbc5530ab601622e802c082f6770f4b1fb92496e43b8522bcf380db58c`.

The earlier failed package-getter gate and noisy CPU screens remain historical
evidence. They are not substituted for the repaired source's complete results.
