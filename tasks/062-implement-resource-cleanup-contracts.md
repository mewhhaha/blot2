# 062 — Implement resource cleanup contracts

## Status, dependencies, and originating requirements

- **Status:** Complete — closed on 17 October 2026 against the two resource rows
  of
  [language qualification](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026),
  gate at `05401a9`.
- **Dependencies:** [061](061-check-usage-and-call-multiplicity.md),
  [033](033-own-suspended-effects-and-cancellation.md),
  [020](020-persist-complete-semantic-artifacts.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 5 / resource
  cleanup and separate compilation. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Emit required resource cleanup on normal and exceptional exits and preserve
contracts across dependencies.

## Starting point

[runtime_cleanup.zig](../zig-native/src/runtime/runtime_cleanup.zig) already
tracks private runtime scopes; tasks 061 and 033 add checked resource use and
suspended ownership. Portable semantic interfaces come from task 020.

## Implementation checklist

- [x] Lower checked cleanup obligations on returns, breaks, branch exits, scope
      completion and cancellation.
- [x] Transfer cleanup responsibility with ownership, never with a mere borrow;
      handle suspended frames and host exceptions according to the specified
      contract.
- [x] Serialize resource/usage evidence so compiled callers cannot omit cleanup
      or return invalid borrows.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Record cleanup traces for normal returns, early exits, nested resource scopes,
  failed requests and suspended cancellation.
- Test ownership transfer, aliases, borrowed calls and imported resource
  functions for no double cleanup, leaks or escaped borrows.
- Run long-lived failure/retry loops and allocation-failure publication checks.

## Acceptance criteria

- [x] Each owned resource receives exactly the cleanup required on every
      supported exit.
- [x] Separate compilation preserves usage/lifetime contracts and invalid
      borrowed escapes are rejected.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the rows of
[language qualification](../zig-native/LANGUAGE_QUALIFICATION.md) listed below.
Forms outside these rows ("general" captures, stores, transports and shapes) are
not required work: they must reject or decline conservatively with a stable
diagnostic and are recorded as limitations. The acceptance criteria below are
read against these rows.

| Contract  | Qualified requirements                                          |
| --------- | --------------------------------------------------------------- |
| Resources | Return/break/trap, host failure, suspended cancellation         |
| Resources | Transfer, retirement, persistent journal, structural host roles |

Intentional rejections under the normative design: unknown cleanup termination.

The task completes when every native law and guest test mapped to these rows
passes in the full compiler gate (`deno task test:compiler` and
`deno task lint:zig`) on the committed source. The rows passed in the 15 October
freeze `3548546c…`. The 20 native-law failures seen on the evening of 15 October
were fixed in `23a934f`, and the gate at `05401a9` passed on 17 October. The
original acceptance index
(`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`)
was removed with `build/`. The row-to-law mapping regenerated from that gate's
native test names and guest JUnit report is recorded in
[LANGUAGE_QUALIFICATION.md](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026).

## Completion evidence

- Revision: committed source at `05401a9` (17 October 2026), the tree the gate
  ran on; `23a934f` also passed the full gate. The closure itself is
  documentation only.
- Validation (Zig 0.17.0): the full gate at `05401a9` passes 2,355 native laws
  in two shards with zero failures and zero leaks, 1,501 guest tests with zero
  failures, and the harness and smoke phases; `deno task lint:zig` reports zero
  zig-analyzer findings over 486 files. The run's final native-input check
  refused only because another session edited `../gdev` during the run; every
  phase passed. The earlier gate at `23a934f` passed 2,354 native laws with zero
  leaks, 1,486 guest, 28 harness, 21 preflight and 48 smoke tests and zero
  analyzer findings.
- Row-to-law mapping: the
  [index](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026)
  names 19 native laws and 22 guest tests for the seven requirements of the two
  resource rows; all passed in the `05401a9` gate.
- Implemented at the focused checkpoints (Zig 0.17.0; later continuations in the
  durable record supersede some rejections listed here, such as owning public
  outputs): checked cleanup lowering for scalar payloads, managed callback
  results, early returns/breaks, reverse cleanup, traps, failed
  acquisition/cleanup and host throw/rejection in both tiers and sync/JSPI;
  pending JSPI retains ownership until settlement and blocks reentry/disposal.
  Array/List payloads of unqualified primitives reuse ABI 4 and the same
  journal. Counted owning boxes preserve one journal obligation through moves,
  shared aliases and once captures within an invocation; owning
  scalar/numeric-Array inputs are freshly boxed and owning public outputs
  reject. Imports, failed revisions, portable checkpoint and restart preserve
  bytes; typed ABI mutants reject before invocation.
- Focused evidence: 24 combined usage/resource native laws and four backend laws
  with complete allocation sweeps (177 source/Core and 311 backend failures),
  plus reference and transfer continuation laws and both-tier guest groups.
  Ownership counters return to zero with flat warmed memory over 4096
  failure/recovery calls and 4608 repeated transfer calls; journal controls
  cover 10,000 sequential scopes, 5,000 sequential resources and the 4096
  live-reservation limit. Selected 328-file Zig lint has zero findings under the
  verified Zig/std backend; an earlier 416-file claim is withdrawn because its
  backend was missing.
- Comparison: performance measurement does not apply; the closed rows set no
  performance target. Retained resource-scope phase times (population 1.8337 ms,
  first edit 1.6419 ms, revert 1.4306 ms) are recorded in
  [measured scope cost](../zig-native/LANGUAGE_QUALIFICATION.md#measured-scope-cost);
  they include IPC and qualify no CPU target.
- Remaining limitations: unknown cleanup termination remains an intentional
  rejection under the normative design, so unknown, recursive and named adapter
  calls and pure cleanup parameters gain no cleanup authority. Host cleanup
  `maxSteps` is a trusted host completion promise that the compiler cannot
  prove; only `maxCalls` is enforced. Payload and host shapes without a closed
  checked representation (loans, providers, demands, nested usage and callable
  payloads) cannot become owners or cleanup payloads. Raw Wasm traps drain host
  journals rather than promising source-level unwinding. Forms outside the rows
  are excluded scope under the owner decision of 15 October 2026 (closed
  acceptance above; [README owner decisions](README.md#task-index)), not open
  work. Such forms reject or decline conservatively.
- Durable record:
  [row-to-law index](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026)
  and
  [bounded qualification](../zig-native/USAGE_CONTRACTS.md#bounded-implementation-and-qualification).
