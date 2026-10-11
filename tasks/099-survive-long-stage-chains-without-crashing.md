# 099 — Survive long stage chains without crashing

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** None.
- **Originating requirements:** reported on 11 October 2026 by the gdev session
  while porting gdev's tests to Blot. Sources: that session's report.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

`blotc` reports a diagnostic or compiles, and never crashes, for modules with
long chains of nested stage functions.

## Starting point

A module with a chain of about 12–20 nested stage functions
(`const b = fn () => run (a ()) …`) called from many entries makes
`blotc serve-project` exit with signal 11 (exit 139); the client reports
"Unexpected EOF or truncated response frame". Some subsets of the entries
compile, and adding links to the chain made a compiling module crash. The repro
is a gdev game-mode test module (appended to gdev's `src/main.blot`), not yet
reduced without gdev. Task 091 moved compilation onto a 1 GiB reserved stack and
bounded constant evaluation by call depth; this may be another unbounded
recursion.

## Implementation checklist

- [ ] Reduce the crash to a public repro and find the faulting recursion or
      memory error.
- [ ] Bound it or make it iterative, with a positioned diagnostic where a limit
      is reached.
- [ ] Add a regression law at the reduced program's size and beyond.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- The reduced chain at increasing lengths, fresh and retained, CLI and server.

## Acceptance criteria

- [ ] Long stage chains compile or report a positioned diagnostic; the compiler
      process never crashes on them.
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
