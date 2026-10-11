# 097 — Resolve array cursor representation in gdev fixtures

## Status, dependencies, and originating requirements

- **Status:** Complete.
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
- [x] Find why specialization reaches the cursor without concrete representation
      evidence and fix the compiler, not the program.
- [x] Add a regression law for the reduced program.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- The reduced program compiles and runs; the 16 gdev tests compile.

## Acceptance criteria

- [x] The reported fixtures compile, with a public regression law.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementations: `f2b41b4` preserves partial physical shapes without
  defaulting language types; `881c6ab` parks pending selections until their
  unknown receiver changes, removing retries that exhausted inference on the
  remaining fixture.
- Validation: Zig 0.17.0; full native suite and 690 guest/client tests pass.
  Analyzer: zero findings across 318 files, including three unregistered asset
  files under development. Native step-bound and executed-Wasm
  rejection/recovery laws qualify the public reduction.
- gdev: all 472 cases across 54 current regular modules pass; the remaining
  blocked split-hauling module compiles and passes 12 exports/25 assertions.
  Formerly blocked app/sandbox cases are in the regular suite. This qualifies
  the current checkout, whose fixture layout changed after the original report.
- Comparison: all 13 public examples, four synthetic workloads and frozen gdev
  preserve Wasm bytes. Public 51-stage inference steps fall 974,824 → 269,363;
  obligations/type nodes remain unchanged. Three paired gdev samples establish
  no general CPU improvement.
- Remaining limitations: generic-chain type/obligation growth remains quadratic;
  101 stages still reject under the unchanged one-million-step inference budget.
  Requested/peak allocation rises slightly from queue watches.
- Durable records:
  [partial collection layouts](../zig-native/PARTIAL_COLLECTIONS.md) and
  [pending selections](../zig-native/PENDING_SELECTIONS.md), with executable
  pins and paired samples.

[099]: 099-survive-long-stage-chains-without-crashing.md
