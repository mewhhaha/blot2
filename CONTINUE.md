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

`main` is at `544c5c6`. Completed today, each with a durable record:

| Task                          | Implementation | Record                                                       |
| ----------------------------- | -------------- | ------------------------------------------------------------ |
| 048 Dispatch explanations     | `67e7912`      | [DISPATCH_EXPLANATIONS](zig-native/DISPATCH_EXPLANATIONS.md) |
| 026 Resolved structured flow  | `ae908fa`      | [RESOLVED_FLOW](zig-native/RESOLVED_FLOW.md)                 |
| 027 Ownership roles in the IR | `c226967`      | [OWNERSHIP_ROLES](zig-native/OWNERSHIP_ROLES.md)             |

Earlier today: 025 (resolved calls), 088–092, and progress on 093 (gdev retained
edit 570 → 440 ms; see the task file). Every public example, the synthetic
corpus and the frozen gdev copy still emit byte-identical Wasm at `544c5c6`
(gdev SHA-256 `3158216b…def0`, 840,534 bytes).

Tasks added today: 094 (locate specialization failures at the caller's use), 095
(versioned project protocol), 096 (native typed asset imports), 097
(`Array.iter` with an unconstrained element type), 098 (recursive demand
forwarding does not type-check; one law skipped), 099 (compiler crash on long
stage chains).

## Uncommitted work in the tree

1. **Task 097, in progress.** `zig-native/src/check.zig` adds
   `defaultUnconstrained` in `Engine.finish`: an expression type variable that
   inference left unconstrained, that no scheme generalizes and that no unsolved
   obligation names, unifies with Unit (checker counter `defaulted_types`). A
   copy is in `build/wip/097-default-unconstrained.patch`. `zig-out/bin/blotc`
   is built from this tree.
   - The gdev-free repro now compiles and runs: `count` loops over its array
     argument (`for x in xs: n := self + 1`), and
     `entry const create = fn () => count #[]`. So does the `Box [a, b]` variant
     (`count #[] + count #[#A 1, #A 2] * 10` returns 20).
   - Not yet acceptable: it changes the Wasm of `examples/monads.blot` and
     `examples/prelude.blot`. Defaulted there: `#Nothing` and the name
     `Result.unwrap_or` (monads), `Result.unwrap_or` (prelude). Also defaulted
     but byte-identical: a record pattern `{ initial }` in `ecs` and
     `count_until_zero` in `requests`.
   - Next: find which variable `Result.unwrap_or` leaves free (likely the unused
     error type) and why Unit instead of `erased` changes code. Then decide
     between keeping the byte change (verify behavior: examples' tests, gdev
     bytes and gdev tests) and narrowing the rule, for example defaulting only
     where emission would otherwise fail.
   - Then add the two repro programs as laws, run the gate, and record. Root
     cause: specialization cannot tell an unconstrained variable from an
     unselected one (both reach it as `erased`), and refinement of `Array.iter`
     needs concrete element evidence. Defaulting in the checker is the only
     place that knows a variable is truly unconstrained.
2. **`zig-native/PROJECT_PROTOCOL.md`** (untracked) was written by the pen
   session (`pen-9c`) as task 095's first checklist item, describing protocol
   version 1 as the code has it at `544c5c6`. It is unreviewed. Review it
   against `zig_project_server.zig`, `zig_project_frames.zig` and
   `compiler/zig_project_client.ts` before committing it with 095. The pen
   session flagged two points to check: duplicate JSON fields stop the process
   only through Zig 0.17's default `duplicate_field_behavior`, and the example
   rejection is illustrative.

## Next work

1. Finish 097 (above).
2. 099: get a reduced, gdev-free repro from the gdev session. The current one is
   `/tmp/claude-1000/-home-jacobt-src-gdev/8fe707f7-36f4-47a4-8a1f-37ead8a3232f/scratchpad/ui_game_crashes_blotc.blot`
   (compile it appended to gdev's `src/main.blot`, or run
   `../pen/target/release/pen test-blot <path>` from `~/src/gdev`). A segfault
   suggests another unbounded recursion (task 091 bounded constant evaluation).
3. 095, then 096: pen will drive `blotc serve-project` from Rust and pin a blot2
   commit once 095 lands. Tell the gdev session (`gdev-94`) the commit to pin.
   096's spec is gdev's `asset_parsers.ts`; match the text parser exactly (code
   points, per-character font glyph check, `fontExtra`, the `shown` transform,
   lines ~77–112).
4. Then numeric order: 028 (emission consumes resolved bodies; 025–027 plans are
   transient per construct), 036, 049, 094, 098.
5. Still open: 024 and 093 in progress; 002 blocked on owner-local benchmark
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
  `build/tools/zig-analyzer`; it reports zero findings across 314 files at
  `544c5c6`.
- Seventeen source files whose inline tests were never registered in
  `zig-native/src/tests.zig` were added there in `c226967`. A new file with
  `test` blocks needs its own `_ = @import(...)` line, or its tests never run.
