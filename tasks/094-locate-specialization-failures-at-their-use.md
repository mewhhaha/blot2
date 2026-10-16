# 094 — Locate specialization failures at their use

## Status, dependencies, and originating requirements

- **Status:** Complete.
- **Dependencies:** [048](048-explain-dispatch-and-evidence.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 1 / explainable
  inference; found while completing task 048. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md),
  [dispatch explanations](../zig-native/DISPATCH_EXPLANATIONS.md#remaining-scope).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

A dispatch or obligation that fails while a callee is specialized for a caller's
types is reported at the caller's source use, with the callee's location kept as
secondary context.

## Starting point

`#Box 1 + #Box 2` in a program without `Box.add` reports `missing_associated` at
`std/prelude.blot` 603–630, the `@type.call` inside `add`, because the checker
leaves the concrete dispatch to specialization and
[core_eval.zig](../zig-native/src/eval/core_eval.zig) fails while validating the
specialized `add` body. Task 048's explanation names the operand types, but the
location is still the prelude. `anchorRecursion` already moves recursion
diagnostics to a call site.

## Implementation checklist

- [x] Carry the outermost entry-project use through specialization and report
      obligation and dispatch failures there, keeping the callee's span as
      secondary context in the published diagnostic.
- [x] Keep diagnostic ordering, codes and explanations unchanged, and keep
      failures that belong to the callee itself located in the callee.
- [x] Extend the client schema for the secondary location with defensive
      decoding.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Operators over user, imported and compiled-dependency types without a member;
  generic callbacks; nested generic callees; failures inside a library's own
  body that must stay there.
- Fresh and retained builds, CLI and project server.

## Acceptance criteria

- [x] A specialization failure caused by a caller's types points at the caller's
      expression in the user's file, with the callee location available.
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
- Remaining limitations: Computed indirect callbacks retain their definition
  location when no source-owned caller origin is available. Successful-dispatch
  editor explanations remain task 050.
- Durable record:
  [DISPATCH_EXPLANATIONS.md](../zig-native/DISPATCH_EXPLANATIONS.md) and the
  shared
  [qualification](../zig-native/RESOLVED_BODIES.md#qualification-11-october-2026),
  including exact compiler/input/harness hashes and median distributions.
