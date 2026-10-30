# 099 — Survive long stage chains without crashing

## Status, dependencies, and originating requirements

- **Status:** Complete.
- **Dependencies:** None.
- **Originating requirements:** reported on 11 October 2026 by the gdev session
  while porting gdev's tests to Blot. Sources: that session's report.
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

`blotc` reports a diagnostic or compiles, and never crashes, for modules with
long chains of nested stage functions.

## Starting point

A module with a chain of about 12–20 nested stage functions
(`const b = func () => return run (a ()) …`) called from many entries makes
`blotc serve-project` exit with signal 11 (exit 139); the client reports
"Unexpected EOF or truncated response frame". Some subsets of the entries
compile, and adding links to the chain made a compiling module crash. The repro
is a gdev game-mode test module (appended to gdev's `src/main.blot`), not yet
reduced without gdev. Task 091 moved compilation onto a 1 GiB reserved stack and
bounded constant evaluation by call depth; this may be another unbounded
recursion.

## Implementation checklist

- [x] Reduce the crash to a public repro and find the faulting recursion or
      memory error.
- [x] Bound it or make it iterative, with a positioned diagnostic where a limit
      is reached.
- [x] Add a regression law at the reduced program's size and beyond.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- The reduced chain at increasing lengths, fresh and retained, CLI and server.

## Acceptance criteria

- [x] Long stage chains compile or report a positioned diagnostic; the compiler
      process never crashes on them.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementation: `5340ef2`. The fault was an unchecked slice of empty checker
  catalogs after budget exhaustion. Export handling safely skips sentinel
  indices, preserving the existing owned, positioned `inference_budget`.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 653 guest/client tests.
  `ZIG_ANALYZER=build/tools/zig-analyzer/zig-out/bin/zig-analyzer deno task lint:zig`
  reports zero findings across 315 files. The focused native rejection law and
  both executed CLI/server laws pass.
- Public reduction: 64 callbacks with 51 links compiles at 974,824 inference
  steps; 52 and 64 links report positioned diagnostics. CLI publishes no output
  and reports zero live requested bytes. Retained rejection agrees with fresh
  sessions and recovery preserves Wasm plus the executed result, 204.
- Comparison: the successful 51-link control preserves complete checker counters
  and 13,077-byte Wasm. Binary pins and one control pair are recorded;
  uncontrolled load and concurrent builds prevent any CPU speedup claim.
- Remaining limitations: large unresolved callback chains still exceed the
  existing inference budget. The original gdev split-hauling fixture now exits 1
  with `inference_budget` instead of signal 11; it remains uncompiled. Task
  [097] retains that separate compilation qualification.
- Durable record:
  [stage-chain rejection](../zig-native/STAGE_CHAIN_REJECTION.md) and
  [binary pins](../zig-native/qualification/stage-chain-rejection-pins.json).

[097]: 097-resolve-array-cursor-representation-in-gdev-fixtures.md
