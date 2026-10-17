# Continue here

Finish the entire program in [tasks/README.md](tasks/README.md), continuing past
individual milestones. Commit or push only with the owner's approval. As of 17
October 2026 there are 80 complete tasks (including four designs), 21 in
progress and 8 pending: **29 remain open**; see the counts in
[tasks/README.md](tasks/README.md). Keep this handoff until every required task
verifies.

## Owner decisions — 15 October 2026, evening

- Language tasks 058/059/061/062/064/065 close against the fixed rows of
  `zig-native/LANGUAGE_QUALIFICATION.md`; 067/068 against the typed-staging
  acceptance traces; 073/074 against the structured-concurrency traces. Forms
  outside those lists reject or decline conservatively and are limitations, not
  open work. See each task's "Closed acceptance" section.
- The five final performance targets moved to new tasks 100–104; 084 re-pins a
  workload and records measurements.
- Task 035 is gated on running without crashes or memory exhaustion; the CPU
  comparison with tracing is informational only.
- Task 082 uses a local analyzer built from `../zig-analyzer` instead of a
  remote run; no push.
- Task 083 is complete. The owner removed `build/` (all `build/bench/...`
  evidence paths below are historical); every `.zig-cache` under
  `/var/tmp/blot2-*` (659 directories, 438 GB) was deleted with approval.
- The working tree first failed 20 of 2,354 native laws. Those failures and the
  guest regressions behind them were fixed on 16 October:
  - lazy demand types follow the callee parameter;
  - only a demand parameter declared affine before instantiation moves captured
    owners (`demand_once`), so retry demands keep rejecting them (owner accepted
    this rule on 17 October; recorded in `USAGE_CONTRACTS.md`);
  - public dependency freezes copy instance identities verbatim;
  - workspace goals also search active quantifier goals;
  - task call sites register pattern locals;
  - body-cache replay re-covers declared clauses (`covered_requirements`);
  - quoted named calls admit lift/splice arguments;
  - two stale laws were updated: the host-stub fixture and the hidden-payload
    staging law, now adversarial.

  `region_activation_execution` expects one fewer allocation per development
  cycle after task 047's scalar closure environments. The full gate then passed:
  2,354 native laws (zero leaks), 1,486 guest, 28 harness, 21 preflight and 48
  smoke tests, in 752 s. Lint (CI-pinned analyzer) reports zero findings over
  486 files.
- Four retained/reuse laws evaluate an infinite `read ()` recursion. They
  overflow the stack only in `-Dllvm=false` builds; the LLVM gate passes them.
- Task 075 no longer depends on 001–074 (owner-delegated decision, 16 October
  2026); open feature tasks build on the split evaluator structure.

## Active continuation after the qualified freeze

The qualified gate below predates the current continuation. It does not qualify
later 024/035/047, evaluator/Core/checker/backend owners, portable composition,
constant graph/query or source-layout changes. Their focused pins and failures
are retained under `build/bench/finish-rest-20261015/`. Current ordinary Cost is
12,878 bytes after the integrated scalar-environment candidate; the 11,958-byte
figure below belongs to its earlier frozen compiler.

Source files now live under
`zig-native/src/{parse,check,eval,backend,reuse,runtime}`. The full move map and
original before tree are retained in `source-areas/`. No source forwarding stubs
were added. Dev build succeeds; final common source, release/full compiler/CPU
gates and external/cleanup prerequisites remain open.

## Current qualification — 15 October

The final combined gate passes **2,223 native laws, 1,404 guest/client tests and
1,366 complete allocation-failure sweeps** plus two expected-error harness laws.
Both native shards report zero skips, failures, leaks and logged errors. All 455
Zig files have zero analyzer findings. Full gate: **697.812 s**. Tasks **070/071
are complete**; the remaining 27 tasks stay open.

Frozen source: `/var/tmp/blot2-final-proof-repaired-20261015/source`. Manifest
SHA-256 `3548546cb8660905de9a83922bab67270376a2b955f840f2bc7cf13fcefa53ec`; all
1,303 source and 41 external pins match after execution. Exact logs, inputs,
identities, qualified executable/bundle and post-run verification:
`build/bench/complete-program-20261015/final-proof-repaired-gate/`. Release and
decompressed bundle SHA-256
`6a83bad5560ec1a82220dc834dd366646fb8ab10370f82b26a2bcb775111ae6b`; packed
bundle SHA-256
`77ad409f11b952ba39fc3f752ceec30ffc1c762c95a76063ed4c2f77b75e1075`. Actual
handshakes agree with installed identities and fresh independent configure runs.
Task-status/documentation updates follow this verified freeze and have separate
hashes in `qualification-document-updates.json`.

The alias-before-first-proof regression and two obsolete aggregate cutoff
assertions are repaired. Their unchanged semantic controls and all allocation
sweeps pass in the complete run. Earlier failed gates and release inventories
remain preserved; none is relabeled as a full pass.

An earlier private ownership union/guard screen failed its compiler gate:
guard/control fresh 1.1143, retained 1.0103, geometric mean 1.0610 exceeds 1.05;
union 1.0664 also fails. It uses the earlier 2cbbc4c3… source freeze, before the
final alias repair. No later timing, runtime/release screen or promotion
follows. Evidence: `current035-screen/`. Task 035 and dependent 073/074 remain
open.

The captured project preserves all 415 input pins, exact fresh/edit/revert bytes
and 70,330 source steps. Its roughly 1.3 s retained edit is concurrent
compatibility evidence, not CPU qualification or the 100 ms goal. Ordinary Cost
stays byte-exact at 11,958 B. No remote workflow, deletion, commit or push is
performed.

## Prior qualified batch — 14 October

The uncommitted source based on `ef57ec5` passes the full compiler gate: **1,869
native laws, 1,170 guest/client tests, 1,133 complete allocation-failure sweeps
plus two expected-error harness laws**, and zero analyzer findings across 417
files. Both native shards report zero skips, failures, leaks and logged errors.
Full gate: **564.842 s**. No remote workflow has run.

- Frozen source: `/var/tmp/blot2-continuation-reuse-repaired-20261014`.
- Manifest:
  `build/bench/continuation-20261014/reuse-repaired-frozen-inputs.json`, SHA-256
  `1e6c2804d823e09ec96f2e75a0bd463e06d5c8280427665f7274c087e9e1d4cc`. All 1,177
  files and the file set matched after the gate. Subsequent implementation
  changes are being checked in small sets; they await the final full gate.
- LLVM/Fast executable and decompressed bundle SHA-256:
  `2693207b2dada8bd6305b510cab2efecb8ba524f429711854e64293760be6666`.
- Server handshake and independent clean configure identity:
  `a953759fdac4d10db77c5f4f55bc9820a16f43e07daea831a78dabcf0f60964c`.
- Exact pins, phase logs, counts and measurements:
  `build/bench/continuation-20261014/reuse-repaired-qualified-pins.json`.
  [Durable qualification](zig-native/CONTINUATION_QUALIFICATION.md#qualified-continuation-14-october-2026)
  records the admitted behavior and failed attempts separately.
- Preserve unrelated `deno.lock`, SHA-256
  `9ca792a967d134b10168500f68a576a67008431574b7007e14978d22d7e4e781`.

Three alternating captured-project release pairs against qualified `0d77afc`
(`b4fb67c…`) finish in 26.217 s. Fresh/edit/revert paired CPU ratios are
**0.9990 / 0.9178 / 0.9117**. Each compiler uses its own pinned standard
library. Within each side, fresh/retained/repeated Wasm and source work agree;
cross-compiler Wasm differs. Source work is 70,330 and constant receipt activity
is zero. This bounded screen does not complete tasks 084/093.

The batch integrates production ownership/scalar publication, generalized-local
storage and constructor forwarding; single-leaf List traversal; exact capability
flows, lexical loans and scalar resource cleanup; package carriers and numeric
proofs; owned typed staging with bounded named calls; and implementation-module
body reuse. Static captures now reuse executable code through the existing owned
graph importer. Promoted local initializers still require exact wrapper reads
and fresh code. Annotation-only body reads use existing nominal/alias recipes;
explicit selected-call proofs remain fresh. The original reuse guest assertions
are preserved.

## Active continuation after the qualified freeze

The user again requests **all remaining tasks**, continuing through milestones.
Use focused batches and reserve the full gate for the final combined source. No
additional task is marked complete by the focused slices below.

- Current Root integrates 075 evaluator owners, 076 Core model/builder, 024
  general checked-fragment owners and 077 checker responsibilities. Their exact
  partial source/executable freezes and focused validation are under
  `build/bench/finish-rest-20261015/{evaluator-owners,core-owner-integration,body-owner-integration,checker-owners}/`.
  Read `zig-native/{EVALUATOR,CORE,CHECKER}_OWNERSHIP.md` for actual boundaries.
  The current Cost fixture is 12902B; the 11958B statements below belong to the
  older qualified freeze. Final common full/compiler/runtime performance gates,
  mixed portable composition and broad language closure remain required.

- Root integrated fresh compile-time capability identities and exact provider/
  request witnesses. Two native/full-OOM laws, four staged control guest groups
  (source/archive/checkpoint, edits/recovery, both tiers and sync/JSPI), and 263
  selected analyzer files pass. Quoted loop carries, mutable merges and fresh
  scopes/providers pass 47 native laws plus five effect guest groups and 262
  selected analyzer files. The subsequent uncalled-closure row repair passes 48
  native laws. This is not a new full gate.
- The language acceptance index maps thirteen normative rows for 058/059/061/
  062/064/065 to exact passing native names and guest JUnit records from the
  qualified baseline. Scope costs have seven compiler pairs, 31 warmed guest
  pairs per mode and separate population/edit/restart samples. See
  `zig-native/LANGUAGE_QUALIFICATION.md` and
  `build/bench/finish-rest-20261015/`.
- Follow-on row and named-provider principals pass 52 native staging laws,
  complete roundtrip/OOM, and six source/archive/checkpoint/restart guest
  recipes in both tiers and sync/JSPI. Future affine parameters raise the native
  count to 53, including a forged double move. Lexical loan callbacks raise it
  to 54; all 54 plus four ordinary usage controls pass (58 total). The affine
  guest transfers a unique result, consumes it once and rejects reuse in
  sync/JSPI. The generated callable keeps an explicit affine declaration; an
  unannotated unknown callable still reports `multiplicity_unknown` as required.
  Selected lint: 264 files, zero findings. `usage_core.zig` now has a separate
  future environment for quote. Earlier-stage affine moves within lift/splice
  are covered by the later stage-owner batch below; general captured loans
  remain outside the admitted staging frontier. Two independent loan emissions
  execute in sync/JSPI. Exact focused source and compiler pins are in
  `staging-completion/future-loan-union/`.
- Future resource scopes and acquire/release bodies now pass portable/OOM and
  actual Source/archive/edit/cache/checkpoint guest laws, including JSPI await,
  cleanup failure/recovery and bounded memory. Cleanup qualifiers and erased
  Foreign rows reject independently. There are now 55 portable staging laws;
  ordinary usage controls also pass. Imported opaque operations additionally
  pass consumer-side quotations. General captures and final qualification remain
  open.
- The combined stage-owner batch passes 60 portable staging laws, one operation
  header law, eleven task controls and one usage control (73 native total), 25
  guest groups and 413 selected analyzer files with zero findings. Direct
  request clauses retain their declared operation and separate computation/
  handler row owners, including unused handlers and actual Foreign callbacks.
  Earlier-stage affine operands of lift/splice keep their move owner through
  nested quotes and once generators. Qualified scalar constants retain usage
  evidence and decline constant receipts. Exact partial source and executable
  pins, logs and failed attempts: `staging-stage-owners/` and
  `staging-operation-headers/` under `build/bench/finish-rest-20261015/`. Named
  request/resolver helpers, general captures and final qualification remain
  open; these focused results close no task.
- Captured lexical read loans now reconstruct the actual local closure creation
  environment and physical capture catalog. Phantom, missing and escaping
  capture controls reject. The combined focused screen passes 74 native laws, 40
  guest groups and 420 selected analyzer files with zero findings;
  archive/restart and rejected escape edits execute both tiers and sync/JSPI.
  Named scalar/product cases additionally retain ordered coverage and arm
  binders through roundtrip/ OOM; six native and 36 combined guest laws pass.
  Exact partial pins and logs: `staging-captured-loans/` and
  `staging-data-cases/`. General captures, guarded pattern helpers and final
  qualification remain open.
- The reviewed ownership source integration removes production tracing helpers
  while retaining exact activation proofs, counted fallback, Task context fields
  and host cleanup. Its bounded private development screen passes compiler ratio
  1.0304, runtime median 1.0588 and every p95 (JSPI requests 1.1978). Review
  repaired temporary-artifact and relocated-fixture test plumbing without
  changing assertions. Root's combined dev build, three native/OOM and 36 guest
  controls pass; final common matched release measurement and full gate remain
  required. Evidence: `ownership-integration/`, `ownership-fixture-amendment/`
  and `/var/tmp/blot2-task035-result-slot-20261015/`.
- The evaluator owner split passes ten native/OOM laws, 25 guest groups, all
  native test-interface compilation and 422 selected analyzer files with zero
  findings. Evaluation/collection dispatch shrinks from 380/341 to 117/76 lines;
  Session fields are 113 → 87 with unchanged structure sizes. Ordinary bytes,
  full work/allocation counts and imported five-phase output/diagnostic/work/
  archive parity agree. Exact focused pins: `evaluator-owners/`. CPU and final
  common qualification remain pending.
- Task 079 relocates 126 Blot fixtures and two oracle files behind a test-only
  native module outside production `src/`; all 128 byte hashes are unchanged.
  Three relocated native consumers and seven analyzer dependency/cache laws
  pass. Guest readers and build/fingerprint/analyzer wiring are updated; final
  combined validation remains pending. Evidence: `fixture-relocation/`.
- The seven-file constant-query slice is integrated with exact matching before
  hashes. Ordered ordinary queries replace retained inference authority; 27
  native constant/enclosing laws and four query/callable guest groups pass. A
  reviewed six-file follow-up removes the obsolete member-event path (34 lines
  added, 241 removed). Root's eight original constant guest groups and four
  query/callable groups pass together (12 total). Evidence:
  `build/bench/finish-rest-20261015/{constant-query-integration,constant-member-removal}/`.
- Root's same-future-stage capture proof now passes its positive, phantom
  capture, malformed local owner, erased effect-view and full-OOM laws. It
  requires an actual capture edge in a complete scope lifetime report and
  lexical owner sites; earlier-stage captures still reject. Local closures
  retain their exact defining binding and ordinary covariant principal proof.
  All 50 portable staging native laws, ten staged/effect guest groups and 263
  selected analyzer files pass. This is focused evidence, not general staging
  completion or a new full gate. Logs: `staging-completion/` under
  `build/bench/finish-rest-20261015/`.
- Private ownership, retained-work and structured-task agents remain active. The
  ownership final matched-release measurements use frozen
  `/var/tmp/blot2-root-scope-union-20261015/source`, manifest `fc007399…`. It
  pins 1,304 source/document files plus one preserved untracked generated
  fixture. Later Root staging edits are outside that measurement freeze. The
  final matched release CPU geomean was 1.076653 (limit 1.05), so runtime
  qualification was skipped. The CPU 7 quiet window is released; the agent is
  subtracting runtime work after removing two graph passes and a redundant
  invocation frame. Its next compiler screen passes 1.017550; corrected warmed
  runtime median passes 1.089459 and seven of eight p95 limits pass. JSPI
  requests remains 1.218487 (limit 1.20). These are screens, not final release
  qualification. All failed rows remain preserved. Private task foundations and
  successful screens are not completed features.

## Next implementation

The owner's latest direction is to finish the remaining implementation using
small focused checks and run the full compiler gate only at the end. Continue
through individual milestones. Keep independent edits in private checkouts and
review exact deltas before integration. Freeze source for the final full gate.
For a focused native failure that reports only an error name, rerun that exact
filter once with `-Doptimize=debug -Dllvm=false` before instrumenting source.
Zig 0.17.0 Safe omitted the return trace in a local probe; Debug returned exact
source lines. Probe builds took 0.422/0.530s respectively; these are toy compile
measurements, not compiler-suite timings. Evidence:
`build/bench/complete-program-20261015/error-trace-screen/`.

Selected-body reuse, scoped invocations, portable structural packages and
compound constant replay are integrated. The scoped-owner validation repair
restores ordinary replay and captured-project fresh/edit/revert parity. The
current implementation awaits the single final full gate. The release executable
above is preserved in the pinned prior-release copy.

- **024 / 053:** Selected-name body reuse now owns the bounded complete semantic
  implementation catalog, including losing heads, member signatures and
  prerequisites; replay reconstructs current selected proofs and executable
  targets. Generic global/local callers, associated-result annotations,
  source/archive relocation and producer-body edits pass focused checks. The
  local generic associated-result specialization bug is repaired independently:
  projection arguments own lexical sharing, and unresolved projections publish
  no physical hint. Twelve guest groups, ten body native laws and pinned local
  lint pass. Selected-call edit CPU is about 22–26% lower in a development
  screen; population costs more. General cutoff and module qualification remain.
  Current exact delta and measurements are in
  `build/bench/finish-program-20261014/selected-body-source/` and
  `build/bench/finish-program-20261014/selected-body-pairs*.json`. Ordinary loop
  receipts now preserve carried predecessor bindings and lexical break
  snapshots. Two root full-OOM laws, six loop/owner guests and 384-file zero
  lint pass in `body-loop-receipts/`. A five-pair development screen reduces
  128-loop retained edit/revert CPU 150/160 to 120 ms, with elaborations 130 to
  2; population rises 110 to 160 ms and plain controls stay unchanged. General
  interfaces and total edit acceptance remain open. Ordinary `use` statements
  now retain exact names, annotations and existing binding/type facts without
  new side tables. Root capture/replay OOM and both loop/use guest tiers pass in
  `body-use-values/`. Field/index updates now reconstruct selector paths from
  existing typed facts and retain exact root/old-leaf bindings. Root
  capture/replay OOM, five guest groups and 384-file zero lint pass in
  `body-path-updates/`. Development edit/ revert CPU falls 190/190 to 130/140 ms
  for 128 bodies; population rises 130 to 180 ms. Plain wall controls remain
  within 0.3%. Preserve `/var/tmp/blot2-task024-core-fragment-prototype`: its
  additive replay removes lowerings but is slower and unmergeable.
  Annotation-recipe evidence is in
  `build/bench/continuation-20261014/annotation-recipes/`.
- **035 / 047:** Production emission requires complete ownership; all 2,866
  captured bodies admit it. Raw/private fixtures retain compatibility. Broad
  ownership qualification and remaining window fold/cursor/semantic-buffer work
  remain. The isolated replacement fold removes objects but increases payload
  bytes and is not accepted. Preserve `/var/tmp/blot2-iterator-window-fold-047`
  and the earlier frozen iterator/ownership checkouts. A verified tracing screen
  rebuilds the exact historical fixture artifact: current cycle CPU is
  13.30/13.19 ms versus 5.47/5.70 ms, with warmed memory 128 KiB versus 16,320
  KiB. `ownership-vs-tracing/tracing-screen/` pins both modes, sources and raw
  rounds. CPU qualification remains open. A larger collection cadence was slower
  and doubled memory; it stays private. Discovery now subtracts each gray-target
  edge immediately, removing the separate member edge sweep. Twenty-five
  alternating pairs lower cycle CPU 2.4% sync / 3.5% JSPI with unchanged 128 KiB
  warmed memory and 190 fewer Wasm bytes. Nine integrated cycle/layout/acquire
  laws and 23 raw/cycle/resource guest groups pass, with byte-identical measured
  and integrated cost Wasm. `cycle-edge-fusion/` pins the small improvement; the
  historical CPU gate stays open. A private mask-bit iterator missed the
  two-mode acceptance threshold: sync was 0.6% slower, JSPI 10.3% faster, with
  128 extra Wasm bytes. Keep the root implementation;
  `/var/tmp/blot2-cycle-mask-ctz-evidence-20261015` pins the rejected candidate
  and clean 25-pair measurements. Fusing dead classification into member
  partition was also screened privately. Its nine native and 19 executed
  graph/resource/source laws pass; 25 alternating pairs lower CPU 15.4% sync /
  4.8% JSPI, retain 128 KiB and remove 44 Wasm bytes. JSPI misses the declared
  5% two-mode threshold, so the root stays unchanged. `cycle-partition-fusion/`
  records exact source, inputs, results and rejection. Getter/direct dispatch
  and single-activation field ownership are now integrated. Their focused
  native/OOM and executed-Wasm laws pass. The pinned screens lower cycles about
  17% together with flat 128 KiB warmed memory. Historical geomean 1.302610
  remains above 1.10 and p95 gates still fail; tracing metadata stays intact.
  Exact integration evidence is in
  `build/bench/complete-program-20261015/getter-dispatch/` and
  `activation-owner/`. Exact scalar-result inlining now exposes one four-byte
  capture to existing scalar replacement. Focused native/OOM and both guest
  tiers pass; 25 balanced rounds lower cycle CPU about 27–28% from the original
  current baseline. Historical cycle ratios remain 1.58 sync / 1.56 JSPI, above
  the required gate. `scalar-capture/` preserves all rounds and rejected
  alternatives. Checked demand-producer descriptors preserve the same memo cell
  and replace its indirect force edge with an exact direct target. Replay,
  allocation-failure and original-table-slot sharing checks pass. This is a
  proof prerequisite; no additional CPU improvement is claimed.
  `demand-descriptor/` records the encoder correction and integrated source.
- **058 / 059:** Named unary input callbacks now use existing owned result
  recipes only with a separate source/Core no-store proof. Hidden stores,
  discarded request payloads and unknown applications remain guarded. Five root
  native laws, one full development generation group (both tiers privately) and
  332-file zero lint pass; exact pins are in
  `build/bench/complete-program-20261015/named-input/`. General multi-input,
  higher-order and abstraction contracts remain open. Exact result/capture/store
  graphs, deferred-block/pattern captures and scoped descriptor-bearing argument
  shapes are integrated. Invocation binders and generative per-call versions are
  now integrated from `/var/tmp/blot2-capability-generative-qualified-20261014`.
  Their `Scheme.generative` owns arrow/selected-type pairs; body reuse and
  staging decline nonempty lists until their copiers own relocation. Three
  focused native laws, three invocation/rank guests, 26 reuse/staging groups and
  all eight ordinary compile budgets pass; affected-file lint has zero findings.
  Returned Unit factories now retain earlier captures while freshening each
  callback invocation; two native artifact/OOM laws and both guest tiers pass.
  Higher-order/anonymous transport and general foreign sink graphs remain
  isolated follow-on work. The returned delta is in
  `build/bench/finish-program-20261014/returned-invocations-source/`. Preserve
  `/var/tmp/blot2-generative-effects-058` and its checkpoint patches. Validation
  context reuse now declines generative or existential foreign interfaces until
  its owned image records those dependencies. Constant replay and callable
  templates also decline invocation identities hidden inside scalar-result
  bodies. Four native laws, ten guest groups and affected-file lint pass at that
  checkpoint. Scoped relocation now records exact correspondence between
  scheme-owned instance variables and concrete owners, while captured owners and
  invocation versions remain exact. Two new native laws, the original ordinary
  compound replay assertion and both generation guest tiers pass. The callback
  pattern and malformed call-chain repairs are integrated too. Captured
  fresh/edit/revert preserves exact Wasm and 70,330 steps, with eleven retained
  hits, 61,383 replayed steps and no retries. Retained CPU is about 12.6–12.8 s
  before the owned presence fast path. Session/Gate now summarize generative
  source presence once, preserving unconditional owner checks and all deep
  guards when either context contains the feature. Five focused native laws, ten
  guest groups and 233-file selected lint pass. One development pair lowers
  retained edit/revert CPU from 12.84/12.55 to 10.69/10.27 s with exact bytes,
  fuel and inference counters. Pins are in `guard-presence/`; this is not
  release or task 093 qualification. Checked suspension headers now retain their
  exact refinement owner without admitting suspended creation or full body
  inference. Three native laws and the deferred-call receipt guest pass; the OOM
  sweep covers 38 failures. `header-owner/` records the delta; measured CPU
  stayed near parity. Formal Unit callback invocation now reconstructs complete
  application chains and freshens only the actual creator's declaring versions.
  Independent creations retain distinct slots; capture-only versions remain
  exact. Twenty native laws, two artifact OOM laws, eight guest groups and
  selected lint pass. `formal-invocation/` records the merged source. General
  callback inputs and no-store compositions remain open. Structural
  record/product callback projections now prove exact executable creators and
  physical field paths. Unsupported owner paths with version-bearing outputs
  reject, including coordinated erased catalog mutants. The complete
  projected-artifact OOM law, creator control and both generation guest tiers
  pass; pins are in `callable-projection/`. The finite typed-input callback
  delta is integrated in `typed-input-invocation/`, combining private patch
  `fca31b8e` with reviewed five-file correction `7aebd7c7`. Actual callback
  bodies prove conditional no-store authority; discarded non-scalar Unit
  requests still inspect their receivers. Invariant/unowned row tails remain
  exact, and memoized comparisons distinguish covariance. Local aliases prove
  raw initializer to owned principal using their closing certificate, then
  principal to reference use; unchanged captured variables retain exact identity
  within the same immutable module. The combined root passes 29 native laws, 14
  complete OOM sweeps covering 9,011 fault points, 47 guest groups including all
  eight compile budgets, and 377-file affected lint with zero findings. Resource
  transfer, numeric plans, Bool staging and numeric rank witnesses remain
  qualified in that combined tree. General forwarding/factory/projected input
  recipes and arbitrary storage graphs remain open. The release binary is
  unchanged; the final full gate is still pending. The exact combined guard
  delta is in `generative-receipt-context-source/` under the current
  `build/bench/finish-program-20261014/` evidence directory.
- **061 / 062:** Usage control flow, lexical loans and bounded pure scalar
  resource scopes are integrated. The invocation journal drains cleanup/drop in
  reverse order, preserves body failure priority and guards suspension, reentry
  and disposal. Primitive Array/List payloads now retain their journal-owned
  reference through cleanup; the reference adapter drops payload, callback and
  provider roots even after a cleanup trap. Fifteen focused native laws and five
  guest groups pass, including complete source/Core and backend allocation
  failures, sync/JSPI roots, flat warmed memory, imports and restart. Exact pins
  are in `build/bench/finish-program-20261014/reference-resource-source/`.
  Explicit unique-to-shared conversion of primitive and primitive Array/List
  owners is integrated, together with the inherited once-callback header repair.
  Thirty-nine native laws, six guest groups and 373-file selected lint pass.
  `sharing/` records the delta. Invocation-local acquired owners are now
  integrated: primitive and numeric Array/List payloads carry one counted box
  and cleanup token through moves, sharing and once captures. Retirement queues
  cleanup after stable RC/cycle transactions; lexical branches publish merged
  roots before their temporary owners close. Source/Core startup forgeries and
  public owner outputs reject. Twelve checker and ten backend laws, complete
  allocation-failure sweeps and 22 resource/rank guest groups pass. Nine numeric
  laws and 13 numeric/generation guest groups preserve the newer merged proofs.
  `resource-transfer/` records exact before/source/merged pins and the first
  excluded guest attempt with its missing fixture. The reviewed wide-layout
  repair deduplicates before queueing and follows quantified payloads,
  preserving the exact unique-node bound with zero allocation and 16 KiB fixed
  storage. New regressions fail against the original walker and pass after
  repair. `layout-owner-worklist/` records the correction. All 428 affected Zig
  files have zero findings. Exact finite cleanup ranges now reconstruct
  source/Core bounds and charge every iteration, including empty-body loops.
  Unknown bounds, oversized nested work and forged receipts reject. Four focused
  native laws, 210 complete allocation failures and both guest tiers pass.
  Resource request cancellation and retries now admit invocation owners while
  preserving unrelated effects; repeatable bodies reject captured affine moves.
  Corrected Core validation checks type/catalog bounds before dereference. Four
  native laws, 440 complete allocation failures, seven resource/scoped guest
  groups and 376-file zero analyzer pass qualify the merged request changes.
  Exact evidence is in `build/bench/complete-program-20261015/finite-cleanup/`
  and `resource-request/`. Nominal/opaque payload affinity now carries one
  shared scan budget and requires exact imported producer definitions. Owning
  package views preserve the original cleanup token. The 17-file region/view/
  nominal merge passes five checker laws, three executed-Wasm groups and
  377-file zero lint; pins are in `ownership-integration/`. Explicit synchronous
  host cleanup capabilities now own their ABI, call budget and provenance;
  ordinary/async callbacks reject. Finite pure producer-local cleanup bodies use
  independent source/Core receipts. Five native/OOM laws, seven guest groups,
  client signature checks and 377-file zero lint pass in `host-cleanup/`. Closed
  structural aggregate payloads now reconstruct nested product, record,
  Array/List and nominal storage under one budget. Producer-owned `has_usage`
  keeps shared owners repeatable while preventing lifetime erasure through plain
  package witnesses or lifts. Four aggregate/nominal guest groups and nine
  native/OOM laws pass; exact source is in `general-resource/` and
  `nominal-usage-authority/`. Closed nominal storage now reconstructs exact
  generic constructors and operand roles; three native/OOM laws, seven guest
  laws and 380-file zero lint pass in `nominal-closed-storage/`. Public `once`
  exports consume their native guard before body entry, including failure and
  suspension. One replay/OOM law, six guest/metadata/async laws and 236-file
  zero lint pass in `public-once-entry/`. Persistent public owner handles now
  use instance-bound typed native leases and retained synchronous cleanup
  bindings. Five root native/OOM/import laws, nineteen guest/journal groups and
  240-file zero lint pass in `public-owner-lifetimes/`. Private ordinary
  controls preserve Wasm bytes with wall-time increases of 1.29% fresh and 0.75%
  retained. Host structural payloads, general portable rank region recipes and
  the final full gate remain open.
- **035 provider prerequisite:** Exact provider parameters, checked result
  roles, physical constructor initialization and guarded head flow now survive
  replay/archive. Three root native/OOM laws, six once/cleanup/demand guest laws
  and 238-file zero lint pass in `provider-proof-v2/`. The State-only optimizer
  consumer is now integrated; it owns the complete mode catalog in captures and
  archives and preserves guarded reads plus publication before collection. Three
  root native/OOM laws, eight archive neighbors, six guest groups and 239-file
  zero lint pass in `state-provider-consumer/`. Private cost Wasm drops 12,297
  to 11,958 bytes, with unchanged allocation counters. Historical CPU gates
  remain open.
- **064 / 065:** Source/Core rank checking, owned constant evaluation and
  structural/sequence/nominal package carriers are integrated. Portable rank v2
  admits one pure `forall[a] => a -> a` identity recipe with scalar and managed
  numeric Array/List per-use witnesses, exact lexical owners and independent
  executable validation. It passes the compiled positive and negative controls
  with a shared traversal budget. General binder, row/region/predicate and
  qualified-drop frontiers remain open. Portable two-binder structural package
  publication is integrated, with heterogeneous witnesses and captured
  callbacks. Five native laws and five guest groups pass. Caller-aware
  validation context classification is integrated; seven combined native laws
  and four import/restart guest groups pass, with zero findings across 328
  selected files. The source is frozen in
  `/var/tmp/blot2-integrated-callers-20261014`. The three-file Array witness
  extension passes four native laws and the source/archive/checkpoint/restart
  guest in both tiers, plus eight carrier and package neighbors. Same-layout
  Array F32, hidden effects and nonidentity body mutations reject. Sixty-four
  repeated raw/guest calls keep zero roots/leases and flat warmed memory;
  returned host copies survive disposal. `array-rank/` records the exact delta.
  General collection recipes remain open. The same carrier now admits Array F32
  and List U32/F32 too. Four native laws reject eight coordinated
  witness/result/header/effect/body mutations even when the forged type itself
  is admissible. Principal comparison independently follows element types. The
  rank guest and eight carrier/package neighbors pass in both tiers; 256 warmed
  raw and managed calls per artifact keep zero roots/leases and flat
  196,608-byte memory. `numeric-rank/` pins the three-file delta.
  Nonnumeric/nested/qualified element witnesses remain closed. Canonical
  quantifier evidence now owns every sorted binder, including phantom binders
  and formal loan edges; fresh wire tags prevent older readers from accepting
  the new layout. Nested evidence imports and lazy evaluator frames preserve
  lexical ownership without widening type nodes. Focused canonical and
  universal-pipeline allocation-failure laws pass, with zero findings across 378
  selected files. `build/bench/complete-program-20261015/quantifier-evidence/`
  records the exact merge. This representation does not yet qualify general
  parametric executable bodies, row/predicate contracts or stored dictionaries.
  Immutable predicate goal ownership is now integrated in Store, Core and frozen
  source graphs. Equality, substitution, scope checks and rollback preserve
  exact goal endpoints. Nested substitution/resolution clones inner binder
  owners; principal projection preserves sorted structural quantifiers. Three
  root native/OOM laws and six guest laws pass; the private union also passes
  the higher-rank neighbor, fourteen guests and 384-file zero lint. Exact delta:
  `quantifier-goals/`. Core capability reconstruction now follows exact returned
  literal closure binders after a named call while retaining outer aliases. The
  root new native/OOM law and nine rank/scoped guests pass; private malformed
  call and parameter-domain neighbors, eleven guests and 379-file zero lint pass
  in `nested-capability/`. The identity-only rank verifier is now removed. One
  lexical verifier reconstructs multiple binders, products, records, generic
  Array extraction, nested universals/captures and explicit polymorphic
  recursion. Three root native/OOM laws, five guest groups and 238-file zero
  lint pass in `structural-rank-verifier-v2/`; formal rows, predicate
  dictionaries and broader region runtime remain open. Formal row tails now
  preserve sorted owners through Source checking, Store/Core/PI and canonical
  evidence. Three root complete OOM laws, six guest groups and 380-file zero
  lint pass in `formal-row-ownership/`. Sorted universal row carriers now
  execute dynamic pure/Foreign callbacks with exact provider forwarding and
  bounded generic row argument matching. Five root native/OOM laws, eight guest
  groups and 388-file zero lint pass in `sorted-universal-row-carriers/`.
  Source/Core/runtime predicate dictionaries and canonical ordered goals are now
  integrated together. Methods remain strong package contents; exact lexical
  openings load their own methods, and E preserves every goal endpoint through
  projection, snapshots and imports. Five root native/OOM laws, eleven guest
  groups and 386-file zero lint pass in `dictionary-canonical-union/`. Source/
  archive/checkpoint/restart/recovery and both tiers sync/JSPI execute privately
  and in the root portable law. The private archive native compile hit its
  60-second bound without a result; it remains unqualified. General universal
  predicate introductions/evidence ABI, associated projections/resealing/drop,
  ordinary inferred schemes in quantified modules and the final full gate remain
  open. A private Source-only universal introduction/OOM prototype is in
  `/var/tmp/blot2-universal-dictionaries-20261015`; it is not integrated and has
  no Core/runtime admission yet.
- **067 / 068:** Imported producer effects and private/opaque bodies now
  validate independently against conservative declared rows. Generic operation
  row permutations retain later matching candidates and propagate budget
  failures. Four native laws, four executed-Wasm groups and 238-file zero lint
  pass; pins are in `build/bench/complete-program-20261015/staging-producers/`.
  Typed syntax, closed evaluation, portable staging, nested quotes and
  producer-local first-order pure named calls are integrated, including bounded
  generic substitution reconstructed from each callee's owned variables. Public
  ordinary nominal lifts retain exact constructor, argument and payload proofs
  through snapshots; hidden callable values reject. Producer-local immutable
  data reads reconstruct their exact body and generic owner too; runtime,
  foreign and cyclic reads reject. Focused staging guests cover tracked JSON
  asset byte edits, failure recovery and restart. Focused Core/snapshot laws and
  OOM sweeps pass; pinned affected-file lint is zero. Exact six-file delta is in
  `build/bench/finish-program-20261014/staging-source/`, with the data-read
  delta in `staging-producer-data-source/`. Public nominal descriptors now
  expose only fields shared by every constructor, with exact generic
  substitutions; all fourteen staging guest groups pass. Four focused
  descriptor/neighbor native laws pass, including portable OOM and
  forged-owner/type controls. That delta is in `nominal-descriptor-source/`.
  Indirect, effectful, scoped, sealed/package and general generated declaration
  support remain open. Pure helper blocks now own earlier local bindings and
  exact return targets; nested generic aliases pass portable OOM and four helper
  guest groups. Forward reads, caller-local captures, duplicate owners and
  foreign returns reject. The three-file delta is in
  `staging-local-blocks-source/`. Pure named helpers now construct ordinary
  nominal data too. The reader reconstructs each constructor's generic result,
  payload and positional input; private families, forged payloads and hidden
  callables reject. Five native laws and five helper guest groups pass, with
  exact fresh/edit/restart work. The three-file delta is in
  `staging-nominal-helpers/`. Collection helpers now reconstruct length,
  indexing, identity, concatenation, slicing and Array/List conversion shapes.
  Four native laws and seven helper guest groups pass; both collection tiers
  preserve exact fresh/edit/restart bytes and 76 work steps, with zero work on
  unchanged/recovered input. Invalid shapes and out-of-bounds edits reject. The
  three-file delta is in `staging-collection-helpers/`; final qualification
  remains outstanding. Pure nominal field-reader helpers now reconstruct public
  constructor tags, physical field positions and generic result ownership
  independently. Seven native laws and nine helper guest groups pass, including
  complete roundtrip OOM, forged paths and both-tier edit/restart recovery with
  40 work steps. The delta is in `staging-nominal-reads/`. Pure helper statement
  `if` suites now preserve source/archive parity too. Both branches reconstruct
  their local bindings and exact enclosing return target; unselected effects,
  foreign returns, branch leaks and mutable merges reject. Six native laws and
  twelve selected helper/staging guest groups pass, including complete portable
  and checkpoint-restart allocation sweeps. Both tiers retain exact
  fresh/edit/restart bytes and 31 work steps, with zero work on
  unchanged/recovered input. `staging-statement-if/` pins the four-file delta;
  general case, loops and broader staging remain open. Exhaustive guard-free
  Bool cases now reconstruct exact 1/0 patterns and both typed arm bodies
  through the same reader, with independent local owners. Eleven
  pattern/result/ownership mutations and unselected effects reject. Seven staged
  native laws, including complete portable and restart OOM, pass alongside four
  rank laws and eleven combined guest groups. Bool fresh/edit/ restart uses 30
  steps; prior statement-if remains 31, unchanged/recovery zero.
  `staging-bool-case/` pins the four-file delta; general patterns and mutable
  control flow remain open. Closed sealed packages and qualified owning carriers
  now retain their original cleanup token through Code snapshots and imports.
  Foreign-only inferred rows require the exact current body certificate; the
  missing-certificate native failures and correction are retained separately in
  `sealed-packages/` and `package-foreign-rows/`. Generated diagnostics now
  carry bounded quote/generator/splice/invocation origins for the actual
  selected generator instance. Archive corruption, allocation failures, pool
  leases, source/checkpoint/restart failures and recovery pass in focused
  checks. `generated-origins/` pins the implementation. Origins confer no
  executable, provider or type authority. See
  [staging](zig-native/STAGING_QUALIFICATION.md).
- **070 / 071: complete.** The finite acceptance audit, exact value/length
  contracts, portable authority, guard/trap order and erased representation pass
  the final combined gate. Unknown or exhausted optional analysis retains
  checks. Current acceptance and historical measurements are in
  `zig-native/NUMERIC_PROOFS_QUALIFICATION.md`; avoid reopening old prototype
  limitations already superseded by the finite audit.
- **073 / 074:** Structured concurrency designs are complete; implementation
  waits for the remaining usage/resource/proof authority. Start with affine
  scoped handles, cooperative execution and child-before-parent cleanup.
- **086 / 093:** Compound replay now owns ordered dependency reads, reachable
  typed views and private buffer frontiers through the existing graph validator.
  Captured edits replay 61,383 local steps in eleven hits, with exact 70,330
  source fuel and fresh-identical Wasm. One development pair is near CPU parity;
  snapshot copying falls from 1,073,244 to 615,084 bytes. Unchanged inference
  and backend preparation dominate the remaining time. The integrated delta is
  frozen in `/var/tmp/blot2-task086-demand-frontier-freeze-v2-20261015`; its
  isolated owner continues the preparation/inference hill. Focused alias,
  descriptor, frontier, limit and allocation-failure laws pass. Any mismatch
  after dependency demand tears down the attempt before a single ordinary retry;
  OOM propagates directly. Exact diagnostic source, logs and owner assessment
  are preserved in
  `build/bench/continuation-20261014/constant-current-diagnostic/`. Do not merge
  its logging patch or reuse the older 177-step inference trace as current
  attribution. General mapping/view publication still needs owned effects.
- **075–081 / 084 / 999:** Respect dependencies. Task 075 has no feature-task
  edge; broad owner/module moves and final documentation/qualification remain.
  Test extraction may continue as an iteration improvement. Do not delete tasks,
  PLAN.md or this handoff before task 999's prerequisites hold.

## Iteration and validation

Check Zig **0.17.0 before each build batch**; set `TMPDIR=/var/tmp`. Use
`deno task build:compiler:dev` for development, writing
`zig-native/zig-out-dev/bin/blotc`. Ordinary caching gives about 0.05–0.06 s
warmed builds; `--incremental` is an explicit option for real production edits.
Test-only edits should use ordinary caching. Release output is
`zig-native/zig-out/bin/blotc`. Before a new native filter, locate its file in
`zig-native/src/*_suite.zig`; `core_proof_tests.zig` belongs to `evaluator`,
while `runtime_operation_backend_tests.zig` belongs to `backend`. Require a
nonzero selected count; a wrong suite compiles successfully but tests nothing.
`layout.zig` is in `backend`, not `types`; inspect imports instead of guessing.
Use `-Dtest-force-run=true` when fresh native execution/counts are required; an
unchanged cached success may emit no log. Preserve the previous qualified log.

Use focused native filters/subsystem roots or actual positional `.test.ts`
files, with **60-second uncertainty probes**. A broad development guest attempt
hit its budget after 323 passes; keep that attempt marked incomplete. The full
release gate above supplies complete guest coverage. Never raise the cap merely
to finish an exploratory sweep. `scripts/bench_list_traversal.ts` now accepts an
optional eighth argument of widths, e.g. `tuple 1 u32 3` or `record 1 u32 1,16`.
Omit it for the required all-width matrix. The two-edge-width functional smoke
took 1.229s; evidence is in `focused-list-widths/`. Before compiler commits,
require the complete `deno task test:compiler` and zero-finding
`deno task lint:zig`.

The pinned analyzer is
`/home/jacobt/.cache/blot-tools/zig-analyzer-0.17.0-1-x86_64-linux/bin/zig-analyzer`.
Zig must be on PATH: earlier isolated zero reports without its stdlib backend
were invalid. Lint now checks prerequisites and full toolchain cache keys.
`deno fmt --no-config` formats files beneath `zig-native/`.

The fourteen iteration hills are integrated; see
[measured iteration costs](zig-native/ITERATION_COST.md). Native/release builds
now overlap. The latest full run serialized its two native execution shards; its
479.533 s execution prompted a bounded concurrency probe. The final profiled run
overlaps both shards and takes 258.509 s; no scheduler change was made. Another
39 type laws and 16 helpers moved out of production hashing without new public
APIs. Native resume excludes qualification notes but retains compiler/runtime
inputs. Keep exhaustive OOM coverage in the final gate; do not repeat it for
each slice.

## Preserved work and owner choices

Preserve all private sources, failed candidates, measurements and unrelated
work. The complete earlier handoff is frozen at
`/var/tmp/blot2-continuation-reuse-repaired-20261014/CONTINUE.md`; it retains
historical checkpoints and their paths. Failed batches remain under
`build/bench/continuation-20261014/`, including `repaired-failed-release/`,
`guest-failed-release/`, and their separate source manifests. Qualified control
`b4fb67c…` and its own standard library remain pinned under the 13 October
continuation evidence and `/var/tmp/blot2-continuation-invocation-20261013`.

Task 083's proposal lists 46 inactive cache directories, 4,946,001,920 bytes, in
`build/bench/continuation-20261014/cache-cleanup-proposal.json`. No deletion is
authorized or performed. Task 082's push/remote-workflow decision is separate.
Other owner choices remain `/var/tmp/blot2-names.patch` (always-on Wasm names,
about 5% more bytes) and tuple patterns in comprehension generators. Continue
ordinary authorized work independently.

gdev/pen contain other sessions' changes; do not edit or commit their private
sources. gdev links this repository's compiler bundle and standard library.
Captured asset roots are `src` and `devtools`. Missing historical boxed/prewalk
binaries and the old frozen gdev manifest were waived on 11 October; qualify
current reproducible workloads while retaining the reconstructed boxed reference
and all-width cursor requirement. bpm is complete at `2798ff9`; no package is
published.

Checked borrowed State provider lifetime summaries and reachable-release/journal
negatives now pass three root native laws, eleven guests and selected lint in
`build/bench/complete-program-20261015/provider-lifetime/`. Cost Wasm and
runtime counters remain unchanged; task 035 remains open.

Structural synchronous host cleanup ABI 7 is integrated with exact schema/import
roles, detached copies for closed products/records/packed sequences/public
recursive variants and opaque witnesses. Root four native laws with replay/full
OOM, 22 guests plus seven corrected copy/execution groups, selected lint and
TypeScript checks pass in
`build/bench/complete-program-20261015/structural-host-cleanup/`. The
packed-List logical extent correction is included. Ordinary private wall
controls stay flat with identical Wasm. Generic region/package execution and the
final gate still keep 061/062 open.

Universal physical dictionary-slot metadata is integrated in
`build/bench/complete-program-20261015/universal-dictionary-layout/`: ordered
signatures, explicit empty ABI marker, owned snapshots and conservative semantic
reverse conversion. Four native/OOM laws, two portable dictionary/State guests
and selected lint pass. The stale pool test HostKey fixture is repaired. Full
universal dictionary execution is still private.

Ordinary inferred scheme variables/rows now coexist with explicit quantifiers
and packages under independently rederived admission. Root three native/full-OOM
laws, three rank/dictionary guest groups, selected lint and new TypeScript
checks pass in
`build/bench/complete-program-20261015/inferred-scheme-admission/`. Declared
physical captures remain authoritative even if unused. Deferred ordinary scheme
obligations and associated abstract projections remain open.

2026-10-15 callable endpoint metadata: the fourteen-file freeze is integrated
with current HostKey and structural cleanup ownership preserved. Five root
native laws (including full OOM replay/import mutants), seven executed guest
groups and 242 selected analyzer files pass; affected TypeScript checks pass.
Evidence and exact source/compiler pins:
`build/bench/complete-program-20261015/callable-endpoints/`. The facts have no
new dispatch consumer yet; unchanged private Cost bytes and counters establish
no allocation or CPU improvement. Cross-file retained producer reconstruction
remains a separate repair. All 29 tasks stay open.

2026-10-15 associated projection authority foundation: eighteen files cleanly
merged; canonical and physical projection coordinates retain exact lexical
contract goal/member ownership. Five root native laws (new full-OOM canonical,
Core/opening and physical checks), four executed neighbor groups and 389
selected analyzer files pass. Exact evidence:
`build/bench/complete-program-20261015/associated-projection-authority/`. The
pack-only resolver hook is ready; selected-proof substitution, Source/runtime
associated methods and closed-signature dictionary capture checks are still
unfinished. No task completion or full compiler qualification is claimed.

2026-10-15 captured pure-call receipt repair: the four-file minimal delta is
integrated. Exact primitive/pure signature operands now retain lexical closure
captures; Foreign, uncertified and role mutants still decline. Root two native
laws, the cross-file returned callable record-to-Array edit law (both tiers,
sharing modes, fresh/retained equality, sync/JSPI), 388 selected analyzer files
and affected TypeScript checks pass. Evidence:
`build/bench/complete-program-20261015/captured-pure-call-receipts/`. This
closes that focused retained producer repro; all 29 tasks remain open.

2026-10-15 universal stored dictionaries: fifteen-file delta integrated,
preserving projection authority, structural cleanup and callable endpoint
metadata. Separate reference dictionaries support checked forall
introduction/elimination, curried partial application, ordinary closure captures
and exact-owner helper forwarding. Cross-pool dictionary-key imports
conservatively rebuild. Root four checker and two backend laws (new full OOM),
eleven executed groups, 389 selected analyzer files and affected TypeScript
checks pass. Archive/checkpoint/recovery, traps, warmed memory and balanced
root/lease controls are included. Exact pins:
`build/bench/complete-program-20261015/universal-dictionaries/`. Associated
outputs, explicit dictionary resealing and remaining capture/region
qualification are unfinished; all 29 tasks and final full gate remain open.

2026-10-15 dictionary capture/projection checks: seven-file delta integrated
over universal execution. Source and Core retain exact lexical goal footprints
through closed method signatures; only exact explicit witnesses reseal them.
Pack-only associated substitution consumes that pack's selected type member.
Root four new native/full-OOM laws, nine executed groups, 389 selected analyzer
files and affected TypeScript checks pass. Evidence:
`build/bench/complete-program-20261015/dictionary-capture-projection/`.
Source/runtime associated outputs, dictionary forwarding during package
resealing and a static global package serialization panic remain separate
implementation; all 29 tasks and the final full compiler gate stay open.

2026-10-15 ordered scoped callback inputs: twenty-file delta integrated,
preserving current dictionaries and instance argument identities together. Two
stale deleted public footprint wrappers were restored; the initial failed build
is retained. Root three native laws including complete
lowering/validation/emission OOM and compact wire, ten guest groups including
inferred/universal archives, 389 selected analyzer files and affected TypeScript
checks pass. Ordinary wire stays seven bytes. Exact-source wall controls show
+1.35% fresh/+0.29% retained with identical Wasm; no CPU/speed improvement is
claimed. Evidence:
`build/bench/complete-program-20261015/ordered-callback-inputs/`. General
forwarding/projected callbacks and unknown sink lifetimes remain open; no task
completion or final full-gate qualification is claimed.

2026-10-15 static package serializer: three-file repair integrated; rich
constant packages no longer reach the unreachable aggregate serializer. Exact
canonical recipes recover admitted Core quantifiers; typed static carriers
preserve method adapters and relocation roles. Root two backend laws including
full emission/replay OOM, ten executed groups, 110 selected analyzer files and
affected TypeScript checks pass. Static scalar/Float/product/nominal/Array/List,
source/ archive/checkpoint/literal-edit, warmed memory and ownership controls
are included. Exact pins:
`build/bench/complete-program-20261015/static-packages/`. Arbitrary outer-owner
nested recipes and associated outputs remain unfinished.

2026-10-15 rejected guarded provider expansion: preserve the wholly private
seven-file prototype
`/var/tmp/blot2-guarded-provider-expansion-evidence-20261015/`. Five
native/full-OOM, fourteen guest and 435 analyzer controls pass, but 25 balanced
runtime rounds regress sync/JSPI medians 4.74%/4.32% and p95 4.35%/3.47% against
endpoint/lifetime baseline. Wasm grows 11958 to 13061B; counters and 128 KiB
stay flat. Historical median geomean 1.702165>1.10 and p95 ratios
1.709610/1.595137>1.20 fail. Do not integrate or claim task 035 completion.
Exact rejection is in its EVIDENCE.md and runtime-summary.json; final pins SHA
cb036c71f9647b4184aa70a5ec755257004b776045256db6f014cef4a337de94.

2026-10-15 forwarded scoped invocation: seven-file delta integrated after the
static serializer. Exact executable producer chains reconstruct ordered callback
inputs with bounded independent Core checks. Root one new native law with full
lowering/validation/emission allocation failures, five executed groups, 389
selected analyzer files and affected TypeScript checks pass. Existing
metadata/wire is unchanged. Exact pins:
`build/bench/complete-program-20261015/forwarded-invocations/`.
Projected/factory callbacks and unknown sink lifetimes remain open; all 29 tasks
and the final full compiler gate remain open.

2026-10-15 dictionary resealing: nine-file delta integrated. Repacking consumes
exact active opening/universal dictionaries; immutable Core reconstructs owners,
arguments and ordered method references independently. Root four native/full-OOM
laws, nine guest groups, 389 selected analyzer files and affected TypeScript
checks pass. Exact pins:
`build/bench/complete-program-20261015/dictionary-resealing/`.
Source/archive/restart, edits, warmed memory and balanced owners are included.
Associated runtime results, nested sealed closure return composition and
ordinary inferred helper evidence transport remain open, as do all 29 tasks and
final gate.

2026-10-15 inferred predicate schemes: eight-file delta integrated alongside
repacking, preserving both appended native law blocks. Exact scheme-owned
predicate frames and publication variable/row bijections now coexist with
annotated polymorphism. Root five native/full-OOM laws, seven executed groups,
246 selected analyzer files and affected TypeScript checks pass. Exact pins:
`build/bench/complete-program-20261015/inferred-scheme-predicates/`. Unknown
universal helper transport, ordinary projection ownership, broader Core forms
and effectful staging composition remain open; all 29 tasks remain open.

2026-10-15 forall with nested package opening: three-file delta integrated.
Exact opening binding/ordinal identity permits coexistence with an outer forall.
Root two native/full-OOM laws, three executed groups, 246 selected analyzer
files and affected TypeScript checks pass; wrong ordinal/owner mutants reject.
Exact pins: `build/bench/complete-program-20261015/universal-nested-opening/`.
All 29 tasks and the final full compiler gate remain open.

2026-10-15 provider activation lifetime: two-file proof/test delta integrated;
existing universal/static backend laws are preserved. The optional law tracks
allocation origins, owned parent links and CFG retirement, rejecting stale
aliases, transitive borrowers and repeated/early retirement. Root three
native/full-OOM laws, 22 executed groups and 243 selected analyzer files pass.
Cost remains exactly 11958B/SHA
1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad. Exact pins:
`build/bench/complete-program-20261015/provider-activation-lifetime/`. No
optimizer consumes this proof yet; historical gates, task 035 and final gate
remain open. All 29 tasks remain open.

2026-10-15 ordinary associated schemes: seven-file delta integrated. Exact
callee scheme clauses and selected proofs govern projection endpoints; partial
dictionary calls retain exact opening ownership. Root three native/full-OOM
laws, four executed groups, 247 selected analyzer files and two TypeScript
checks pass. Exact pins:
`build/bench/complete-program-20261015/ordinary-associated-scheme/`. General
associated package payloads, helper runtime evidence transport and final
qualification remain open. All 29 tasks remain open.

2026-10-15 associated dictionary results: six-file delta integrated. Exact
lexical and universal dictionary owners now transport opaque scalar/Float/Array
results; static methods use their evaluator-owned concrete signature. Concrete
forall sealing reconstructs its checked given before selecting representation.
Root two native/full-OOM laws, 16 executed groups, 244 selected analyzer files
and two affected TypeScript files pass. Source/archive/checkpoint/restart and
warmed ownership pass. Ordinary Cost Wasm remains exactly 11958B/SHA
1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad. Exact pins:
`build/bench/complete-program-20261015/associated-dictionary-results/`.
Associated package payload normalization is the next separate Source slice;
nested sealed closure recipes and implicit helper evidence transport remain
open. All 29 tasks and the final full compiler gate remain open.

2026-10-15 curried numeric methods: four-file delta integrated. Existing
prepared selected targets now preserve numeric operands/conditions through exact
owned returned closures and literal/alias captures. Root five native laws
including complete OOM/replay sweeps, five executed groups, 244 selected
analyzer files and affected TypeScript pass. Identity comparisons fall 1 to 0;
wrapping retains 1. Ordinary Cost Wasm remains exact 11958B/SHA
1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad. Exact pins:
`build/bench/complete-program-20261015/numeric-curried-methods/`. Nested
selected helper graphs, general inference and the final full gate remain; all 29
tasks remain open. No compiler CPU improvement is claimed.

2026-10-15 rejected raw provider storage: eight-file candidate stays private at
`/var/tmp/blot2-provider-activation-storage-evidence-20261015`. Four
native/full-OOM laws, 47 guest groups,two raw boundary laws and 434-file zero
analyzer pass, but the quiet CPU 7 balanced 25-round screen is slower: paired
medians 1.06273 sync/1.06007 JSPI vs current baseline, memory 192 KiB vs 128
KiB. Historical median geomean 1.60943 exceeds 1.10 and p95 ratios
1.48794/1.47942 exceed 1.20. It is rejected; fewer allocations alone do not
qualify task 035. Patch
0ccd6835eeb4db5bc8798137ac0a00109e61d0204d0ba83263ad7c27a7b447cb; final-pins SHA
a09dadd742774e0fa5218eb799698fb81f0482df0927f1cba552c1a00e1428fa. Root summary:
`build/bench/complete-program-20261015/provider-activation-storage-rejected/`.
No tracing deletion, runtime integration or full compiler gate occurred.

2026-10-15 associated package payloads: six-file delta integrated. Written goals
scope quantified annotations; ordinary payload positions infer witnesses before
this exact pack's selected type members normalize associated positions.
Evaluator normalizes only the substituted payload copy; partial physical shape
holes grant no semantic associated equation. Root seven native/full-OOM laws
with four Core corruptions, 11 executed groups, 392 selected analyzer files and
affected TypeScript pass. Heterogeneous U32/U32 versus Bool/F32 payloads,
resealing, arrays, archives, checkpoint/restart, invalid edits and sync/JSPI
execute with flat warmed memory. Exact pins:
`build/bench/complete-program-20261015/associated-package-payloads/`. This
package graph rebuilds all 63 runtime fragments after checkpoint; no fragment
reuse is claimed. Semantic associated layout inverse remains closed. Ordinary
Cost Wasm remains exact 11958B/SHA
1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad. Nested sealed
closure recipes, inferred helper transport, broader rank/staging coexistence and
final qualification remain. All 29 tasks remain open.

2026-10-15 rejected direct provider stores: three-file follow-up over rejected
raw8 stays private at `/var/tmp/blot2-provider-direct-store-evidence-20261015`.
Four native/full-OOM laws, 48 guest groups and 434-file zero lint pass. The
quiet CPU 7 balanced 25-round screen improves raw8 about 1% but remains slower
than the qualified baseline (paired medians 1.05256 sync/1.04591 JSPI), with 192
KiB vs 128 KiB. Historical median geomean 1.41608 and p95 ratios 1.35326/1.40726
still fail. No runtime changes integrated. Root evidence:
`provider-direct-store-rejected/`. Final-pinsSHA
c7acab325cbb231f37ce46f56fad2adee93c06309b0ddec27d65e07086e41d2a. The next
substantial 035 hill is independently checked closed-activation graph ownership,
after Core lifetime/sink authority; factory no-store facts alone do not
authorize Memo/State-cycle retirement. All 29 tasks remain open.

2026-10-15 projected callback factories: 13-file delta plus corrected negative
integrated, preserving current dictionary/package/ordinary scheme readers. Exact
Source/Core executable graphs seal callable arguments separately from captured
outer inputs; records,pure Unit factories and generic structural keep preserve
ordered receiver identities. Closed constructor evaluation defers callback code
until its concrete projection use. Root six native/full-OOM laws,nine executed
groups, 393 selected analyzer files and affected TypeScript pass. Forged role,
required executed effect row,body result mask and generalized receiver owner
reject; valid unused outer-row widening remains allowed.
Source/archive/checkpoint/restart, producer edits,reverts,failures and sync/JSPI
pass in both tiers. Pins:
`build/bench/complete-program-20261015/projected-callback-factories/`. Ordinary
Cost Wasm remains exact 11958B/SHA
1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad. A general
lifetime/sink interpreter remains next; factory no-store facts do not prove
closed activation cycles. All 29 tasks and final full gate remain open.

2026-10-15 callable construction/result graph facts: two sequential two-file
deltas integrated. Initial environment input and a complete straight-line
factory result now retain exact allocation/return owner and parameter edges.
Changed owner type/return, later stores, imports, global sinks and malformed
tails decline; creation alone grants no dispatch or retirement authority. Root
four native/import/replay/full-OOM laws,two executed groups and five selected
analyzer files pass. Compiler remains exact
4cd0422a166196be3e0e6dba0623e2c8cef5a11c334eeb44918902ae366ddc13. Evidence:
`build/bench/complete-program-20261015/callable-result/`. State/Memo lifetime
graph and measured ownership qualification remain open; all 29 tasks and final
full gate remain open.

2026-10-15 exact U32 identities: three-file delta integrated. Numeric operands
retain their exact value through unit multiplication/division, all-ones masks,
self AND/OR, zero OR/XOR and masked-zero shifts. Exact identities remove one
bounds comparison; changed operands retain it and arithmetic/traps still
execute. Five native/full-OOM/replay laws,four executed groups, 244 selected
analyzer files and affected TypeScript pass; Cost Wasm remains exact
11958B/1ddc5f2d… . Pins:
`build/bench/complete-program-20261015/numeric-bit-identities/`. General
selected helper graphs,inference and final qualification remain; all 29 tasks
remain open.

2026-10-15 stored-Memo force facts: two-file delta integrated. The complete
reference-result force body now rederives pending/evaluating/ready states,
actual environment/provider/producer edges,guarded reset and cache-before-ready
order. Callsite cell identity and matching constructor producer remain
mandatory; this read-only fact grants no dispatch or retirement. Root five
native/full-OOM /import/replay laws,eight executed groups and six selected
analyzer files pass. Compiler remains exact
ad2c6702b6e4f435614d1a00def5cfa64316605bcdeee52acd28ecab217c59ae. Evidence:
`build/bench/complete-program-20261015/demand-force-edges/`. State writes and
complete Core/runtime lifetime graph remain; all 29 tasks and final full gate
remain open.

2026-10-15 State write graph facts: two-file delta integrated. Shared checked
lookup retains existing State read behavior; write facts identify the selected
frame,value slot,argument 1 and owning publication,including F32 bits. Root four
native/full-OOM laws,eight executed groups and 245 selected analyzer files pass;
ordinary Cost Wasm remains exact 11958B/1ddc5f2d… . Pins:
`build/bench/complete-program-20261015/state-write-edges/`. Whole-activation
graph composition and qualified ownership replacement remain; no new RC omission
or tracing deletion. All 29 tasks and final full gate remain.

2026-10-15 staging ambient rows: three-file Source repair integrated.
Emit/splice contribute latent effects through the established covariant use
boundary,without changing the stored Code row. Run purity and callback input
rows remain strict. Three native laws/full-OOM,two executed both-tier sync/JSPI
portable/exception groups,affected TypeScript and selected analyzer pass; Cost
Wasm is exact. Pins:
`build/bench/complete-program-20261015/staging-ambient-rows/`. Two existing
named-operation archive neighbors fail InvalidArtifact on both before and
candidate compilers; the separate rank/staging reader repair is held for
capture-parity correction. All 29 tasks and final full gate remain open.

2026-10-15 direct scope/older cell: three-file Source repair integrated. Exact
immediate scope callbacks retain enclosing State installation frames; deferred
closures continue clearing them. Root five checker/full-OOM laws,four executed
groups, 393 selected analyzer files and affected TypeScript pass. A capturing
younger edit specifically rejects capability_escape and recovers
byte-identically. Pins:
`build/bench/complete-program-20261015/direct-scope-state/`. General immutable
lifetime graph remains separate and unfinished. Cost Wasm is exact
11958B/1ddc5f2d…; all 29 tasks and final full gate remain open.

2026-10-15 rank/staging coexistence: corrected seven-file reader/checker union
and isolated scalar-action publication follow-up integrated. Exact future rows,
forall argument effects, provider/handler residuals and closed dictionary
capture footprints validate independently; imported certificates check unused
slots too. Initial root failures were traced to irrelevant effectful
Unit->scalar constructor metadata and repaired by declining that publication,
preserving pure factories. Root seven native/full-OOM laws,eleven both-tier
sync/JSPI guest groups, 446 Zig analyzer files with zero
findings,TypeScript/lint/format and dev build pass. Compiler
9cb9ce2a2b4f50b5ae5ce0dd95b5c18ed6cd3ef2501e33adadf29585b64173d4. Pins/evidence:
`build/bench/complete-program-20261015/rank-staging-coexistence/` and sibling
`rank-staging-actions/`; initial failed logs remain preserved. Earlier
named-operation archive/capture hold is resolved. Ordinary inferred helper
dictionary transport and broader Core forms remain; all 29 tasks and final full
gate remain open. No new runtime performance claim.

### Qualified cohort/runtime and construction-capture prerequisites — 15 October 2026

Root rank/staging coexistence and scalar-action publication fix pass 7
native/fullOOM, 11 guest groups and 446-file zero analyzer; see
`rank-staging-coexistence/`. Late-only bounded cohort helpers/fixture now pass 3
native/fullOOM and 9 direct Wasm protocol groups plus 2 fixture dependency laws.
The owner must outlive all member journal leases; malformed lists, unexpected
retains and premature retirement trap before group liveness changes. Live
outgoing references preserve ordinary RC. No production cohort rewrite is
integrated; ordinary helpers/Source IDs remain unchanged. See `cohort-runtime/`
and `cohort-root-order/`. Source Demand construction proof admits capture-free
delayed work while retaining capability/operation/resource/usage capture guards.
Root 4 native/fullOOM including neighbors and 10 guest groups pass. The two
read-only activation readers pass their combined 7 native/fullOOM; runtime graph
and semantic graph confer no RC authority. Semantic type_same/overloaded-scalar
audit corrections remain required before a consumer. See
`demand-construction-captures/`, `activation-graph/` and
`immutable-lifetime-graph/`. Union analyzer 399/452 files zero; affected TS
passes. Current root dev compiler
c13b051cab335adf1e6b1981cd758a0bde46783d4f604a58b947eb64fa77cbed; ordinary Cost
remains 11958B/1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad.
All 29 tasks remain open. Historical ownership performance, general semantic
coverage and the single final compiler gate remain pending; no commit/release.

The read-only semantic graph witness/dispatch hold above is superseded by
`immutable-lifetime-correction1/`: actual type_same witnesses execute;
overloaded scalar c!=0 declines pending exact implementation proof. Root 3
focused native laws (two allOOM) and 5 selected analyzer files pass. No RC
consumer is integrated. An exact per-scope-root rejection-only immutable guard
is being qualified privately; unsupported paths will grant no completeness or
confinement fact.

`cohort-member-guard/` supersedes the early runtime protocol guard: nested
member checks avoid bit-mask/Boolean AND. A new dropped-pin control fails the
oldfixture and passes the correction. Root 10 direct Wasm protocol groups +3
native/fullOOM and affected TS/analyzer pass. This remains a late runtime
prerequisite with no production consumer; historical CPU gates remain open.
Scope 3 staged above was held before apply after review found whole-context
preflight could reject >65k unrelated nodes; a corrected combined scope freeze
is being qualified privately.

Corrected immutable scope guard is integrated in
`immutable-scope-rejection-corrected/` (combined root d54f78a3...); the held
original Scope 3 stage remains unapplied. Root 10 native laws pass (7 fullOOM),
including 70k unrelated/current-module population and hard shared semantic
budget controls. 16 neighbor guest groups pass. Both scoped_value_flow tiers
fail the same emit type_mismatch under pre-hook ac8 and corrected f19; this
existing emitter defect is being localized, not attributed to the scope guard.
Private final 25-pair compiler CPU controls: ordinary fresh/edit+1.11/-0.51%,
scoped+0.55/+2.07%, equal Wasm. Unsupported scope paths grant no new fact. Full
gate remains deferred; all 29 tasks stay open. See exact qualification pins/logs
in the integrationdir.

15 October 2026 follow-up: corrected inferred dictionary helper 10 is integrated
(root patch f8260274...), with 4 native/fullOOM laws and 19 selected guest
groups. Immutable Scheme owners transport dictionaries through
direct/reference/partial calls; missing data witnesses and exhausted matching
reject. Unsupported key imports decline reuse. See
`inferred-dictionary-helpers/`.

Record shape repair 1 (patch 8fe2e9ac...) fixes the existing imported-container
failure above by exact field names/types with duplicate/missing/budget
rejection. Root 2 native laws and 6 guests pass; private 25-pair same-order
retained CPU+0.11% with byte equality. Reordered baseline rejects, so no speed
ratio is claimed. See `record-code-shape-names1/`.

Semantic emission 6 receipts are integrated (root 804d8788...), preserving newer
dictionary transport and omitting unrelated private cohort prototype tests. Root
1 native/fullOOM and 22 executed groups pass; full 453-file analyzer is zero.
Root dev 334c38e8f4ddee18a1587b4b1ac40cbbf8997252382bca33e95345d8ec17e9a5;
release/lock remain unchanged. Cost stays exact 11958B/1ddc5f2d... . Private
wall control geomean 0.999058 is not a CPU claim: leader-only CPU
instrumentation was invalid. See `semantic-emission/`. No production cohort
consumer, tracing removal, full gate, commit or task completion yet. All 29
remain open.

Numeric remaining-argument slice is integrated in
`build/bench/complete-program-20261015/numeric-remaining-arguments/`. A15-line
reader change retains exact prepared-method operands across further
applications. Root 3 new native laws (2 completeOOM), 3 neighbors and 6 guest
groups pass; selected 251/453analyzer files are zero and TypeScript passes.
Three-argument identity has 0 bounds comparisons; changed final argument
retains 1. Root dev 1f856e8a...; Cost remains 11958B/1ddc... . Initial
call_arity fixture and non-generic direct literal-receiver unsupported lowering
logs are retained, not reported as passes. General helper graphs, all 29 tasks
and final qualification remain open.

Root generic State 6, boundary-reader scale 2 and alias/safety 10 are
integrated: `generic-state-invocation/` patch 71a7b220...,
`immutable-boundary-owner-scale/` patch ce2880ad..., and `member-alias/` patch
cdb6cd27... in the current evidence directory. Root 11 native laws (including
fullOOM), 15 guest groups, 3 TS files and full 453-file zero analyzer pass.
Compiler 524251f1255348f5a5ddbda6bb24c5dc3012f62a5f909832303739d751cb8cfc;
ordinary Cost remains exact 11958B/1ddc... . No task completion or full gate
yet.

Captured-project construction capture repair is now integrated and compatible:
`deferred-named-capture/` patch 56b834bd... separates deferred call construction
from execution/no-store proof, retaining exact owned callees and actual lexical
captures. Root native fullOOM, 8 combined guests and 400 affected-file zero lint
pass. Compiler 0b7fe9e1692a5ea478466c90d08564589ff778f305e38259ba22b99adec04242
passes the unchanged captured project's fresh/edit/revert: 25.493/14.275/13.628s
wall, 70,330 source steps, 11 retained hits/61,383 replayed steps,no retries.
Fresh/revert SHA
24315d616b3785e12d07270bd5295bb92c56563df84229a4b9f744340fe5758a. These are
compatibility checks, not CPU qualification or a speed claim.
`captured-after-capture-repair/` owns the exact compiler/input pins and phases;
`captured-attribution/` preserves failed controls and restored diagnostic
copies. The one-line scalar-global guard now has an independent frozen-Core
fullOOM law; removing only that guard fails independent reconstruction. Exact
root and private controls are in `nonfunction-global-control/`.

The literal selected-method regression is repaired in
`numeric-literal-dispatch/` patch 33e708bb... . A function-result selected call
uses the existing curried reference/apply path. Root 2 native laws (one complete
emission/replay OOM) and both new guest tiers pass; identity removes its bounds
comparison while the changed final argument retains it. Source/archives,
checkpoint,changed callee,trap/recovery and JSPI remain exact. Broader numeric
helper graphs and all 29 tasks remain open.

Private closed-activation cohort 11 is rejected for speed and is NOT integrated.
Thirty balanced CPU 7 rounds pass values and 128 KiB memory but median cycles
ratios are 0.99955 sync/1.00105 JSPI against current, historical totalgeo
1.28443, cycle ratios 1.76635/1.70898 and p95 1.64304/1.61003. Preserve the
immutable private freeze and raw report; grouped pin/list work replaces
collector work without payoff. The next private experiment must remove proved
member lifetime work. The complete-program, exact remote workflow, owner cleanup
decision and final full gate remain required. Keep this handoff and all task
statuses unchanged.

### Latest qualified small sets, 15 October 2026

Root development compiler
cebe3efd38ce72a26f9ef8dacc57d30ab0d7c510d5fef1f4f508c15677f76434 includes
demanded-body receipts and effectful returned-closure row repair.
`body-demand-receipts/` owns 4 files: 2 native laws/2 neighbors, completeOOM, 2
new guest tiers plus 4 loop/path neighbors, 400 affected analyzer files zero.
Five paired development screens: 128 demanded-body edit/revert 160/150→120/120
ms, elaborations 130→2; population 120→160 ms. Plain retained controls 100→100
ms. Exact 60 phase bytes and results; process CPU resolution 10 ms. No
general/release speed target claim. Binary demand rewrites and unsupported
effect rows decline.

`effectful-method-closure/` integrated patch 4f996bd8... repairs covariant
returned-function rows while keeping callback parameters invariant and exact
selected operation identities/instances/arguments. Independently closed declared
rows may use the existing conservative source-view relation. Root 3 native laws
(2 completeOOM), 16 guest groups, 256 affected analyzer files zero, 3 TS files
pass. Ordinary Cost stays 11958B/1ddc... . Stored unknown-forall dictionary
forwarding remains an explicit private frontier, not an ambient/witness
fallback.

`captured-after-demand-rank/` passes the unchanged captured inputs after both
repairs: 25.038/14.032/13.466s wall,exact same fresh/edit/revert hashes as the
previous captured repair, 70,330 steps, 11 hits/61,383 replays,no retries. This
is combined compatibility only. Final full gate, release/historical/compiler
performance qualification and all 29 tasks remain open. Private ownership region
and iterator-step work continues; no production cohort hook is applied.

Nested callable reuse is repaired in `nested-callable-reuse/` patch 65450b87...
. An outer fragment includes nested callable records; each record now checks its
own exact job owner, function and callable layout. Invalid owner/layout controls
decline without changing fresh output. Root 1 native/completeOOM, 26 guests and
112 affected zero-finding analyzer files pass. Compiler 5530630c... preserves
ordinary Cost 11958B and all captured phase hashes. The unchanged captured
project now reuses 1152 named+369 closure fragments, recovering 489 declines;
remaining declines 240. Fresh/edit/revert wall 25.023/11.782/11.287s versus
25.038/14.032/13.466s before. This single wall screen is not CPU qualification.
See `captured-after-nested-callable/`. All 29 tasks and final gates remain open.

Immediate collection-step sinks are integrated in `immediate-collection-step/`
patch b28e8205... . Exact pure cursor producer/constructor and a single adjacent
pattern permit emitting the original has/value/advance operations directly.
Saved/captured steps, unknown/effectful dispatch and packed rows keep fallback.
Root 3 native laws/completeOOM, 5 guest groups and 111 affected zero-finding
analyzer files pass; compiler bd7cab47... keeps ordinary Cost exact 11958B. The
private Windows screen removes 2 allocation sites and 4 publications,
18412→17846B Wasm. Tiny wall samples are diagnostic only. Remaining
successor/adapter state, all-width packed comparisons and final qualification
keep 047 open.

Resource callback-result footprints are integrated in `resource-scope-result/`
patch be149e10... . A scalar resource wrapper can return a closure retaining an
older live effect owner; younger owners, the fresh resource loan, cleanup stores
and unknown sinks still reject. Immutable Core reconstructs actual acquisition,
callback and cleanup order with shared proof budgets. A cleanup failure retains
the result graph while marking the report incomplete. Root 3 native/fullOOM, 9
guest groups and 400 affected zero-finding analyzer files pass; compiler
70e345b8... keeps ordinary Cost exact 11958B. General resource/lifetime forms
and final gates remain open.

All-dirty module cutoffs are repaired in
`build/bench/complete-program-20261015/all-dirty-module-cutoff/`, patch
1103c1a8... . A leaf edit may dirty every dependency while preserving public
interfaces; the mixed checker now offers those ordinary semantic comparisons
even without an already reusable dependency. An opaque 3-module screen reuses
both callers, reducing fallback elaborations 5→3; executable values 42→43→42 and
fresh bytes remain exact. Root 1 native/completeOOM, 10 guests and 19 affected
zero-finding analyzer files pass. Source/archive/checkpoint, invalid signatures
and recovery pass in both tiers and sync/JSPI. Compiler dc7c3149... keeps Cost
exact 11958B. This is a work-counter result; tasks 024/053 and the final gates
remain open.

Nongenerative user-effect callback rows now retain complete family/member
recipes and exact producer-origin/alias reads in `body-user-effect-rows/`, patch
db78cbc8... . Frozen operation identities relocate through their own validated
map; function/Demand row arguments retain their reads. Invocation,
scoped/generative and unsupported recipes remain ordinary. Root 8 native laws, 4
complete allocation sweeps, 6 guest groups and 400 affected zero-finding
analyzer files pass. Source edits use 4 versus 5 fresh elaborations; archives
preserve exact execution without a demonstrated work reduction. Compiler
f8b5818c... keeps ordinary Cost 11958B. No CPU/general-cutoff or final-gate
completion is claimed.

The separate append-only symbol-prefix experiment was rejected and all 4 files
restored byte-exact: `growing-symbol-cutoff/`. Its reuse assertion still fails.
Read-only attribution identifies extra inert local slots in the positional
principal binding table; broader normalization needs its own complete proof.

Local cursor successor families are integrated in `local-cursor-successors/`,
patch 64f04180... . Exact nonescaping ordinary Array/List cursor versions keep
collection/index/leaf/base in locals and materialize an immutable header at an
actual return or aggregate escape. Calls, captures, merges, unknown producers
and packed rows retain fallback; already selected whole-loop families remain
separate. Root 3 native laws/completeOOM, 11 guest groups and 111 affected
zero-finding analyzer files pass. Compiler 2ebd8b48... keeps ordinary Cost exact
11958B. The private fork screen removes 2 allocation sites without changing 7
publications. The width1 packed comparison still regresses against boxed/task
002 references; typed ownership publication is being attributed before any
all-width run. This regression predates the successor change: its width1 Wasm is
byte-identical to the prior immediate-step compiler. Task 047 and final
qualification stay open.

A separate bounded principal-suffix proof is now qualified in
`inert-principal-slot-cutoff/`, patch 984c6ff5... . Old symbol IDs still require
exact spellings/producers; new spellings may append. Shared binding slots and
every other principal field remain exact. Only canonical inert local/parameter
suffixes may differ, after validating the truncated principal to reject any
reference into omitted slots. An opaque leaf's last function can add/remove a
private local while both callers retain semantic reuse. Earlier insertions that
shift shared slots still decline; no interface compaction/remapping is
attempted. Root 3 native laws/completeOOM, 10 guest groups and 56 affected
zero-finding analyzer files pass, including source/archive/checkpoint, signature
failure/recovery and both tiers/sync/JSPI. Compiler 42dff30d... preserves
ordinary Cost 11958B. These work counters do not complete 024/053 or establish
the general edit CPU target.

Principal suffix validation is hardened in `principal-local-target-bounds/`,
patch 716d2e2b... . The shallow validator now bounds proof-header bindings and
self-unit external/implementation/selected-member/predicate targets before a
cutoff can omit slots. A forged proof-header reference passed the earlier
comparison; the preserved Debug counterexample now rejects. Root 8 native laws,
22 guest groups and 60 affected zero-finding analyzer files pass. Compiler
dc4c6b84... keeps cache-disabled ordinary Cost exact 11958B. No format or
authority expansion.

The combined source through the original suffix proof preserves all captured
fresh/edit/revert hashes in `captured-after-principal-cursor/` (compiler
42dff30d...). It retains 70,330 source steps, 11 constant hits/61,383 replayed
steps and no retry. Wall 25.302/11.854/11.414s is compatibility evidence only.
The independent fresh configure audit also matches the current root compiler
identity; sharing one symlinked Zig configure cache across private roots is not
a supported evidence setup. Private controls now use separate local caches.

Current combined compiler is f4d5c9a9... . Unreferenced local principal suffixes
are normalized in `principal-local-suffix-normalization/`, patch cca2dc62... .
Both earlier/later private function edits retain caller reuse despite shifted
inert parameter/local markers. Remaining bindings, catalogs, graphs and exports
stay exact; no persisted format or binding remap changes. Proof headers, usage
binders, self/unit0 targets and local shared-callee predicates cannot reference
omitted slots. Foreign predicates require exact retained external aliases. Root
8 native/3completeOOM, 25 guests and 266 affected zero-finding analyzer files
pass. An initial overbroad bounds rule and the unrelated rank-row repro are
preserved separately. General edit CPU and the final gate remain open.

Finite numeric qualification is integrated in `numeric-finite-qualification/`,
patch 244fa5be... . Current bounded summaries already compose nested selected
helpers/returned closures; old general-inference notes are not new requirements.
The production correction reports consumed Plan.visits before copying a return.
Root 3 native/fullOOM and 8 guest groups pass. No-feature proof work/allocations
are 0; the composed case uses 385 visits/2144B peak, and 256 requirements 4902
visits/44620B peak. Private 25 balanced CPU pairs are near parity (proof
fresh/edit 1.003/1.001), not a speedup. Final combined/release qualification
still keeps 070/071 open.

Empty scalar lexical frames are eliminated in `empty-lexical-row-frames/`, patch
3993478d... . Fresh executable CFG proves every action/path acquires and
publishes no owner. Public invocation frames, resource drains and collector
boundaries remain. The optimizer now invalidates when a cleanup drain appears;
the preserved mutant exposed stale body reuse. Root 3 native/fullOOM, 29 guests
and 266 affected zero-finding analyzer files pass. The exact root width1 Wasm
matches the privately timed candidate: fold CPU 0.133625→0.0105 ms (12.7×), 31
paired samples. Cursor speed is unchanged. All-width, compiler-cost and final
047 gates remain.

The older quantified-row dependency regression is repaired in
`rank-row-scope-repair/`, patch 32f82098... . An exact closed Foreign callback
read through an unowned inference tail now publishes closure after the whole
endpoint matches. Generic/formal/wider ambient rows retain their separate owner
checks; failed payload matches publish nothing. Root 5 relevant
native/2completeOOM laws, 9 guest groups and 266 affected zero-finding analyzer
files pass. All four slices preserve cache-disabled ordinary Cost exact 11958B.
Full gate/release/performance and all 29 task completion claims remain pending.

The combined compiler f4d5c9a9... passes captured fresh/edit/revert in
`captured-after-finite-repairs/`: wall 25.377/11.902/11.419s, 70,330 source
steps, 11 constant hits/61,383 replayed steps, 1152 named+369 closure reuses and
240 declines. All 415 inputs match before/after. Fresh/revert bytes agree; bytes
legitimately change from the earlier compiler after empty-frame optimization.
These are compatibility observations, not CPU/release qualification.

Compiler 0c17e2de... adds `static-operation-body-receipts/`, patch 73c393da... .
Static unparameterized operation bodies reconstruct exact current targets from
owned family/origin/signature reads; parameterized/scoped/State recipes decline.
Eight native laws, capture/replay/fullOOM, six selected guests, TypeScript and
shared 402/455 zero-finding analyzer files pass. A 5-pair combined development
screen cuts 128-body edit/revert 240/250→110/110 ms and elaborations 130→2;
fresh population 220→240 ms, plain controls unchanged. The metric is
whole-process CPU at 10 ms resolution; no isolated or release claim. A first
invalid duplicate-name control was corrected to a legal
renamed-family/global-shadow program.

The same compiler integrates `persistent-cursor-borrows/`, patch d5e71f05... .
Fresh CFG proves a real persistent owner covers exact copied row values; calls,
writes, missing/bypassed owners and uncertain provenance decline. Root 3 native/
fullOOM and 4 guest groups pass. Array root Wasm exactly matches timed
59b837...; 16384 rows retain/release 16385→1 and CPU ratios .388 sync/.372 JSPI,
31 balanced pairs. List leaf-cache and old tracing packet paths still decline;
task 047 stays open. The compiler-cost control is being completed in bounded
sets, without rerunning finished samples.

`region-forall/` is test-only, patch 7336d28e... . Current compiler already
accepts the annotated region-polymorphic borrow reader. Two root groups pass
both tiers, source/archive/checkpoint, independent owners, actual JSPI await,
invalid loan escape, host cleanup and producer edit/revert. No production
feature was added. Ordinary Cost remains byte-exact11958B for all three slices.
Task status/counts, the final full gate, release, remote CI and owner cache
decision remain open.

The cursor compiler-cost control is now complete: 20 pairs each, ordinary
retained CPU+1.09% and finiteArray+2.53%. Fresh medians are 10 ms-quantized, not
zero-cost proof. One 60s cap preserved 43/80 samples; one bounded continuation
collected only the missing 37. Exact followup freeze is
`/var/tmp/blot2-cursor-owner-20261015/build/bench/persistent-cursor-borrows-followup-final-20261015/`,
pins 523e8059... . List helper 949 instructions are attributed read-only; no
call authority was added. All jobs are reaped.

`affine-forall/` adds one test only, patch 4671ec0e... . Existing 0c17 compiler
accepts `forall[a] => unique a -> unique a` across source/archive/checkpoint,
actualJSPI suspension, host cleanup, edits/revert and exactuse_after_move
rejection. Two root groups and TypeScript/lint/format pass. The earlier
generic-shared screen omitted this explicit affine contract; no production
change was necessary.

The 15 October final combined gate supersedes the historical open 29-task counts
in earlier focused updates above. Current counts and frozen qualification are at
the top: 070/071 complete, 27 tasks open. The next work should establish a
current failing acceptance case or measured bottleneck before implementation;
old scope/rank/cleanup checkpoint exclusions are not current defects by default.
