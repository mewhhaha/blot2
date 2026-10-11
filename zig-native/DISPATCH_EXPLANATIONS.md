# Dispatch explanations

Task 048 makes a failed dispatch say what it tried. Before it, `1 + 2.5`
reported only "Neither operand has a compatible associated implementation", at
the prelude's `@type.call` inside `add`, with no word about which types were
searched or why each was rejected.

## What a diagnostic carries

[dispatch_explanation.zig](src/dispatch_explanation.zig) defines an owned
`Explanation`: the operator symbol, the member looked up and up to four
candidates in the order dispatch considered them. Each candidate has a side, its
type as diagnostics spell it, and an outcome:

| Outcome              | Meaning                                                                 |
| -------------------- | ----------------------------------------------------------------------- |
| `unknown_operand`    | The type is still unknown, so it names no owner                         |
| `no_member`          | The type declares no member with this name                              |
| `incompatible`       | The member exists, but its signature rejects the operands               |
| `unsupported_scalar` | Both operands are a scalar without this built-in operation              |
| `result_mismatch`    | Selected from its operands; its result conflicts with the expected type |

Sides follow dispatch exactly: `left`, then `builtin` (an unnamed operator over
equal scalars), then `right` unless its owner is the left's. `@type.result`
looks only at its `destination`, and member access only at its `receiver`, never
at argument types. Nothing follows a `result_mismatch`, because dispatch tried
nothing after it.

The CLI writes it as `details.explanation`; the project server forwards it; the
client decodes it as `diagnostic.explanation` with
[readDispatchExplanation](../compiler/type_diagnostics.ts), which copies only
known fields and rejects unknown sides or outcomes, more than four candidates,
spellings over 256 UTF-8 bytes and malformed strings.

## Where explanations are built

- The checker attaches an explanation to `ambiguous_operator`,
  `missing_associated`, `ambiguous_associated`, receiver `missing_member`, and
  to the `type_mismatch` raised when a selected binary member's result conflicts
  with its use. It reads member tables and resolved operand types only.
- The evaluator's `select`, `resultSelection` and closure-region constraints
  record a plain `DispatchRecord` inside their diagnostic. On failure the
  backend spells it with the entry-interface type display, so nominal types are
  module-qualified (`main::Box`, `library.blot::Meters`), and member names come
  from the build's identity view.

Explanations change no selection, no selection order and no reported diagnostic.

## Qualification on 11 October 2026

- Zig 0.17.0. `deno task test:compiler` passes the full native suite and 645
  guest/client tests; `deno task lint:zig` reports zero findings across 313
  files. The milestone is `67e7912`.
- [Native laws](src/dispatch_explanation_tests.zig) check, for each stage that
  reports it: receiver lookup that ignores an argument's member, left before
  right with `incompatible` and `no_member`, an identical right owner listed
  once, result dispatch, a selected left member whose result conflicts while
  the right member would fit, and a generic callback. A 300-byte type name is
  cut to 256 bytes on a UTF-8 boundary and marked truncated. An
  allocation-failure sweep covers checker and backend explanations; a mutant
  that lists an identical right owner fails the law.
- [A process law](tests/dispatch_explanation.test.ts) checks `1 + 2.5` and
  `#True + #False` through the CLI with the standard prelude; a project server
  session that fails on an imported type without `add`, explains a selected
  member's result conflict, and recovers to the original Wasm; and a type from a
  compiled dependency bundle.
- [Client tests](../compiler/type_diagnostics.test.ts) reject malformed
  explanations and drop unknown fields.
- Every public example and the frozen gdev copy emit byte-identical Wasm (gdev
  SHA-256 `3158216b…def0`, 840,534 bytes). Successful compilation does no new
  work beyond recording which side a dispatch selected, so no timing comparison
  was run.

## Remaining scope

- Explanations accompany diagnostics only. There is no editor query that shows
  why a successful dispatch chose its member.
- Failures found while specializing are still located at the callee's
  `@type.call`, for operators inside `std/prelude`, not at the user's operator.
  Task [094](../tasks/094-locate-specialization-failures-at-their-use.md) moves
  them.
- A user-written `@type.call` whose result conflicts later is reported at the
  conflicting annotation without an explanation; the checker explains result
  conflicts only for dispatch it solves as a pending obligation, which includes
  every operator.
- The evaluator also records `result_mismatch` for a selected member, but no
  source program was found that reaches it: the checker reports those conflicts
  first. A closure region's result conflict carries no explanation.
- Emit-stage spellings are module-qualified and omit shapes without a source
  name, such as records; checker spellings are bare names.
