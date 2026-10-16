# Resolved structured flow

Task 026 extends the resolved backend boundary from calls
([resolved calls](RESOLVED_CALLS.md)) to structured control flow. Before it,
[the emitter](src/backend/core_backend.zig) found a `return`'s block and a
`break`'s loop by scanning its target stacks in the middle of the statement,
derived join result types where it opened each block, and decided which cleanup
an exit ran as it emitted the branch.

## Plans

[resolved_flow.zig](src/backend/resolved_flow.zig) defines what preparation
hands to emission:

- `Exit`: one edge out of structured scopes (`return_`, `break_`, and a request
  loop's `request_return` and `request_break`). It names the exiting statement,
  the block or loop it leaves and that target's Wasm label, the target scope's
  cleanup mark, the `return` value or the `break` values in source order, and
  the loop carries those values replace, last to first.
- `Join`: arms that rejoin, with the joined value's machine type (none for an
  `if` statement) and the local versions (`Merge`s) each arm hands on; an `if`
  statement records whether it emits an else arm.
- `Match`: a `case` or `if let`, with its join, its inputs (evaluated once, in
  order) and its arms. A row whose pattern fails falls to the next row, a
  rejected guard to the next arm, and a completed arm joins the result.
- `Loop`: a loop's kind, its carries (incoming, iteration, backedge and outgoing
  versions), whether its element pattern tests at runtime and traps, and whether
  a `forever` loop without `break` diverges.
- `RequestLoop`: the handler arms that yields run, the `exited` edge to the
  enclosing block when a handler returns, the `broken` edge to the loop's exit
  with its carries, and the completion pattern and body. Cancellation unwinds
  every cleanup of the function inside the runner.

## Rules

- Each plan is prepared before the first instruction of its construct:
  `prepareReturn`, `prepareBreak`, `prepareJoin`, `prepareMatch`, `prepareLoop`
  and `prepareRequestLoop`. An unresolvable target is reported at the exiting
  statement before any of its instructions.
- `takeExit` discharges exactly the cleanup actions recorded above the target
  scope's mark, the obligations of the scopes the edge leaves, innermost first,
  then branches to the depth computed from the target's label at the exit point.
- A request loop's `broken` edge binds its cleanup mark when the loop's exit
  scope opens, after the cell and handler frames the loop allocates; the loop's
  own close releases them, so the edge itself discharges nothing.
- Local allocation, label numbering and every emitted instruction are unchanged.
  Plans borrow Core slices and are dropped after their construct.
- Work counters (`prepared_exits`, `prepared_exit_cleanups`, `prepared_joins`,
  `prepared_matches`, `prepared_loops`, `prepared_request_loops`) count prepared
  plans and the cleanup actions exits discharge.

## Qualification on 11 October 2026

- Zig 0.17.0 before every build batch; the milestone is `ae908fa`.
  `deno task test:compiler` passes the full native suite and 646 guest/client
  tests; `deno task lint:zig` reports zero findings across 314 files.
- Every public example, the synthetic `bench:compile` corpus in every phase and
  the frozen gdev copy emit byte-identical Wasm before and after (gdev SHA-256
  `3158216b…def0`, 840,534 bytes).
- [A process law](tests/resolved_flow.test.ts) executes value and statement
  joins with rebinding merges, a guarded `case`, nested loops with two carries,
  zero iterations, `break` and a `return` from inside a loop, and request loops
  whose handlers yield, return and break. Retained builds equal fresh ones
  through an edit, and fresh builds count every plan shape, including cleanup
  discharged by a request handler's return. A mutant that assigns `break`
  carries in source order fails it.

## Remaining scope

- Plans are prepared per construct and dropped after emission; task 028 makes
  emission consume stored resolved bodies, and task 027 attaches ownership roles
  to these edges.
- Exact builders and internal traversal code (list spans, row views) open their
  own Wasm blocks and loops without plans; they are not source-level edges.
- The cleanup actions an exit discharges are still created by emission (private
  storage is allocated as values are emitted), so an exit records its target
  scope before its value and discharges the actions present when it branches.
