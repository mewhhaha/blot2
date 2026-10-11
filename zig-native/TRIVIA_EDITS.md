# Trivia-only edits

Task 087 makes an edit that changes only comments or spacing publish the last
output instead of rebuilding. A separate session measured gdev's dev loop: a
comment edit cost the full retained build (about 1.05 s) and emitted
byte-identical Wasm. The compiler milestone is
`eaf02d7f90a2cf741ab06cb77dc4855a1e39bdfb`.

## Rule

[`revision_inputs.Snapshot.triviaEqualsPrevious`](src/revision_inputs.zig)
compares a new input snapshot with the last compiled one exactly like
`equalsPrevious` (options, canonical paths, import resolutions and every source
read), except that a source may also differ when `sameTokens` holds: both sides
lex cleanly to the same token tags and spellings, with the same adjacency
between consecutive tokens. Layout is part of the token stream, and the parser
reads only those facts and the relative order of positions (adjacent `(` and `[`
select calls and indexing), so such sources parse to the same program at other
positions. Hygienic loop names no longer depend on positions (task 024). Size
limits still apply to the new sources.

[The retained session](src/retained_revision.zig) then reuses the previous
output as for an unchanged revision when the previous revision compiled, the
settings and canonical entry path are equal, and the inputs are trivia-equal.
The retained state is kept, so the next real edit diffs against the last
compiled sources. `attemptStats.trivia_only` reports the reuse.

## Catalog positions

A trivia shift that accompanies a real edit, or any body edit that changes a
module's length, moved obligation spans. `catalogEqual` compared obligations
exactly, so the reuse gate turned off for the whole program and every function
was rebuilt (960 fresh functions on gdev for a comment edit). Obligation spans
locate diagnostics only, so [the gate](src/principal_reuse_gate.zig) now
compares obligations with their spans cleared; declarations still compare node
spans, so shifted declarations are revoked individually.

## Qualification on 11 October 2026

The baseline is the task-085 compiler (`7d64435`); binaries and inputs are
pinned in [the pins](qualification/trivia-edits-pins.json).

- Zig 0.17.0 before every build batch. `deno task test:compiler` passes the full
  LLVM native suite and 633 guest/client tests; `deno task lint:zig` reports
  zero findings across 310 files.
- [Native laws](src/revision_input_tests.zig) fix which edits are trivia:
  comment changes, trailing comments and spacing between separated tokens are;
  spacing that makes `values[0]` an argument or `helper(…)` a call, leaving a
  suite, a changed literal and a source with lexer diagnostics are not; with an
  allocation-failure sweep.
  [A retained-session law](src/source_overlay_tests.zig) reuses the output for a
  commented dependency and compiles the next real edit.
- [A gate law](src/principal_reuse_gate_tests.zig) shifts obligation spans with
  a longer comment and a scalar edit: the gate stays enabled and the shifted
  declarations are revoked. It fails with exact obligation comparison.
- [A process-level law](tests/trivia_edit_reuse.test.ts) edits ecs, syntax and
  monads through comment, trailing-comment and spacing edits, an added
  declaration, a failing edit, recovery and a trivia revert: bytes and
  diagnostics equal fresh builds and `trivia_only` is reported exactly when the
  inputs are trivia-equal to the last compiled revision.

Three pairs on the frozen gdev copy at load 2–4
([CSV](qualification/trivia-edits-gdev.csv)), CPU per retained edit:

| Sequence                                    | Task-085 compiler        | Candidate                     |
| ------------------------------------------- | ------------------------ | ----------------------------- |
| Comment-only edits                          | 930–950 ms, then ~710 ms | 0–10 ms                       |
| Comment edit, then literal edits keeping it | 920–940, then ~810 ms    | 0–10, 1010–1040, then ~825 ms |
| Literal edits                               | ~825 ms                  | ~825 ms                       |

The baseline rebuilt all 960 functions for a comment edit because shifted
obligation spans disabled the gate. The candidate skips the comment edit; its
next real edit keeps reuse (110 fresh functions) but pays about 200 ms more than
a plain literal edit, because the edited module is no longer structurally equal
to the last compiled one.

## Remaining scope

- A trivia edit that changes layout or adjacency is a real edit.
- The first real edit after a trivia edit diffs against the pre-trivia sources,
  so declarations after a shifted position are not exact and rebuild.
- Reuse requires a successful previous revision. Successful builds report no
  diagnostics, so no source position is reused.
