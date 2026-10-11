# 091 — Bound compile-time evaluation by call depth

## Status, dependencies, and originating requirements

- **Status:** Complete at `915b7e1`.
- **Dependencies:** None.
- **Originating requirements:** reported on 11 October 2026 by a separate
  session developing gdev against the `b822ccf` compiler; compile-time
  evaluation limits. Sources: that session's report.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Compile-time evaluation limits recursion by call depth (or exempts tail calls)
rather than by nested expressions, so recursive walks over long lists evaluate.

## Starting point

`core_eval.Session.expressionInner` fails with `constant_fuel` when
`Session.depth` reaches `Options.max_depth` (256), and depth grows with every
nested expression. A recursive walk over gdev's ECS registration list
(`Entry.contains`) therefore fails at about 80 registered types, far below any
real stack limit.

## Implementation checklist

- [x] Count call depth (or do not count tail calls) for the evaluation limit,
      while keeping a structural bound on native recursion.
- [x] Keep fuel, failures and their diagnostics deterministic and equal between
      fresh and retained builds.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Evaluate a recursive constant walk over several hundred elements, and a
  non-terminating recursion that must still fail deterministically.

## Acceptance criteria

- [x] The recursive walk evaluates; runaway recursion still fails with a
      positioned diagnostic.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `915b7e1` ("Bound compile-time recursion by call depth on a reserved
  stack").
- Change: `main` runs the compiler on a thread with a 1 GiB reserved stack and
  falls back to the main thread when the reservation fails. Nested function
  calls are bounded by `Options.max_call_depth` (4,096) with a new
  `constant_recursion` diagnostic, which unwinding frames re-anchor to the
  outermost call of the failing evaluation. `Options.max_depth`, the nested
  expression bound, rises from 256 to 65,536 as a native stack guard. Measured
  stack use is about 11 KB per recursion level in release builds and 13 KB in
  safety-checked builds, so 4,096 simple calls need about 55 MB.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 636 guest/client tests; `deno task lint:zig` reports zero findings across
  310 files. A native law (`core_eval_tests.zig`) evaluates recursion just under
  a small call limit, fails one call past it with `constant_recursion` spanning
  the constant's outermost call, and shows that one call nesting seven
  expressions counts once; it fails without the re-anchoring. A process law
  (`tests/evaluation_depth.test.ts`) walks registries of 600 and 3,000 entries,
  executes the results, and reports runaway recursion at `forever 0`, retained
  and fresh alike; the previous compiler fails at 600 with `constant_fuel`
  inside the prelude.
- Comparison: the synthetic corpus emits identical Wasm in every phase with CPU
  within the 10 ms timer resolution; two gdev pairs keep identical counters and
  edit CPU (560–580 ms).
- Remaining limitations: tail calls are not exempt; the limit is 4,096 nested
  calls. Hosts that cannot reserve 1 GiB run on the main thread, where very deep
  evaluation can still exhaust the native stack.
- Durable record: [CONTRACT.md](../zig-native/CONTRACT.md).
