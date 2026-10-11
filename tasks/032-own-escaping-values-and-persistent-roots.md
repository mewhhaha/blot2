# 032 — Own escaping values and persistent roots

## Status, dependencies, and originating requirements

- **Status:** Complete — local implementation `2798ff9`.
- **Dependencies:** [031](031-implement-shared-reference-counting.md)
- **Originating requirements:** PLAN: Earlier programs / escaping ownership;
  DEMANDS: Effects and lifetime. Sources: [PLAN.md](../PLAN.md),
  [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Establish ownership for escaping closures, captures, demands, globals, returned
aggregates and roots surviving guest calls.

## Starting point

[core_backend.zig](../zig-native/src/core_backend.zig) materializes
closures/demands and globals; [compiler/guest.ts](../compiler/guest.ts) manages
guest invocation boundaries. Local lifetime proofs deliberately reject many
escaping cases.

## Implementation checklist

- [x] Transfer or retain roots across returned values, captured environments,
      persistent aggregates and module initialization.
- [x] Keep demand captures and completed results alive until their last owner
      releases them, preserving once-per-creation sharing.
- [x] Define entry/exit and arena-reset ownership using task 030 without
      expanding the public guest ABI implicitly.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Save closures and demand aliases in globals, Lists/Arrays and records, call
  entries repeatedly and release roots in different orders.
- Test rebinding snapshots, returned shared children, startup data and State
  reaching a cached demand.
- Measure memory after repeated guest calls and verify teardown, failure and
  fresh/retained compilation parity.

## Acceptance criteria

- [x] All supported escape and persistent-root boundaries have explicit
      ownership operations.
- [x] Surviving values remain valid across calls and resets, with no premature
      release or unbounded discarded roots.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `2798ff9` (joint 029/032/037 compiler and bpm milestone).
- Implementation: Explicit ABI-3 invocation boundaries, module owner tables,
  typed frame/result/carry owners and iteration retirement own supported
  synchronous escaping values. Managed local memos keep a caller-frame owner
  across callee iterations.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native
  suite, 844 guest/client laws and all eight unchanged allocation budgets.
  `deno task lint:zig` checks 339 files with zero findings. Focused execution,
  OOM, archive/checkpoint, unchanged-Core and failed-edit recovery laws pass.
- Comparison: seven alternating release pairs over 13 public examples and four
  synthetic workloads. Old semantic counters match; each compiler's output is
  stable and fresh/retained/restart parity holds. Ownership helpers
  intentionally change public Wasm. Peak deltas and teardown live bytes are
  zero; CPU is mixed. Exact pins, distributions and isolated runtime costs are
  retained in the
  [shared qualification](../zig-native/PERSISTENT_ROOTS.md#integrated-qualification-12-october-2026).
- Remaining limitations: Whole-module admission preserves complete tracing for
  unknown/host/import shapes. Host/JSPI ownership, cycles and tracing removal
  belong to 033–035. The isolated reference-Array batch costs +46.7%; memory
  retirement does not return Wasm pages to the OS.
- Durable record: [PERSISTENT_ROOTS](../zig-native/PERSISTENT_ROOTS.md).
