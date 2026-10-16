# 098 — Type-check recursive demand forwarding

## Status, dependencies, and originating requirements

- **Status:** Complete.
- **Dependencies:** None.
- **Originating requirements:** found while completing task 027, when
  `demand_inline_tests.zig` first joined the native suite; demand forwarding
  semantics in [compiler/guide.md](../compiler/guide.md#demand-parameters) and
  [DEMANDS.md](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

A function that forwards its own demand to itself type-checks, as forwarding
does for any other lazy callee.

## Starting point

`const recursive: ~U32 -> U32 = fn ~(value: U32) => recursive (@demand value)`
reports `type_mismatch` over the whole declaration, with or without the
annotation and with `fn ~value`. Forwarding to another lazy function
(`fn ~(value: U32) => twice (@demand value)`) checks. The law "recursive demand
forwarding declines its bounded inline proof" in
[demand_inline_tests.zig](../zig-native/src/backend/demand_inline_tests.zig)
expects the recursive program to check and is skipped until this task completes;
it never ran before its file was registered.

## Implementation checklist

- [x] Find why the recursive reference loses the callee's demand mode during
      checking, and keep the demand mode for recursive and mutually recursive
      uses.
- [x] Re-enable the skipped law and add an executed recursive forwarding law.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Recursive and mutually recursive forwarding, with and without annotations,
  terminating through a base case.

## Acceptance criteria

- [x] Recursive demand forwarding checks, runs and declines the bounded inline
      proof.
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
- Remaining limitations: Provisional demand modes cover direct recursive lambda
  spines only. This does not broaden recursive inline-proof eligibility or
  change recursive-force policy.
- Durable record: [DEMANDS.md](../zig-native/DEMANDS.md) and the shared
  [qualification](../zig-native/RESOLVED_BODIES.md#qualification-11-october-2026),
  including exact compiler/input/harness hashes and median distributions.
