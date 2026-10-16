# Ownership roles

Task 027 gives the runtime IR explicit ownership roles taken from checked
layouts. Before it, [the lifetime pass](src/backend/wasm_lifetimes.zig) proved
releases from symbolic Wasm alone: every `i32` parameter was a candidate address
because of its machine type, and nothing told it which words of an allocation
may hold references. The runtime heap structures declared per-word roles in
[runtime_layout.zig](src/runtime/runtime_layout.zig) that nothing read.

## Roles

[runtime_ir.zig](src/backend/runtime_ir.zig) defines `Role`: `scalar` (never a
heap reference, whatever its machine type), `reference` (a heap reference or
zero), `value` (a word whose layout admits both, such as an erased payload) and
`unknown` (no layout fact; analyses stay conservative).

- **Parameters.** Each function created by the emitter records its parameters'
  roles (`Function.parameter_roles`), from the checked layout of each argument;
  a closure body's environment and provider pointers are references, and host
  ABI scalars and numeric arrays come from their `Scalar`. The journal records
  them (`parameter_roles` events), and both journal replays restore them.
- **Allocations.** Every allocation of constant size is preceded by an
  `ownership` annotation run immediately before its `i32_const size`: chunks of
  13 word roles and a terminating `rest` annotation that states how many words
  it describes and one role for every later word. Roles come from the checked
  layouts of what each word holds: record and product fields in physical order,
  constructor cells (scalar tag, then the payload's role), array headers and
  elements, capture environments (a captured closure template stores its
  environment pointer, a reference, although its layout slot is the unit
  placeholder), request and provider state, and the runtime structures' role
  tables (closures, demands, cursors, pairs, decisions, request cells and
  frames, provider frames and cells). Scalar rows use `allocate_scalar` and are
  annotated as scalar. Allocations of runtime-computed size are not annotated;
  the lifetime pass never owns them.

## Rules

- The encoder drops annotations. Size heuristics (inlining admission and
  budgets, the emitter's 4,096-instruction inline limit, vectorization budgets)
  count only code, and machine-code sharing compares and hashes bodies without
  annotations, so output is unchanged.
- A run describes an allocation only when its `rest` terminator sits directly
  before that allocation's size constant and its chunks count down to chunk 0.
  An annotation left behind by a pass that removed its allocation describes
  nothing.
- The lifetime pass treats a parameter as a candidate address only if it is an
  `i32` word whose role is not scalar. A tracked allocation stored into a word
  whose role is scalar escapes instead of forming a reference edge; such stores
  are counted as `role_conflicts` over every emitted body and published in the
  runtime optimization stats. Emission from checked layouts produces none.
- Releases remain the lifetime plan's: each release sits on a control-flow edge
  (`after`, `before`, `when_true`, `when_false`) chosen by backward liveness;
  owned results are summarized as transfers, borrowed parameters by their byte
  extent, and anything unproved escapes to arena policy. Scoped cleanup on
  structured exits is task 026's (`takeExit`), and cancellation unwinds every
  cleanup of the function.
- Work counters `allocation_role_runs` and `parameter_role_functions` count
  annotated allocations and functions given parameter roles.

## Qualification on 11 October 2026

- Zig 0.17.0; the milestone is `c226967`. `deno task test:compiler` passes the
  full native suite and 647 guest/client tests; `deno task lint:zig` reports
  zero findings across 314 files.
- Every public example, the synthetic `bench:compile` corpus in every phase and
  the frozen gdev copy emit byte-identical Wasm (gdev SHA-256 `3158216b…def0`,
  840,534 bytes) with zero role conflicts. gdev annotates 4,318 allocations and
  gives 1,873 functions parameter roles.
- Before the capture-environment rule, gdev produced role conflicts and 52 more
  bytes of Wasm: the conflict counter found a captured template's environment
  pointer stored in a word that the unit placeholder made scalar.
- Native laws cover annotation runs and their boundaries
  ([runtime_ir.zig](src/backend/runtime_ir.zig)); a scalar word that never
  carries a followed reference and scalar parameters that are never borrowed
  addresses ([wasm_lifetimes.zig](src/backend/wasm_lifetimes.zig)); annotations
  that are not encoded; and journal replay of both facts
  ([artifact_emitter_tests.zig](src/reuse/artifact_emitter_tests.zig)).
- [A process law](tests/ownership_roles.test.ts) builds closures capturing
  templates, constructor cells, records, arrays and request loops through edits
  with retained builds equal to fresh ones, nonzero role counters and zero
  conflicts.
- Reverting the capture-environment rule makes the process law fail on its role
  conflicts.
- Seventeen source files whose inline tests were never registered in the native
  suite, including the lifetime pass's own ownership laws, now run in it. One
  stale law in `demand_inline_tests.zig` expects recursive demand forwarding to
  type-check, which it does not; it is skipped pending task 098.

## Remaining scope

- Roles do not yet drive reference counting; tasks 030–035 specify shared and
  cyclic ownership, add retain/release and remove tracing.
- `value` words (erased payloads, request pairs and decisions, collection roots)
  still need their checked type at each use to become exact.
- Runtime helpers (list runtime, arena) create functions and allocations without
  roles; their words stay unknown.
