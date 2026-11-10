# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Preserve compiler/ as the oracle.

Actual whole173 stops after 151.03s with 458 unchanged inputs and no artifacts.
Two errors remain: scoped_backend2604 diagnostic publication inside recursive
run (§7.8), and process_requests retaining payloads through project_executor61
(§5.1). Their lexical-factory/exact-packet-owner repairs are prepared off-tree.

The complete 32-law component inventory passes in 288.97s: actual C emission,
linking and native execution with unchanged import closures. Stages retain the
30s cap. The affected assembly trio separately passes in 18.06s. Assembly now
owns retry scratch lexically, preserving cleanup/error/retry order. The new
fixture covers success/rejection cleanup, packet source retirement and profile
hash parity; nonempty names/data, Frame and process scheduling remain pending.
These laws do not qualify the complete compiler runtime.

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
