# Finish the Goose compiler experiment

The current frontier, probe recipe and contracts live in
[the root CONTINUE.md](../CONTINUE.md). Evidence is indexed in
[the receipt index](../benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json);
remaining requirements are in [the storage task](../tasks/STORAGE_REWRITE.md).

A whole compiler executable builds with the patched Goose
(`tools/upstream-32a4f44/build.sh`, then `build.py`) and matched the Zig
compiler on 12 November. It is the scoped compiler of that date and cannot
read today's sources: [the plan](../tasks/GOOSE_PORT.md) has the state and
the steps. There is no forwarding to compiler/ and no ABI fallback.
