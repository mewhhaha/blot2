# 038 — Eliminate demands through known callbacks

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

- [ ] Propagate use/escape facts through statically known callback invocations
      and local captures with complete evidence.
- [ ] Eliminate storage only when every use remains within the creation
      lifetime; retain a shared cell for unknown/escaping uses.
- [ ] Preserve callback invocation multiplicity, latent effects, captured
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

- [ ] Complete known local callback use can avoid demand cells while keeping
      exact memo semantics.
- [ ] Unknown or escaping paths keep safe persistent storage with valid root
      ownership.
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
