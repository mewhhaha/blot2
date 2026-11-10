# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Preserve compiler/ as the oracle.

Focused prepare209 now stops in 21.29s at its caller: local Run may refer to
resolved-body payloads across preparation cleanup (§5.1). Incoming Capture/global
stamp errors clear on this path. Next is a copied lifecycle split: source-key
validation before reset, lexical memo after reset, memo scope ends before final
Run cleanup. The unstaged preparation root is check-only; never execute it.

Four affected native laws pass in 58.26s: exact stamp snapshots/mutation tokens,
independent memos, Capture keys, prepared inputs and resolved-body/shared-gate
teardown. Stamps use lexical growth and scalar checked source owners; Capture
views reuse their registry; workspace memo/counter/duplicate aliases are removed.
Local growth replaces pooled stamp capacity; cost is unbenchmarked.

Latest actual whole remains whole190: 157.73s, unchanged inputs, no artifacts,
incoming Capture error. It predates these repairs. Inventory now 35, not run
together; Complete32 at e514479e is historical coverage only. See root receipts
for exact source closures, rejected fixture attempts and runtime limitations.

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
