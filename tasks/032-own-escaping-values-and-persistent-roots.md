# 032 — Own escaping values and persistent roots

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

- [ ] Transfer or retain roots across returned values, captured environments,
      persistent aggregates and module initialization.
- [ ] Keep demand captures and completed results alive until their last owner
      releases them, preserving once-per-creation sharing.
- [ ] Define entry/exit and arena-reset ownership using task 030 without
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

- [ ] All supported escape and persistent-root boundaries have explicit
      ownership operations.
- [ ] Surviving values remain valid across calls and resets, with no premature
      release or unbounded discarded roots.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task; record commands, versions, results and
  evidence links.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
