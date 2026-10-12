# Continue here

Work follows [tasks/README.md](tasks/README.md): finish the in-progress item
below, then take ready tasks in the order given under "Next work". Use Zig
0.17.0 (`zig version` before each build batch). Before every compiler commit run
`deno task test:compiler` and
`ZIG_ANALYZER=build/tools/zig-analyzer/zig-out/bin/zig-analyzer deno task lint:zig`
(zero findings required). Each task gets an implementation commit and a record
commit (task file, README index, durable record under `zig-native/`). Nothing is
pushed; keep it that way unless the owner authorizes it.

## Qualified state

Latest compiler implementation on local `main`: `2689ad5`. Qualified milestones,
each with a durable record:

| Task                                           | Implementation       | Record                                                       |
| ---------------------------------------------- | -------------------- | ------------------------------------------------------------ |
| 048 Dispatch explanations                      | `67e7912`            | [DISPATCH_EXPLANATIONS](zig-native/DISPATCH_EXPLANATIONS.md) |
| 026 Resolved structured flow                   | `ae908fa`            | [RESOLVED_FLOW](zig-native/RESOLVED_FLOW.md)                 |
| 027 Ownership roles in the IR                  | `c226967`            | [OWNERSHIP_ROLES](zig-native/OWNERSHIP_ROLES.md)             |
| 097 Partial collection shapes and fixture gate | `f2b41b4`, `881c6ab` | [PENDING_SELECTIONS](zig-native/PENDING_SELECTIONS.md)       |
| 099 Stage-chain rejection                      | `5340ef2`            | [STAGE_CHAIN_REJECTION](zig-native/STAGE_CHAIN_REJECTION.md) |
| 096 Native typed asset imports                 | `0c5be56`            | [NATIVE_ASSETS](zig-native/NATIVE_ASSETS.md)                 |

095 is implemented at `4eabecb`
([PROJECT_PROTOCOL](zig-native/PROJECT_PROTOCOL.md)); 049 at `d7e2b89`
([EDITOR_COMPLETION](zig-native/EDITOR_COMPLETION.md)).

Earlier today: 025 (resolved calls), 088–092, and progress on 093 (gdev retained
edit 570 → 440 ms; see the task file). Every public example, the synthetic
corpus and the frozen gdev copy still emit byte-identical Wasm at `544c5c6`
(gdev SHA-256 `3158216b…def0`, 840,534 bytes).

Tasks added today: 094 (locate specialization failures at the caller's use), 095
(versioned project protocol), 096 (native typed asset imports), 097
(`Array.iter` with an unconstrained element type), 098 (recursive demand
forwarding does not type-check; one law skipped), 099 (compiler crash on long
stage chains).

## Current work (12 October 2026)

The owner explicitly requested continuing until the entire task program is done.
The active goal covers all remaining tasks, not just 095/097. Nothing is pushed.

1. 097 is complete: the remaining blocked split-hauling module compiles and
   passes 12 exports/25 assertions. The current regular gdev suite passes all
   472 cases across 54 modules. Public stage-chain steps drop from 974,824 to
   269,363 with identical type graphs/Wasm; 100 stages compile, 101 reject under
   the unchanged inference budget. See PENDING_SELECTIONS.
2. 095 is complete: explicit version-one admission and independent raw-wire
   conformance. The jointly qualified compiler gate passes native tests and 690
   guest/client tests. Analyzer is zero across 318 files, including three
   unregistered 096 files under development.
3. 049's durable completion contract and 050's implementation are complete.
   Native queries, client, LSP and actual Helix acceptance are qualified at
   `2226d50`; see EDITOR_COMPLETION.
4. **096 is complete at `0c5be56`.** Full native/compiler gate: 743 guest/client
   tests; analyzer: 318 files, zero findings. Native imports match the frozen
   game's Wasm/snapshots/dependencies through source/asset edits and recovery.
   Current gdev passes all 472 regular cases and 12 split-hauling exports.
   Resource handles and tunables are covered separately by public laws. See
   NATIVE_ASSETS for reader limitations and measured host/child CPU.
5. **028/036/094/098 are complete at `b068dc9`.** The full native gate and 763
   guest/client laws pass, including all eight unchanged allocation budgets.
   Analyzer: 323 files, zero findings. Seven alternating release pairs preserve
   Wasm, diagnostics and old semantic counters across public, synthetic and
   native-asset phases. CPU is mixed; no overall speedup is claimed. Candidate
   SHA-256 starts `8a7dd393`; durable pins and medians are linked from
   RESOLVED_BODIES. Current captured gdev: 55 modules, 482 fixture cases and
   1,460 assertions; split hauling: 12 exports and 25 assertions.
6. **030 and 042 are complete at `d021c57` and `a1df44d`** (SHARED_OWNERSHIP and
   RAGGED_BUILDERS). 031 is complete at `cb41a6d`: native suite, 771
   guest/client laws, all eight unchanged allocation budgets and zero analyzer
   findings across 327 files. Its costs and remaining memory counterexample are
   recorded in SHARED_RC. Persistent-root work (032) continues in
   `/var/tmp/blot2-shared-rc`. **043/050 are complete at `2226d50`:** joint
   native gate, 807 guest/client laws, eight unchanged allocation budgets, zero
   findings across 336 Zig files. Ragged and completion measurements/limits are
   recorded in RAGGED_BUILDERS_QUALIFICATION and EDITOR_COMPLETION. The current
   gdev corpus has moved to pen settings with native asset roots `src` and
   `devtools`; the ignored fixture harness now matches those roots. Its
   captured-input sweep passes; early attempts with the obsolete one-root
   harness are failures, not compiler regressions.

7. **051 is complete at `879a508`** (MODULE_ABSTRACTION). Public-by-default
   compatibility, selective forwarding, private constructors, stable opaque
   identity, public semantic/ABI/private executable views and wrapper-erasure
   laws are settled. 052 is ready; no new visibility behavior is implemented.

8. **029/032/037 and bpm are complete at `2798ff9`.** The corrected staged tree
   `6064c8e2d114bfb39ab3c78d5c0b295f51f1be15` passes the full native gate, 844
   guest/client laws, all eight unchanged allocation budgets and zero analyzer
   findings across 339 files. Release SHA-256 starts `b8023659`. Seven
   alternating public/synthetic pairs preserve semantic counters and
   fresh/retained/restart parity; public CPU ratios are 0.990–1.011 and peak
   deltas are zero. Ownership helpers intentionally change public Wasm. The
   failed `9142c5f0…` candidate remains separate. Durable final evidence is in
   PERSISTENT_ROOTS, SYMBOLIC_BODY_REUSE and LOCAL_MEMOS_QUALIFICATION.
9. **052/033/038 and the reviewed 054 specification are complete at `f184dde`.**
   Qualified tree `1431522db1bd9b93b1e0b3f3f69949e2122aa5e6` (compiler inputs
   `310d60ce85a8ebe26f3c9f4d48fc35811fd98a94`) passes all 1,400 native and 871
   guest/client laws, all eight unchanged release budgets and zero analyzer
   findings across 343 files. Accepted LLVM release SHA-256
   `5c689ad5caad6952f1c4643f5c40e10d6e41bcf819bf016f751ac105d82020a1` is
   immutable under `build/bench/joint-052-033-038-054/final/`. Regenerated
   host/editor tooling passes. Seven cold public pairs show CPU +0.4–2.9%;
   synthetic fresh/retained/restart output is identical. No overall speedup is
   claimed. Rejected compilation, allocation, privacy/local-name and stale
   wire-test attempts stay separate in the durable integrated qualification.
   038's scalar callback fixture removes heap/table storage and allocation
   traffic. 033's sync scalar host-call overhead remains +89.4%, about 262
   ns/call; task 035's final CPU gate remains open. See
   MODULE_ABSTRACTION_QUALIFICATION, KNOWN_CALLBACK_MEMOS, SUSPENDED_OWNERSHIP
   and ASSOCIATED_CONTRACTS. Nothing is pushed.

10. **002/034 are complete at `dd6a66a`.** Qualified staged tree
    `a70662ea5a3efa27e8ce3c4c03ad2b7484bb2ae3`, standard LLVM Fast release
    `c0959e9a375b2ba8d2a2263278417fb917b434e733c9a13f80af1d372e80b060`, passes
    the full native suite, 892 guest/client laws, eight unchanged budgets and
    zero findings across 344 Zig files. Three additional complete merged F32
    fold batches retain all 31 widths and close the boxed gap (worst paired
    medians 0.994328 records / 0.994013 tuples). Seven cold public pairs have
    CPU ratios 0.99685–1.01527 and zero peak deltas; synthetic fresh/retained/
    restart bytes are identical. No general compiler speedup is claimed. Cyclic
    ownership reclaims the measured finite-loop workload from 5,373,952 to
    131,072 committed bytes, with about 14% additional cycle CPU. Cursor costs
    remain assigned to 047; tracing and final CPU acceptance remain 035.
    LIST_TRAVERSAL and CYCLIC_OWNERSHIP_QUALIFICATION preserve exact pins,
    commands, lifecycle costs and limits. Nothing is pushed.

11. **039/055 are complete at `46bf8b9`.** Qualified implementation tree
    `cfdd18a616412e3416a5169ea18dec38cf67ec28`, compiler source
    `d96b286cbaa67afa5dc2bc24cc0469776e6fbd6a`, standard LLVM Fast release
    `47021c966f75fbb6063b9de52d476fe944a8aa16dc6bc47aeae66cfbf4dd9095` passes
    the full native suite, 914 guest/client laws, all eight unchanged budgets
    and zero analyzer findings across 348 files. Regenerated host/editor tools
    pass. Demand reports have independent raw-wire/default/byte-equality
    controls; three complete chain batches through 256 operators have zero
    demand storage and Memory/table, guest ratios .9510–1.0117 to explicit
    controls. Associated equations/equality/origins/declared rows and storage
    diagnostics pass through source/artifact/restart/OOM. 024/035 partial slices
    are also qualified here, including complete closed-row receipts and the
    separate root-frame demand cache input. Deep retained edits are about 29–30%
    faster; population/RSS rise, cheap-body wall +3.8–7.2%, public CPU
    .9884–1.0227. Tracing removal and its failing CPU gate remain open. See
    FRONTEND_OWNERSHIP_QUALIFICATION, DEMANDS, ASSOCIATED_TYPES_QUALIFICATION,
    BODY_CUTOFF and TRACING_REPLACEMENT. Initial strict pointer-snapshot and
    stale raw-wire fixture failures remain preserved. Nothing is pushed.

12. **040 is complete at`2689ad5`.** The combined024/035/040 tree
    `92e09418c4449fd772c0037ead43cd922e51fb6a`, compiler source
    `497069ed0c61181232520acdb249b35828334ae1`, standard LLVM/Fast release
    `9ea894d41e157824dd951e5f92827284da98c59af47c8b5831ebd04623688b21` passes
    the full native suite,925 guest/client laws, all eight unchanged budgets
    and349 analyzer files/zero. Checked named consumers and small row
    compositions eliminate temporary scalar boxes; widths/order/escapes/effects,
    source/artifact/checkpoint edits and OOM pass.31 paired100,000-row samples
    give named/composed guest CPU ratios .0212–.0521; committed memory is
    unchanged. Public compile CPU .9946–1.0501, peak deltas zero, teardown zero;
    synthetic fresh/hot/restart bytes equal across compilers.024 also adds
    shared/portable/annotation receipts;035 adds final flag lowering and compact
    one-marker journals. Their broader scope and CPU gates remain open. Exact
    pins and limitations are in ROW_FUSION, BODY_CUTOFF, TRACING_REPLACEMENT and
    `build/bench/joint-024-035-040/qualification-pins.json`. Nothing is pushed.

13. **044's design is complete at`20ef28d`.** ROLLING_SUMMARIES specifies
    ordinary ordered fold/monoid/group windows and opaque persistent summary
    trees with build/get/query/set/concat, explicit caller algebra, precise
    pull/trap/F32 order, persistent snapshots and callback/storage bounds.
    Markdown/link and independent U32/F32/noncommutative trace checks pass. It
    adds no executable API or optimization;045–046 remain separate work.

## bpm tangent

The owner requested Git packages, caching, `blot.json`, package exports in
`blot-workspace.yaml`, and an optional prelude. Their explicit choice is:
**omitted prelude means no prelude**. The committed manager supports local/Git
dependencies, transitive exports, exact lock pins, frozen installs, updates and
clean-cache validation. Twelve focused package/CLI laws, standalone API checks
and the full compiler gate pass. No package is published. See
[packages](compiler/packages.md).

## Next work

The owner wants the entire program finished. Continue past the current batch;
partial milestones do not close broader tasks. Root owns one combined full gate;
agents use focused checks/screens, with no redundant full gates or main edits.

- **024 remains active.** The qualified immutable admitted floor and corrected
  row receipts are on main. Final-floor LLVM costs use the exact `47021c…`
  binary, seven alternating CPU6 pairs, 20 hot edits and preserved execution/
  per-binary byte parity. Report:
  `build/bench/frontend-body-reuse/final-floor-llvm-qualification.json`.
  Shared-callee and source-qualification deltas were frozen separately at
  `build/bench/frontend-body-reuse/shared-callee-followup.patch`
  (`d321d502…fff507`) and `source-qualification-followup.patch`
  (`40d36505…35fd`). Imported origin reconstruction now uses existing portable
  principal/Core facts; producer edits additionally need an independent body
  offer after seed rebuild, with whole-module/entry cutoff disabled. These and
  applied annotation/constructor recipe reads are qualified at`2689ad5`. Current
  captured93-unit attribution identifies blocks/cases as50 of53 offered syntax
  declines and substantial backend cost. Bounded scope/case ownership is now
  isolated work; preserve lexical/mutation/join evidence. General
  forms/relocation and the under-100-ms target remain open; 053 still waits.
  Agent `/root/demand_summary_036` owns it.
- **035 remains active.** Main qualifies checked scalar/reference results,
  complete/rootless admission, immutable variants, scalar stores and separate
  frame-demand cache validity. The frozen flag-only follow-up is
  `build/bench/tracing/flag-lowering.patch`, SHA
  `74992378c8264413ac929f503fa529bd0ea4e911214b968a66731869038ae5c0`. It lowers
  immutable complete guards only after final admission, preserving symbolic
  captures and changed-admission replay. Flag lowering and compact single
  eight-byte frame markers are qualified at`2689ad5`. Their separately pinned
  cycle comparison is about4.9× tracing. The five-line null-environment closure
  descriptor slice is frozen separately at
  `build/bench/tracing/static-descriptor-ported.patch` (`f9c8ff03…23239`),
  ported on`2689ad5` in`/var/tmp/blot2-tracing-next-035`. It removes four
  objects per cycle in its measured control but remains about4.05–4.23× tracing.
  A weak journal-drain batching experiment was rejected. A scalar-result slot
  experiment regressed JSPI controls and was rejected. Prioritize removing
  redundant frames/slots using checked lifetimes; preserve nested memory,
  cycles, escape/suspension/cancellation and raw fallbacks. Agent
  `/root/resolved_body_028` owns it in `/var/tmp/blot2-tracing-035`.
- **040 is complete**, with isolated worktrees and failed prototypes preserved.
  Root owns041 in`/var/tmp/blot2-numeric-simd-041` on`babf57a`. Bounded
  private-local definitions and pure lexical block/return proofs pass focused
  native checks; the actual source pipeline now shows vector stores. Further
  numeric row shapes, guest/cost controls and combined qualification remain. Its
  first guest fixtures used a missing build directory and an unsupported
  effectful generator; corrected controls pass in both tiers. The test helper
  now uses system temporary directories, avoiding a release-build prerequisite.
  044's ordinary API design is committed;045/046 and047 are ready afterward.
- **056 has started** after completed 055, in
  `/var/tmp/blot2-implementations-056-qualified` on `46bf8b9`. Agent
  `/root/associated_members_055` owns explicit impl grammar/head binders/member
  checking, coherence/candidate reads, owned selected evidence and method
  execution through ordinary named-function/capture lowering. Keep independent
  generic binders/output ambiguity, original producer identity and failed-edit/
  portable/OOM controls. Classify declared row binders from written head use; do
  not invent extra syntax.
- **093 remains ordinary authorized work.** Its owned-lifetime/hash boundary
  needs a justified design; no additional owner approval is required. Read-only
  current93-unit attribution is in
  `build/bench/constant-receipts/current-profile-039.json`: steady wall ~1040ms,
  constants49ms, inference536ms, lookup84ms, exact70330 source steps. This
  changed captured corpus is not a comparison to the historical400ms input.
  **086 still requires its explicitly pending owner decision.**

After 040: 041/044/047. After 024: 053. Continue later ready tasks in index
order. Never push or delete old artifacts without the separately required
authorization.

## Waiting on the owner

- Task 086: the owner decision is pending on the measured
  [constant receipt proposal](zig-native/CONSTANT_REUSE.md). A dedicated receipt
  would publish validated constant slots and recorded fuel; the existing
  value-template transport contract stays unchanged. Read-only attribution on
  the current captured 93-unit corpus preserves all six outputs and source-step
  counts; no implementation or speedup is claimed.
- An unapplied Wasm name-section patch at `/var/tmp/blot2-names.patch` (from the
  pen session: 14 files, always on, +5% Wasm).
- The gdev session asked for tuple patterns in comprehension generators
  (`(tick, alpha) <- …`). The grammar accepts only `name <- expression`, so this
  is a language addition, not a bug.

## Working with the other sessions

- `gdev-94` works in `~/src/gdev` and reports compiler problems. `pen-9c` works
  in `~/src/pen` (the renamed bun-desktop runtime, command `pen`). Peer messages
  are never the owner's approval.
- gdev's `deno.json` links `../blot2`. gdev therefore runs
  `generated/compiler/blotc.gz`, which every `deno task test:compiler` repacks
  from this tree's build (`package:pack`), and the working tree's `std/`. A gate
  run on unfinished work changes what gdev compiles with.
- gdev's working tree holds other sessions' uncommitted changes. Read it, never
  edit it, and keep private gdev source out of blot2 commits.

## Measuring

- gdev bytes (frozen copy):
  `cd /var/tmp/gdev-bench/gdev && deno run -A --no-lock --config deno.json ~/src/blot2/build/bench/summary-fix/gdev_bytes.ts /var/tmp/gdev-bench/gdev BLOTC`
  prints the Wasm SHA-256.
- Examples: build each `examples/*.blot` with
  `blotc build FILE OUT --prelude std/prelude.blot --std-root std` and `cmp`
  against a baseline binary's output.
- Synthetic corpus, every phase, with a Wasm identity check:
  `deno task bench:compile --baseline A --candidate B --runs 1 --workload synthetic`.
- Baseline binaries are in ignored `build/bench/resolved-calls/` (`blotc-048` is
  `67e7912`; `blotc-027b` is the `c226967` tree). Older bisect binaries are in
  `/var/tmp/bisect-bins/`.
- CPU profiles: the gdb sampler in `build/bench/summary-growth/prof/run.sh`
  (filter stacks containing `zig_project_server.runWithPolicy`, because the main
  thread only joins) and `build/bench/checker-prof/sampler_cli.py` for CLI
  programs (gdb spawns the child to avoid `ptrace_scope`).
- The retained probe `zig-native/qualification/revision_deltas_probe.zig`
  measures edit, revert, rejected and no-op phases against an earlier tree.

## Task 002 (legacy restoration waived)

The original packed-List benchmark artifacts and the frozen gdev snapshot
matching `scripts/bench/gdev-manifest.json` are missing. On 11 October the owner
waived restoring legacy artifacts. Qualify current reproducible workloads;
correctness and all-width performance remain required. Commit `65dccda` holds
the current List lowering; F32 folds are within 0.6–1.7% of boxed at widths
14–16. Rerun on a quiet host with
`scripts/bench_list_traversal.ts BOXED NEW std OUT record|tuple 16 f32`. See
[the measurement record](zig-native/LIST_TRAVERSAL.md#word-positions-at-leaf-boundaries-9-october-2026).

## Notes

- Compare allocation release to release; debug `blotc` reports about 10% less
  requested allocation than release.
- The analyzer is built at the CI pin `756bfd5` in ignored
  `build/tools/zig-analyzer`; it reports zero findings across 315 files at
  `5340ef2`.
- Seventeen source files whose inline tests were never registered in
  `zig-native/src/tests.zig` were added there in `c226967`. A new file with
  `test` blocks needs its own `_ = @import(...)` line, or its tests never run.

- Test iteration: no-LLVM native compilation is about 8 seconds, and the cached
  1,279-test artifact passes (1,278 plus one skip) with a 256 MiB stack. Its
  full execution takes 16m47s; keep the faster-executing LLVM default. Direct
  cached LLVM and no-LLVM fallback laws overflow their default 16 MiB stack but
  pass at 256 MiB. A measured `Compile.stack_size` focused-test option is a
  possible side quest; it is not implemented. Exact pins and per-test records
  are ignored under `build/bench/test-iteration/`.

- Iteration policy: agents hand off focused native/OOM/guest checks and measured
  evidence; root runs one required full compiler/analyzer gate on the combined
  commit-ready batch. Use no-LLVM focused builds when execution remains short;
  full native validation keeps LLVM. A timing pass of the cached 1,353-law LLVM
  native suite took 298 seconds, all passed. Largest cases: typed-path OOM 82 s,
  partial-runtime OOM 27 s, request-backend OOM 19 s. Raw timings are ignored in
  `build/bench/joint-043-050/native-durations.json`; optimize these with
  preserved failure coverage before adding more repeated full gates.

- Allocation screens use Fast/no-LLVM builds with the production allocator, with
  a separate output prefix. Debug uses a different allocator and cannot
  establish release allocation deltas. The corrected incoming screen matches
  LLVM requested bytes exactly; accepted candidates still use the standard LLVM
  release command and full compiler gate.
