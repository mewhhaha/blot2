# 031 — Implement shared reference counting

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [030](030-specify-shared-and-cyclic-ownership.md)
- **Originating requirements:** PLAN: Earlier programs / shared RC. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Add typed retain/release operations and destruction for shared heap objects
while keeping tracing during the transition.

## Starting point

[runtime_layout.zig](../zig-native/src/runtime_layout.zig) defines heap fields,
[arena_runtime.zig](../zig-native/src/arena_runtime.zig) supplies storage, and
[wasm_lifetimes.zig](../zig-native/src/wasm_lifetimes.zig) proves local
allocation groups. Task 030 defines the new shared ownership contract.

## Implementation checklist

- [ ] Implement reference metadata, checked typed operations and destructors
      from the agreed layout roles.
- [ ] Retain/release aggregate fields, closure captures and collection nodes
      without treating scalar bit patterns as references.
- [ ] Integrate exceptional exits and prevent double release when local lifetime
      optimizations consume ownership. Keep tracing available for uncovered
      graphs.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Exercise multiple aliases, persistent List/Array updates, shared children,
  overwritten fields and nested destruction.
- Test empty/scalar-only objects, pointer-looking integers, traps and
  cancellation; run OOM and immutable-input laws.
- Measure reference operation cost and memory alongside existing tracing
  behavior.

## Acceptance criteria

- [ ] Typed RC operations account for every supported shared object and preserve
      alias/snapshot behavior.
- [ ] Destruction has no leaks or duplicate cleanup in the covered cases;
      tracing remains until later gates pass.
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
