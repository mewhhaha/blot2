# 062 — Implement resource cleanup contracts

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

[runtime_cleanup.zig](../zig-native/src/runtime_cleanup.zig) already tracks
private runtime scopes; tasks 061 and 033 add checked resource use and suspended
ownership. Portable semantic interfaces come from task 020.

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

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task; record commands, versions, results and
  evidence links.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
