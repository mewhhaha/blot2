# 034 — Reclaim cyclic ownership

## Status, dependencies, and originating requirements

- **Status:** Complete — local implementation `dd6a66a`; final tracing/CPU gate
  remains task 035.
- **Dependencies:** [033](033-own-suspended-effects-and-cancellation.md)
- **Originating requirements:** PLAN: Earlier programs / runtime cycles.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Implement the cycle-reclamation strategy specified in task 030.

## Starting point

[tests/arena_gc_execution.test.ts](../zig-native/tests/arena_gc_execution.test.ts)
contains the executed State/closure/demand counterexample. Typed RC and
suspended roots now expose the complete graph needed for cycle handling.

## Implementation checklist

- [x] Implement candidate discovery, root/reachability treatment and reclamation
      using the agreed strategy.
- [x] Retain reachable cycles and their strong memoized results; changing State
      may remove a root but must not mutate the cached value.
- [x] Reclaim discarded cycles including shared subgraphs and suspended/canceled
      objects without interfering with ordinary RC destruction.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Run the existing cycle law unchanged, plus multiple cycles sharing children,
  self-cycles and cycles rooted through suspended values.
- Drop roots in different orders, clear/repopulate State and force cached
  results before and after collection opportunities.
- Run long loops creating/discarding cycles and measure bounded live memory and
  reclamation work.

## Acceptance criteria

- [x] Reachable cycle behavior is unchanged, including strong demand memo
      results after State writes.
- [x] Discarded cycles reclaim under sustained execution without leaks, double
      frees or invalid suspension state.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: local implementation `dd6a66a`; separate record commit follows.
  Nothing is pushed.
- Validation: Zig 0.17.0; the required `deno task test:compiler` passes the
  native suite and 892 guest/client laws, including eight unchanged release
  budgets. Analyzer: 344 files, zero findings. Isolated native/OOM and executed
  laws cover unchanged State/closure/strong-memo cycles, shared subgraphs,
  leased roots, JSPI settlement/rejection, cancellation, weak-queue/tracing
  interaction, sparse finite masks, failed revisions and exact replay.
- Comparison: finite-loop warmed memory falls 5,373,952 → 131,072 bytes; cycle
  CPU rises about 14%, and scalar JSPI about 16%. Sparse one-edge closures
  retain about 0.002-ms CPU with either a 4-byte or 4-MiB payload; 1,048,576
  owning slots have about 5.77-ms maximum measured wall pause. Combined
  public/synthetic costs and all exact pins remain in the record.
- Remaining limitations: full closure passes are synchronous and may rescan
  large live graphs. Tracing remains; task 035 owns its removal and final
  CPU/memory gate, including material host-call/cycle overhead. Safety
  completion does not claim that performance acceptance.
- Durable records: [cycle ownership](../zig-native/CYCLIC_OWNERSHIP.md) and
  [qualification](../zig-native/CYCLIC_OWNERSHIP_QUALIFICATION.md#integrated-qualification--12-october-2026).
