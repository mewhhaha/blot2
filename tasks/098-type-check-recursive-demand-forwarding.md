# 098 — Type-check recursive demand forwarding

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
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
[demand_inline_tests.zig](../zig-native/src/demand_inline_tests.zig) expects the
recursive program to check and is skipped until this task completes; it never
ran before its file was registered.

## Implementation checklist

- [ ] Find why the recursive reference loses the callee's demand mode during
      checking, and keep the demand mode for recursive and mutually recursive
      uses.
- [ ] Re-enable the skipped law and add an executed recursive forwarding law.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Recursive and mutually recursive forwarding, with and without annotations,
  terminating through a base case.

## Acceptance criteria

- [ ] Recursive demand forwarding checks, runs and declines the bounded inline
      proof.
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
