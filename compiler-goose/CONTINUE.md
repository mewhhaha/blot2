# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Preserve compiler/ as the oracle.

Actual whole190 stops in 157.73s with unchanged source and no artifacts. The
sole error is artifact_fragment102 storing an incoming Capture value (§9.2).
Previous module-stamp and source_runs errors are cleared. Its existing-registry
Capture reborrow repair is prepared off-tree; preserve header keys during publish.

Focused prepare reproduces the same error in 2.87s. This is partial/check-only,
with deliberately unstaged inputs; never execute it. The actual scoped path
checked cleanly in 61.47s at e3bf1904, also without runtime qualification.

Five current native laws pass in 63.48s: record ordering, proof/Recorder leases,
identity owners, prepared inputs and request snapshots. CompileRun uses pinned
inputs; Recorder resets in place; source headers are local; record names are
scalar coordinates. Identity views explicitly select Metadata pools or shared
journal authority and reborrow exact readonly runs without new copies/pools.

Inventory now 34, not yet run together. Complete32 passed 288.97s at e514479e
before later repairs; it is not a current full gate. Actual full compiler/process
runtime remains pending. See root frontier for exact evidence and tradeoffs.

Use private checker c2b24 at build/goose-port/argcopy-experiment-20261110/goose.
Installed Goose/678 and the off-tree origin checker are unchanged. Selected roots
are partial/check-only; scoped uses invalid Core. Repair cap 120s; emission 180s;
whole 300s; stop 3s after a reported error. No cap lifting/checker relaxation.

Preserve ABI 8/session 2, explicit owners/copies and sibling assets. Actual Goose
CLI/server/OOM/retry/retention awaits the real executable. Eight matching Zig
baseline fixtures pass. Zig source is unchanged; its prior full gate is
incomplete. See [the root frontier](../CONTINUE.md),
[the receipt index](../benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json)
and the storage/RFC tasks for requirements and remaining coverage.
