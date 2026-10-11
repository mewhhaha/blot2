# 028 — Make emission consume resolved bodies

## Status, dependencies, and originating requirements

- **Status:** Complete.
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

- [x] Route every supported body through owned resolved preparation and restrict
      emission to encoding resolved operations.
- [x] Keep planning, layout, static serialization and ownership responsibilities
      explicit; resolve errors with source origins before emission.
- [x] Remove duplicate selection paths only after parity across staged/accessor
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

- [x] Instruction emission performs no semantic callee/evidence selection.
- [x] All production paths use resolved bodies with equivalent behavior and
      explicit ownership; obsolete branches are removed.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementation: `b068dc9` (joint compiler boundary for 028/036/094/098).
- Validation: Zig 0.17.0, Deno 2.9.7; `deno task test:compiler` passes the
  complete native gate and 763 guest/client laws. `deno task lint:zig` with
  `ZIG_ANALYZER=build/tools/zig-analyzer/zig-out/bin/zig-analyzer`: 323 files,
  zero findings. All eight unchanged compile-allocation laws pass.
- Comparison: seven alternating release pairs preserve successful Wasm, constant
  steps, code instances and old prepared-shape counters across 13 public
  examples, synthetic fresh/retained/restart phases and native-asset
  edit/revert/rejection/recovery. Nine CLI diagnostic cases match after optional
  `related`/`details` null-versus-absent normalization. Current captured gdev:
  55 modules, 482 fixture cases, 1,460 assertions; split hauling: 12 exports, 25
  assertions. CPU is mixed; no overall compiler speedup is claimed.
- Remaining limitations: Body plans remain Generator-local. Encoding still owns
  machine layout, static evaluation/serialization and lazy wrapper reservation;
  synthetic helper functions encode directly.
- Durable record: [RESOLVED_BODIES.md](../zig-native/RESOLVED_BODIES.md) and the
  shared
  [qualification](../zig-native/RESOLVED_BODIES.md#qualification-11-october-2026),
  including exact compiler/input/harness hashes and median distributions.
