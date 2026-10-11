# 031 — Implement shared reference counting

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified locally; nothing pushed.
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

- [x] Implement reference metadata, checked typed operations and destructors
      from the agreed layout roles.
- [x] Retain/release aggregate fields, closure captures and collection nodes
      without treating scalar bit patterns as references.
- [x] Integrate exceptional exits and prevent double release when local lifetime
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

- [x] Typed RC operations account for every supported shared object and preserve
      alias/snapshot behavior.
- [x] Destruction has no leaks or duplicate cleanup in the covered cases;
      tracing remains until later gates pass.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementation: `cb41a6d`.
- Validation: Zig 0.17.0, Deno 2.9.7; `deno task test:compiler` passes the
  release build, native suite and 771 guest/client laws, including all eight
  unchanged allocation budgets. `deno task lint:zig` reports zero findings
  across 327 files. Joint integration source matches the isolated qualified tree
  exactly; compiler input fingerprint matches too.
- Comparison: twenty alternating compiler/runtime pairs, header geometry and
  checked-operation costs are recorded in
  [SHARED_RC](../zig-native/SHARED_RC.md). Fresh/edit CPU increases 3.9%/13.2%;
  the covered Array/List workload costs 4.2/11.4 times tracing CPU. No
  performance improvement is claimed.
- Remaining limitations: tracing remains for uncovered graphs. Persistent and
  suspended roots belong to 032–033; complete cycle reclamation/removal to
  034–035. The nested discarded-Array memory counterexample remains open.
- Durable record: [SHARED_RC](../zig-native/SHARED_RC.md).
