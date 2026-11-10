# Continue the Goose compiler experiment

Finish coherent ownership repairs, build the **actual complete C/header/native
Goose compiler**, then qualify CLI/server, request OOM/retry and retention against
Zig. **No whole compiler artifact exists.** Component laws never substitute for
integrated qualification; do not forward Goose requests to the Zig oracle.

## Current frontier and evidence

All **30 production helper laws pass together in 221.34s** at map checkpoint
`f0a602bc`. Exact sources, toolchains, C, native objects and executions are pinned
in [the complete receipt](benchmarks/evidence/qualification/2026-11-10-goose-complete30.json.gz).
Later backend/owner repairs have affected executed laws; the final five-law
checkpoint passes in 55.21s (proof leases, resolved bodies, cache, footprint and
outline), with pinned C/link/runtime evidence in
[the affected receipt](benchmarks/evidence/qualification/2026-11-10-goose-backend-checkpoint-five.json.gz).
Full qualification remains pending.

Actual whole141 stops after **143.58s**, without artifacts, at SIMD initialization
and cached-plan publication. Both source families have subsequent repairs. See
[the pinned whole attempt](benchmarks/evidence/qualification/2026-11-10-goose-whole141.json.gz).
Broader strict scoped145 finishes in 47.31s and reaches recursive-contract
publication plus retained constant-query state. The contract header is now
reconstituted through its existing pool. The remaining retention diagnostic is
`resolved_body.deinit`: global constant `state_owners` may retain payload storage
through `core_backend.constantLookup`. A copied diagnostic identifies an inexact Generator-root class propagated
through pairedImporter, rather than a concrete payload reference. Exact State
reborrowing is being tested. No checker relaxation or live-owner clearing is
authorized.

The strict `scoped` diagnostic uses deliberately invalid empty Core. Early
failures take 19–21s; broader checks take about 47–50s. It is **check-only**, never
runtime qualification. Scoped140's 30s no-diagnostic timeout remains incomplete.
Repair stages retain the standard 120s cap; final emission uses at most 180s
inside a 300s whole-build budget. Stop 3s after an actual diagnostic. Do not lift
caps to hide unfinished work. Bulk-error experiments remain off-tree without a
demonstrated production gain.

## Current source contracts

- Value/Root spellings and active goals use existing arena ranges; recursive
  traversals reload flat elements instead of retaining vector views.
- Both child Generator emission paths save/install/recurse/extract/restore at the
  same threaded address. Parent aliases are dormant during child emission;
  restoration precedes error handling and exactly-once cleanup. Minimal native
  controls pass; actual generator runtime remains pending.
- Specialization keys compare evidence contents. Cache laws cover deduplication,
  chains, completion fallback, rollback and wrapped collisions. One owner-aware
  removal API serves all 78 production calls without extra pools.
- Worker/archive headers use their existing checked journals. Persisted retains
  only its scalar Frozen owner; alias prefixes copy into their canonical owner.
- Query caches retain owned inspection metadata and reconstruct invocation-local
  Plan views. Retained evidence imports reborrow checked Store handles.
- QueryScratch retains live Gate, Pools and exact lease keys instead of borrows.
  Equivalent copied owned headers intentionally compare equal; stale/mismatched
  authorities reject. Its packed layout grows **514→1102B**. A candidate-only
  unoptimized probe measures 10,000 binds in 4.047ms; no whole-compiler speed claim.
- Private transport anchors contain only binding IDs; the query carries field
  spelling unchanged. Catalog search preserves order, privacy, budgets and cache
  behavior using separate lexical borrows. Control/deferred-copy publication and
  cleanup reconstitute existing named runs.

Known additional unqualified legacy API: `host_cleanup_shapes.copyFields` cannot
republish borrowed Field.name from its input slice. Its recorded failed fixture
is preserved; the new cleanup law directly allocates its input in owned_fields
and qualifies deinit only. Do not claim the shape factory passes.

Exact family receipts and historical checkpoints remain in
[the completion frontier](benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json).

## Toolchain and remaining qualification

Use the pinned private copied-argument checker at
`build/goose-port/argcopy-experiment-20261110/goose`, SHA256
`c2b24b697acfff54f5e89fb7eeb024fc2e528ff46e7582faf7714662d3067632`.
Its optional recipe and 21 lifetime controls are recorded in
[the private tooling receipt](benchmarks/evidence/qualification/2026-11-10-goose-copied-argument-contents.json.gz).
Installed Goose and the qualified678 binary remain unchanged. Exact storage
identity, deep/reference reads and recursive conservatism remain intact.

Preserve ABI 8/session 2, named owners, explicit copies and invocation-local
borrows. Language tasks remain retired; copied-packet host workers remain.
Current Blot syntax is `func`, explicit `return`, curried `->`, `$Constructor`,
Boolean primitives and `#[...]` arrays. Preserve compiler/ and sibling assets.

`qualify_compiler.ts` has eight matching-language Zig oracle baseline passes,
but has **not run against Goose**. Native supervisor/transport/cache controls use
a fake compiler entry; actual compiler OOM/retry/retention remain pending.
Unavailable live-byte counts are not zero. The required Zig full gate remains
incomplete: all 2,974 laws compile without LLVM, but the LLVM release phase hit
120s and cancelled after 94 laws/65 full sweeps. Smoke/harness and zero-finding
lint pass. Zig source is unchanged; do not repeat that release build per Goose edit.

Named-function migration across std/Ink/Gdev is checkpointed; source inventory is
not fresh Main/frame qualification. Historical Main is 9,203,613B/5.523s on its
older pinned release, with no reliable compilation gain. Subsecond compilation,
sub-five-second Main and 1–2MB output remain unmet. Preserve the remaining RFC,
runtime/export and performance requirements in
[tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) and
[docs/language/NEXT_MIGRATION.md](docs/language/NEXT_MIGRATION.md).
Environment publication and upstream comments/issues require explicit requests.
Use Astra for concrete snags; never Terra.
