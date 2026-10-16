# 062 — Implement resource cleanup contracts

## Status, dependencies, and originating requirements

- **Status:** In progress — scope closed to fixed language-qualification rows by
  owner decision on 15 October 2026; waiting for a passing full gate on current
  source.
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

- [ ] Lower checked cleanup obligations on returns, breaks, branch exits, scope
      completion and cancellation.
- [ ] Transfer cleanup responsibility with ownership, never with a mere borrow;
      handle suspended frames and host exceptions according to the specified
      contract.
- [ ] Serialize resource/usage evidence so compiled callers cannot omit cleanup
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

- [ ] Each owned resource receives exactly the cleanup required on every
      supported exit.
- [ ] Separate compilation preserves usage/lifetime contracts and invalid
      borrowed escapes are rejected.
- [ ] Applicable checks pass and completion evidence records remaining
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
freeze `3548546c…`, but the current working tree failed 20 native laws on the
evening of 15 October, so completion waits for a passing gate on current source.
The original acceptance index
(`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`)
was removed with `build/`; regenerate the row-to-law mapping from the passing
gate's native test names and guest JUnit report and record it durably in
[LANGUAGE_QUALIFICATION.md](../zig-native/LANGUAGE_QUALIFICATION.md).

## Completion evidence

- Commit: pending; record the local milestone revision.
- Focused evidence: Zig 0.17.0, 24 combined usage/resource native laws and four
  backend laws pass, including complete allocation sweeps (177 source/Core and
  311 backend failures). Three resource guests cover scalar payloads, managed
  callback results, early returns/breaks, reverse cleanup, traps, failed
  acquisition/cleanup and host throw/rejection in both tiers and sync/JSPI.
  Across 4096 failure/recovery calls, roots, leases and host references return
  to zero and warmed memory stays flat. Pending JSPI retains ownership until
  settlement and blocks reentry/disposal. Imports, failed revisions, portable
  checkpoint and restart preserve bytes. Four journal controls include 10000
  sequential scopes and the 4096 live-reservation limit; typed ABI mutants
  reject before invocation. The earlier isolated 416-file analyzer claim is
  withdrawn because its Zig/std backend was missing. The isolated candidate
  still needs combined release qualification.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Reference continuation: Array/List payloads of unqualified primitives reuse
  ABI 4 and the same journal, with independently checked source/Core shapes and
  a reference adapter that drops payload/closure/provider roots after cleanup.
  Four new native laws, eleven related laws and two both-tier guest groups pass,
  including allocation sweeps, trap/host rejection, JSPI settlement, returned
  managed results, archive/checkpoint restart and failed revisions. Selected
  328-file Zig lint has zero findings under the verified Zig/std backend.
- Remaining limitations: other reference shapes, cross-invocation resource
  obligations, host cleanup authority, finite loop/recursive adapter evidence
  and request cancellation through resource-carrying frames remain open.
  Unsupported cleanup calls/projections and standalone cleanup qualifiers
  reject. No broader ownership or cancellation completion is claimed.
- Durable record:
  [bounded qualification](../zig-native/USAGE_CONTRACTS.md#bounded-implementation-and-qualification).

- Transfer continuation: counted owning boxes preserve one journal obligation
  through moves, shared aliases and once captures within an invocation. Normal
  block/branch/loop exits, break, explicit release, traps and JSPI rejection run
  cleanup outside heap transactions. Source/Core startup and captured-loan
  negatives, live weak-box/child-mask mutants, atomic publication failure,
  source/archive/restart and complete backend OOM/replay controls pass. Both
  tiers and sync/JSPI run 4608 repeated calls with zero ownership counters and
  flat warmed memory; 5000 sequential resources do not exhaust journal capacity.
  Owning scalar/numeric-Array inputs are freshly boxed; owning public outputs
  reject. The combined gate and broader host/request lifetime contracts remain
  required. This continuation does not mark the task complete.
