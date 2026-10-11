# 087 — Skip rebuilds for trivia-only edits

## Status, dependencies, and originating requirements

- **Status:** Complete — local milestone `eaf02d7`.
- **Dependencies:** none.
- **Originating requirements:** discovered while qualifying task
  [085](085-gate-principal-graph-sharing-on-payoff.md); PLAN: Hill 6 / cheap
  edits. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

An edit that changes only comments, blank lines or other trivia publishes the
previous revision's output and semantic results with updated source positions
instead of rebuilding.

## Starting point

A separate session measured gdev's dev loop with the task-024 compiler: a
comment-only edit in one module costs the full 1044–1077 ms (`generate_us`
735–768 ms, `reused_output: false`) and emits byte-identical Wasm. Retained
revisions already reuse output for unchanged sources; any byte change, including
trivia, currently invalidates the module's syntax, Core spans and everything
downstream.

## Implementation checklist

- [x] Decide which source changes are trivia (comments, whitespace that does not
      change layout-sensitive structure) and prove the token stream otherwise
      identical, including indentation-significant blocks.
- [x] Reuse the previous output and retained artifacts while updating every
      source position that diagnostics, debug names and later edits read.
- [x] Keep diagnostics, failed-revision rollback and fresh/retained equality
      exact.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Comment, blank-line and indentation edits, including ones that do change
  layout; a later real edit and a later error must report current positions.
- Measure trivia-only and following edits against fresh builds.

## Acceptance criteria

- [x] Trivia-only edits avoid backend work while later diagnostics carry the
      current positions.
- [x] Layout-changing whitespace still rebuilds.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `eaf02d7f90a2cf741ab06cb77dc4855a1e39bdfb` (compiler milestone).
- Implementation: a source is trivia-equal to the last compiled one when both
  lex cleanly to the same token tags, spellings and adjacency (layout tokens
  included) within size limits. When every input is byte- or trivia-equal, the
  settings and canonical entry match and the last revision compiled, the
  retained session publishes the last output and keeps its state. Positions are
  not patched: a reused successful revision exposes none, and the next real edit
  recompiles from the new sources. The reuse gate now compares obligations
  without their diagnostic spans, so shifted positions no longer disable reuse
  program-wide.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 633 guest/client tests;
  `deno task
  lint:zig` reports zero findings across 310 files. Native laws
  classify trivia, layout and adjacency edits (with an allocation sweep) and
  check retained reuse; a gate law (failing with exact obligation comparison)
  keeps the catalog across shifted spans; a process-level law compares bytes and
  diagnostics with fresh builds through trivia, real, failing and recovered
  edits on three examples.
- Comparison: three pairs on the frozen gdev copy at load 2–4: comment-only
  edits 930–950 ms (then ~710 ms) → 0–10 ms; the first literal edit after a
  comment edit costs 1010–1040 ms versus ~825 ms for a plain literal edit, which
  is unchanged. Baseline `b822ccf` (sources of `7d64435`).
- Remaining limitations: a layout or adjacency change is a real edit; the first
  real edit after trivia diffs against the pre-trivia sources, so declarations
  after shifted positions rebuild (about 200 ms more on gdev).
- Durable record: [trivia-only edits](../zig-native/TRIVIA_EDITS.md),
  [distributions](../zig-native/qualification/trivia-edits-gdev.csv) and
  [pins](../zig-native/qualification/trivia-edits-pins.json).
