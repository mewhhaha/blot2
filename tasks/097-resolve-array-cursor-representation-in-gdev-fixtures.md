# 097 — Resolve array cursor representation in gdev fixtures

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** None.
- **Originating requirements:** reported on 11 October 2026 by the gdev session:
  16 gdev tests fail to compile. Sources: that session's report.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Programs that reach `Array.iter` through gdev's app world encoding compile
instead of failing code emission.

## Starting point

The gdev session reduced it to a program without gdev:

```blot
const count = fn xs => do:
  let n = 0
  for x in xs:
    n := self + 1
  return n
entry const create = fn () => count #[]
```

It fails with
`unresolved_type: Code emission requires concrete representation
evidence` at
`std/prelude.blot` 13092–13144
(`const Array.iter = fn values =>
@array.cursor values`): the empty array leaves
its element type unpinned, and specialization reaches the cursor without a
representation for it. `count
#[1]` compiles. A data type parameter left
unpinned (`count #[#A 1]` with `type
Box [a, b] is data = | #A a | #B b`) fails
the same way. In gdev, fixtures that never call `app.advance`/`app.render` leave
`System`'s `update` and `render` parameters unpinned in `run_start`'s
`for system in systems:`; 16 gdev tests fail. Every compiler back to `f7be6e7`
and every gdev commit back to `8205126` fail identically. Evaluating the worlds
as constants instead fails `app.restore` with `ambiguous_associated` at the
prelude's `from`, which may be the same gap.

## Implementation checklist

- [x] Reduce the failure to a public repro without gdev source.
- [ ] Find why specialization reaches the cursor without concrete representation
      evidence and fix the compiler, not the program.
- [ ] Add a regression law for the reduced program.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- The reduced program compiles and runs; the 16 gdev tests compile.

## Acceptance criteria

- [ ] The reported fixtures compile, with a public regression law.
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
