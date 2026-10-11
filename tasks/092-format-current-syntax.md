# 092 — Format current Blot syntax

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** None.
- **Originating requirements:** reported on 11 October 2026 by a separate
  session developing gdev; tooling. Sources: that session's report.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

`@mewhhaha/blot/format` formats every public example, the standard library and
current program syntax, and refuses only invalid sources.

## Starting point

gdev's `deno task fmt:blot` rejects every current gdev source with
`Island 48
rejected syntax`. On 11 October 2026 `formatSource` from
[compiler/format.ts](../compiler/format.ts) also rejected the public
`examples/ecs.blot` and `examples/syntax.blot` (at curried declarations such as
`const insert_cell = fn initial => fn builder => do:`), while it accepted
`std/prelude.blot` and a small `let … else:` block. The formatter predates the
Zig compiler, and `compiler/format.test.ts` does not format the examples.

## Implementation checklist

- [ ] Find which constructs the formatter's grammar lacks and support them, or
      format from the compiler's own syntax tree.
- [ ] Make formatting idempotent and preserve comments.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Format every public example and std module; check idempotence and that the
  formatted source compiles to the same Wasm.

## Acceptance criteria

- [ ] Every public example and std module formats, idempotently, to sources that
      compile to identical Wasm, with tests in the gate.
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
