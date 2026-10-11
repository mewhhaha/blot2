# Continue here

Work follows [tasks/README.md](tasks/README.md): finish the in-progress item
below, then take ready tasks in the order given under "Next work". Use Zig
0.17.0 (`zig version` before each build batch). Before every compiler commit run
`deno task test:compiler` and
`ZIG_ANALYZER=build/tools/zig-analyzer/zig-out/bin/zig-analyzer deno task lint:zig`
(zero findings required). Each task gets an implementation commit and a record
commit (task file, README index, durable record under `zig-native/`). Nothing is
pushed; keep it that way unless the owner authorizes it.

## State on 11 October 2026

Latest compiler implementation on local `main`: `b068dc9`. Qualified today, each
with a durable record:

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

## Current work

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
3. 049's durable completion contract is complete; 050 is ready. The contract
   describes a proposed native query and Helix LSP bridge, not an existing
   feature.
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
6. Reviewed specifications 030 and 042 are isolated in
   `/var/tmp/blot2-ownership-design` and `/var/tmp/blot2-ragged-design`. Their
   implementations are under qualification in `/var/tmp/blot2-shared-rc` (031)
   and `/var/tmp/blot2-ragged-builders` (043). Root's private editor probes,
   generic evidence fitting and shared project-query budget are in
   `/var/tmp/blot2-editor-completion` (050); protocol/client/LSP remain
   unfinished. None is qualified or complete. The current gdev corpus has moved
   to pen settings with native asset roots `src` and `devtools`; the ignored
   fixture harness now matches those roots. Its captured-input sweep passes;
   early attempts with the obsolete one-root harness are failures, not compiler
   regressions.

## Next work

Record the reviewed 030/042 specifications and continue 031, 043, 050, 029, 037
and the remaining ready tasks. 028's read-only architecture map is
`build/bench/resolved-bodies/design.md`. Still open: 024 and 093; 002's current
traversal gates; 086's value-template boundary. The full inventory is in ignored
`build/bench/program/remaining.md`.

## Waiting on the owner

- Task 086: reusing constant evaluation means publishing constant slots and fuel
  from receipts, which crosses the documented value-template boundary.
- Task 093: the module-stamp integrity re-hash (~39 ms per gdev edit) is
  deliberate; replacing it with owned lifetimes is a design decision.
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
