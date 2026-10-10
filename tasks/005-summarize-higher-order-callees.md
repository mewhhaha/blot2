# 005 — Summarize higher order callees

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified parametric callback obligations and
  independent higher-order jobs preserve exact caller obligations.
- **Dependencies:** [004](004-summarize-predicate-bearing-callees.md)
- **Originating requirements:** PLAN: Hill 2 / the sandbox region. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Represent obligations of function parameters parametrically and split valid
higher-order calls into independent inference regions.

## Starting point

Use the
[approved summary interface](../zig-native/CALL_SUMMARIES.md#higher-order-obligations-and-effects)
and its
[acceptance cases](../zig-native/CALL_SUMMARIES.md#acceptance-examples-for-the-implementation-sequence).

Predicate-free callbacks already use checked schemes. `ClosureRegion` and
`principalEvidence` in [core_eval.zig](../zig-native/src/core_eval.zig) still
combine general higher-order graphs;
[callback_row_tests.zig](../zig-native/src/callback_row_tests.zig) and
[tests/callback_row_execution.test.ts](../zig-native/tests/callback_row_execution.test.ts)
cover latent callback rows.

## Implementation checklist

- [x] Implement the callback-obligation form specified in task 003, including
      generic argument/result relationships and latent effects.
- [x] Partition only when complete callback evidence permits it, preserving
      callback captures and source-interface checks.
- [x] Distinguish unresolved or escaping callback facts from principal
      information and preserve the bounded conservative fallback.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Exercise pure/effectful reducers, callbacks returning callbacks, unused
  callback rows, incompatible results and imported generic combinators.
- Test same code with different captures, providers and callback evidence
  through fresh, retained, checkpoint and dependency paths.
- Measure the sandbox region and higher-order fan-out work; compare diagnostic
  order and OOM recovery.

## Acceptance criteria

- [x] Valid higher-order jobs no longer require their entire transitive graph in
      one region.
- [x] Callback effects and captures remain exact, and unresolved cases retain
      correct diagnostics without unbounded retry.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `652f4d6ee67ecd1aa45096bdc57e089bd082a112` on local `main`.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 609 guest/client tests. `deno task lint:zig` reports zero findings across
  291 files. Focused native laws cover callback stages, rows, aliases, captures,
  budgets and allocation failures. Imported guest laws exercise providers,
  predicates, dependency/checkpoint restoration and failed-edit recovery.
- Comparison: 563 public cases / 1,126 cache-disabled invocations have exact
  ordered diagnostic and Wasm parity. Fifteen alternating release pairs cover 32
  workloads; seven pairs cover four ordinary and then 31 extended
  fresh/retained/restart workloads. All pinned hashes remain unchanged.
  Predicate depth-12 fresh CPU falls from 8.8–13.9 seconds to 8–9 ms in the
  extended harness; candidate maximum scopes are three or four.
- Remaining limitations: small callback controls add CPU/allocation overhead;
  incomplete capture observations use ordinary checking. Lexical capture inputs,
  joint recursive components and canonical portable keys remain tasks 006–008.
  Empty profiles supply no duration measurement. Private gdev and historical
  task 002 artifacts remain unavailable.
- Durable record:
  [parametric callback qualification](../zig-native/CALL_SUMMARIES.md#parametric-callback-obligations-10-october-2026)
  records the exact baseline/candidate identities, commands, distributions and
  rejected capture experiment.
