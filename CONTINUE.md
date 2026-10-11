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

Latest compiler implementation on local `main`: `5340ef2`. Qualified today, each
with a durable record:

| Task                                              | Implementation | Record                                                       |
| ------------------------------------------------- | -------------- | ------------------------------------------------------------ |
| 048 Dispatch explanations                         | `67e7912`      | [DISPATCH_EXPLANATIONS](zig-native/DISPATCH_EXPLANATIONS.md) |
| 026 Resolved structured flow                      | `ae908fa`      | [RESOLVED_FLOW](zig-native/RESOLVED_FLOW.md)                 |
| 027 Ownership roles in the IR                     | `c226967`      | [OWNERSHIP_ROLES](zig-native/OWNERSHIP_ROLES.md)             |
| 097 Partial collection shapes (open fixture gate) | `f2b41b4`      | [PARTIAL_COLLECTIONS](zig-native/PARTIAL_COLLECTIONS.md)     |
| 099 Stage-chain rejection                         | `5340ef2`      | [STAGE_CHAIN_REJECTION](zig-native/STAGE_CHAIN_REJECTION.md) |

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

1. **Task 097's representation fix is committed at `f2b41b4`.** The broad
   checker default was rejected; its patches remain in `build/wip/`. Partial
   physical shapes preserve generic reuse without semantic defaults. Full native
   suite, 651 guest/client tests and zero analyzer findings pass. The 54-module
   regular gdev suite passes all 472 cases; blocked app/sandbox pass ten checks.
   All public examples, synthetic phases and frozen gdev preserve Wasm bytes.
   [PARTIAL_COLLECTIONS](zig-native/PARTIAL_COLLECTIONS.md) records the
   evidence. Task 097 remains open for complete reported-fixture qualification:
   the blocked split-hauling module now reports `inference_budget`; it remains
   uncompiled.
2. **`zig-native/PROJECT_PROTOCOL.md`** (untracked) was written by the pen
   session (`pen-9c`) as task 095's first checklist item, describing protocol
   version 1 as the code has it at `544c5c6`. A read-only audit found
   corrections still needed before committing it with 095. It was compared
   against `zig_project_server.zig`, `zig_project_frames.zig` and
   `compiler/zig_project_client.ts`. The pen session flagged two points to
   check: duplicate JSON fields stop the process only through Zig 0.17's default
   `duplicate_field_behavior`, and the example rejection is illustrative.

## Next work

1. Finish 097's reported-fixture compilation gate. The representation fix passes
   every regular gdev module and blocked app/sandbox; split hauling still
   exceeds the existing module inference budget. Public cost reduction:
   `zig-native/tests/stage_chain_budget.test.ts`, 64 callback fields and stage
   links. A 51-link control takes 974,824 inference steps; 52 links exceed one
   million. Do not close 097 merely because the former crash is now diagnosed.
2. 095, then 096: pen will drive `blotc serve-project` from Rust and pin a blot2
   commit once 095 lands. The draft was audited read-only: hello advertises
   version 1 and the TypeScript client checks it, but `open` carries no client
   version. Add explicit client-version admission and an independent raw-wire
   conformance test; existing fake-peer tests only prove client-side version
   rejection. The audit also found draft inaccuracies around absent/default open
   fields, duplicate overlays and stats validation; notes are in ignored
   `build/bench/project-protocol/audit.md`. Tell the gdev session (`gdev-94`)
   the commit to pin. 096's spec is gdev's `asset_parsers.ts`; match the text
   parser exactly (code points, per-character font glyph check, `fontExtra`, the
   `shown` transform, lines ~77–112).
3. Then numeric order: 028 (emission consumes resolved bodies; 025–027 plans are
   transient per construct), 036, 049, 094, 098.
4. Still open: 024 and 093 in progress; 002 blocked on owner-local benchmark
   artifacts (see below); 086 needs a fresh gdev profile and an owner decision.

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

## Task 002 (blocked)

The original packed-List benchmark artifacts and the frozen gdev snapshot
matching `scripts/bench/gdev-manifest.json` are missing. Restore them before
final qualification. Commit `65dccda` holds the current List lowering; F32 folds
are within 0.6–1.7% of boxed at widths 14–16. Rerun on a quiet host with
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

- Test-iteration experiment: safe no-LLVM test compilation took 8.1 seconds, but
  the fallback-Core recursion law emitted a stack SIGSEGV. The experiment was
  stopped, with no aggregate pass count; the default build is unchanged. Details
  and executable/source pins: ignored
  `build/bench/test-iteration/iteration-findings.md`.
