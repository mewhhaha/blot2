# 028 — Make emission consume resolved bodies

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [027](027-represent-ownership-in-resolved-ir.md)
- **Originating requirements:** PLAN: Earlier semantic compilation / complete
  backend separation. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Make Wasm emission consume resolved bodies and remove the obsolete
semantic-selection paths after parity.

## Starting point

Task 025–027 preparation covers calls, flow and ownership.
[core_backend.zig](../zig-native/src/core_backend.zig) still combines generator
planning, layout conversion, selection, serialization and instruction emission.

## Implementation checklist

- [ ] Route every supported body through owned resolved preparation and restrict
      emission to encoding resolved operations.
- [ ] Keep planning, layout, static serialization and ownership responsibilities
      explicit; resolve errors with source origins before emission.
- [ ] Remove duplicate selection paths only after parity across staged/accessor
      and request cases; retain documented unsupported diagnostics.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run the complete native/guest suite and differential diagnostics,
  constant-step, code-instance and Wasm comparisons.
- Cover generic closures, open callback rows, effects, staging, dependencies,
  checkpoints and retained recovery.
- Sweep preparation/emission allocation failures and measure CPU/allocation
  against the preceding boundary.

## Acceptance criteria

- [ ] Instruction emission performs no semantic callee/evidence selection.
- [ ] All production paths use resolved bodies with equivalent behavior and
      explicit ownership; obsolete branches are removed.
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
