# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Preserve compiler/ as the oracle.

Actual whole177 stops after 155.05s with 459 unchanged inputs and no artifacts.
It clears the preceding diagnostic/request failures. Two new boundaries remain:
core_backend1830 publishes run-local module views to module stamps (§9.2), and
source_runs retains request payloads through zig_project_server66 (§5.1).

Selected176 now checks the actual scoped backend path cleanly in 61.47s. It uses
invalid empty Core and does not qualify runtime. Recursive scoped run is removed;
cleanup-only helper preserves all 13 result-before-cleanup exits. Scoped diagnostic
carriers are scalar; all original strings survive through 61 exact lookup/render
IDs. The native diagnostic/executor/assembly trio passes 24.30s. Executor/resolved
body laws pass 44.82s, including request bytes across producer retirement/Frame.

The complete 32-law inventory passed in 288.97s at e514479e, before this last
family. Stages retain 30s caps. Assembly retry ownership, cleanup, success/rejection,
worker-image copies and profile digest laws pass; full compiler/process runtime
is still pending. See the root frontier for exact scopes and limits.

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
