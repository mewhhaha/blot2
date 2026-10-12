# 038 — Eliminate demands through known callbacks

## Status, dependencies, and originating requirements

- **Status:** Complete — local implementation `f184dde`; qualified evidence
  below.
- **Dependencies:** [037](037-lower-loop-aware-local-memos.md),
  [032](032-own-escaping-values-and-persistent-roots.md)
- **Originating requirements:** DEMANDS: Known callbacks and captured demand
  elimination. Sources: [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Extend demand elimination through known callback uses and provably local
captured demands.

## Starting point

Unknown, indirect and escaping callbacks currently retain cells.
[known_call.zig](../zig-native/src/known_call.zig), resolved call evidence and
demand-use summaries can prove complete local callback uses; task 032 covers
fallback roots.

## Implementation checklist

- [x] Propagate use/escape facts through statically known callback invocations
      and local captures with complete evidence.
- [x] Eliminate storage only when every use remains within the creation
      lifetime; retain a shared cell for unknown/escaping uses.
- [x] Preserve callback invocation multiplicity, latent effects, captured
      aliases and once-per-creation memo sharing.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test a captured demand used by several local callbacks, callbacks inside loops
  and callbacks returned/stored externally.
- Use same-typed callbacks with different captures and effect rows; compare
  optimized and fallback effect traces and traps.
- Exercise dependency/checkpoint import, changed callback bodies, OOM and
  failed-edit recovery.

## Acceptance criteria

- [x] Complete known local callback use can avoid demand cells while keeping
      exact memo semantics.
- [x] Unknown or escaping paths keep safe persistent storage with valid root
      ownership.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: local implementation `f184dde`; the separate record commit contains
  this completion evidence. Nothing is pushed.
- Validation: Zig 0.17.0; `deno task test:compiler` passes all 1,400 native and
  871 guest/client laws; eight unchanged release allocation budgets pass.
  `deno task lint:zig` checks 343 files with zero findings. Bounded complete
  callback-use proofs, immutable snapshots, U32/F32/row specialization, loop
  multiplicity, owned captured Arrays, escaping fallbacks, source/compiled
  imports, checkpoints, OOM and failed-edit recovery pass.
- Comparison: The focused 16,384-iteration scalar fixture removes memory/table
  storage and allocation traffic; outside/inside-loop CPU drops 907.06→5.50 µs
  and 8,514.25→34.50 µs. Combined public costs are recorded without an overall
  speedup claim.
- Remaining limitations: Recursive, exhausted, computed, foreign,
  provider/request, parameter-carried and escaping routes keep ordinary shared
  cells. The local proof remains bounded at 96 nodes, 64 bindings and 16
  parameters.
- Durable record: [KNOWN_CALLBACK_MEMOS](../zig-native/KNOWN_CALLBACK_MEMOS.md);
  exact combined pins, commands, rejected attempts and raw evidence are in
  [integrated qualification](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#integrated-qualification--12-october-2026).
