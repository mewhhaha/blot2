# Finish the Goose compiler experiment

Repair coherent ownership families, emit the actual complete C/header/native
compiler, then qualify CLI/server, request OOM/retry and retention against Zig.
**No whole compiler artifact exists yet.** Preserve compiler/ as the oracle.

All 30 helper laws pass together in 221.34s at map checkpoint `f0a602bc`;
[the complete receipt](../benchmarks/evidence/qualification/2026-11-10-goose-complete30.json.gz)
pins its sources and actual C/link/runtime results. Later repairs have affected
laws; the final five-law checkpoint passes in 55.21s; full qualification is pending.

Whole141 stops143.58s without artifacts at SIMD initialization/cached-plan
publication. Source repairs follow. Strict scoped145 takes47.31s, reaching
recursive-contract publication and retained constant-query state. The contract
header is now reconstituted through existing access_pool. Remaining failure:
`resolved_body.deinit` sees payload storage retained by global constant
state_owners through core_backend.constantLookup. A copied trace identifies an inexact Generator-root class at pairedImporter;
exact State reborrowing is under test. Do not relax the checker or clear live owners.

The scoped root is check-only with invalid empty Core. Early failures take
19–21s; broader checks take47–50s. A30s no-diagnostic timeout was incomplete.
Repair cap120s, final emission180s, whole build300s; stop3s after a diagnostic.
Regenerate adapters once, then freeze sources before checking. Never overlap
adapter generation and helper fingerprinting.

Current family uses same-address child Generator context save/restore, scalar
transport anchors, lexical dispatch catalogs, exact Control/deferred-copy runs,
owned plan metadata and checked retained Store handles. QueryScratch uses live
owner/generation/lease keys, accepting equivalent copied owned headers and
rejecting stale/mismatched authorities. Layout514→1102B; 10k candidate binds
measure4.047ms at-O0, no whole-compiler performance claim. Actual generator,
CLI/server and OOM/retention qualification remain pending.

Known unqualified legacy API: host_cleanup_shapes.copyFields republishes a
borrowed Field.name. Its failing fixture is recorded; cleanup laws qualify only
deinit with directly owned input. Do not infer factory success.

Use `build/goose-port/argcopy-experiment-20261110/goose` and its pinned optional
copied-argument recipe; installed Goose/qualified678 are unchanged. Preserve ABI8,
session2 and explicit owner/copy contracts. Native adapters never compile Blot.
No unavailable live-byte count is zero. Zig source is unchanged and its prior
full gate remains incomplete; see [the root frontier](../CONTINUE.md) and
[exact receipts](../benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json).
Unmet language/runtime/performance requirements remain in the storage task/RFC.
