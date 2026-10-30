# 092 — Format current Blot syntax

## Status, dependencies, and originating requirements

- **Status:** Complete at `f6098a8`.
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
`const insert_cell = func initial => return func builder => return do:`), while it accepted
`std/prelude.blot` and a small `let … else:` block. The formatter predates the
Zig compiler, and `compiler/format.test.ts` does not format the examples.

## Implementation checklist

- [x] Find which constructs the formatter's grammar lacks and support them, or
      format from the compiler's own syntax tree.
- [x] Make formatting idempotent and preserve comments.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Format every public example and std module; check idempotence and that the
  formatted source compiles to the same Wasm.

## Acceptance criteria

- [x] Every public example and std module formats, idempotently, to sources that
      compile to identical Wasm, with tests in the gate.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `f6098a8` ("Format nominal record patterns and named operators").
- Cause: in `grammar.baba`, a constructor pattern accepted either record fields
  or any pattern as its payload, and `pattern` includes record patterns, so
  `#Vec2 { x, y }` had two derivations and the `pattern` island (number 48)
  rejected it. Every failing declaration in the examples and gdev used a nominal
  record pattern. Separately, the formatter glued a named operator's right
  operand to its closing backtick (`` `plus`22 ``).
- Change: `constructor_payload` excludes bare record patterns and is its own
  root island in `baba.json`; `deno task generate:parser` regenerated the parser
  (the committed output matched the old grammar exactly). Only the opening
  backtick of a named operator is tight.
- Validation: `deno task test:compiler` passes the full native suite and 638
  guest/client tests; `deno fmt --check compiler` and `deno check` pass. New
  formatter tests cover nominal record patterns in `let` and `case` and
  named-operator spacing, and format every public example and std module
  idempotently and compile the formatted sources through the project server to
  the same Wasm as the originals. Locally, all 60 sources of the frozen gdev
  copy format idempotently, and the formatted copy builds to byte-identical Wasm
  (840,534 bytes).
- Comparison: not a compiler performance change.
- Remaining limitations: the formatter still parses with the Baba grammar,
  separate from the Zig parser, so the two can diverge again; the gate now
  catches that for the public examples and std modules only. gdev picks the fix
  up when the package is published.
- Durable record: [grammar.baba](../grammar.baba) and
  [compiler/format.test.ts](../compiler/format.test.ts).
