# 027 — Represent ownership in resolved ir

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [026](026-resolve-structured-control-flow.md)
- **Originating requirements:** PLAN: Earlier semantic compilation / resolved
  ownership. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Encode allocation, borrowing, transfer, sharing and cleanup roles explicitly in
resolved IR.

## Starting point

[runtime_layout.zig](../zig-native/src/runtime_layout.zig),
[runtime_ir.zig](../zig-native/src/runtime_ir.zig) and
[wasm_lifetimes.zig](../zig-native/src/wasm_lifetimes.zig) describe layouts and
machine-level lifetime facts. Ownership is not inferable from arbitrary i32
words; task 026 provides explicit edges.

## Implementation checklist

- [ ] Attach typed allocation and field roles from checked layouts, including
      shared/owned pointers, scalar payloads and allocation bases.
- [ ] Represent transfers, borrows, escapes and cleanup on each
      normal/exceptional edge, retaining conservative unknown cases.
- [ ] Preserve aliases, persistent collection snapshots, cyclic groups and
      suspended payload lifetimes.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test scalar words resembling pointers, reference-bearing rows, escaping
  groups, shared children and cycles.
- Check branch/loop liveness, last borrows, returns, request cancellation and
  allocation-failure cleanup.
- Compare lifetime optimizations with conservative execution and fresh/retained
  output.

## Acceptance criteria

- [ ] Ownership roles come from checked layouts and explicit operations, never
      raw machine-word types.
- [ ] Every admitted transfer/cleanup has a valid edge and alias proof; unknown
      ownership remains conservative.
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
