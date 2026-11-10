# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

Actual whole177 checks 459 unchanged inputs in **155.05s**, then stops:

- `backend/core_backend.goose:1830`: module stamps retain the run-local module
  view (§9.2). Reborrow the existing pinned input owner before publication.
- `backend/resolved_body.goose:60`: global `source_runs` may retain payloads
  through `reuse/zig_project_server.goose:66` (§5.1). Its headers are invocation
  scratch; source text is copied by existing revision snapshots.

No C/header/native artifact exists. The prior whole173 scoped-diagnostic and
worker-request failures are cleared. Exact source/diagnostics:
[whole177](benchmarks/evidence/qualification/2026-11-10-goose-whole177.json.gz).

The actual scoped backend path now checks cleanly in **61.47s**, with unchanged
source. This is a partial check using deliberately invalid empty Core, not runtime
qualification: [selected176](benchmarks/evidence/qualification/2026-11-10-goose-scoped176.json.gz).
The recursive scoped run is removed. A cleanup-only helper preserves the 13
result-before-cleanup exits and original order. Internal diagnostics now store
only scalar unit/span/code/detail ID; public diagnostics expand at the result
boundary. All original string literals are unchanged; 61 exact message IDs have
matching lookup/render controls. No new owner, buffer, pool or allocation. Lookup
occurs only when recording a failure. Native diagnostic/executor/assembly laws
pass in **24.30s**, including scalar diagnostics across producer retirement and
Frame. See [the source audit](benchmarks/evidence/qualification/2026-11-10-goose-scalar-diagnostic-family.json.gz)
and [executed trio](benchmarks/evidence/qualification/2026-11-10-goose-scalar-diagnostic-laws.json.gz).

Both lower/check request publications now reborrow exact existing packet runs.
The executor law retires its producer, opens/releases a compiler Frame, then
reads the live request bytes. The executor/resolved-body pair passes **44.82s**:
[packet laws](benchmarks/evidence/qualification/2026-11-10-goose-lexical-packet-laws.json.gz).

The complete **32-law inventory passes in 288.97s at e514479e**, before this last
family. All stages keep their 30s cap. Do not present that older run as a complete
current-source gate: [complete32](benchmarks/evidence/qualification/2026-11-10-goose-complete32.json.gz).
Assembly retries own scratch lexically; cleanup remains bodies → parallel →
matcher → passes → profile, with original error/retry order. Native assembly,
collector rejection, owned packet/image round trips and profile hash controls
pass. Packet names/data retirement, Frame spanning of those Wasm images, real
process scheduling and full CLI/server remain pending. Slice-only packet copies
stage through a grow array; cost is not benchmarked.

## Contracts and remaining coverage

- Preserve ABI 8/session 2, named owners, invocation borrows, explicit copies,
  sibling sources/assets and the Zig oracle. Language tasks remain retired;
  copied-packet host workers remain.
- Planning requests hold scalar unit/range/rejection IDs over existing owners;
  no new graph/key pool or clone. Core/liveness traversal uses scalar cursors.
- Active child Generator remains at one address through emission, is cleaned
  once and restores its parent once. Workspace/query/Recorder publications name
  existing owners. Diagnostic/tape OOM laws preserve prior messages and errors.
- Native leaf laws never qualify full generator/probe/tape/CLI/server runtime.
  Known pending API coverage: artifact_import factory across Frame and
  host_cleanup_shapes.copyFields.
- Requirements and rejected experiments remain in
  [the storage task](tasks/STORAGE_REWRITE.md),
  [the language migration](docs/language/NEXT_MIGRATION.md) and
  [the receipt index](benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json).

## Tools and next checks

Use private checker `build/goose-port/argcopy-experiment-20261110/goose`, SHA256
`c2b24b697acfff54f5e89fb7eeb024fc2e528ff46e7582faf7714662d3067632`.
Its copied-argument recipe has 21 focused lifetime controls; exact storage
identity, deep reads and recursion rules remain intact. Installed Goose/678 are
unchanged; the separate origin-diagnostic checker is not promoted.

Selected roots are partial, check-only; scoped uses invalid empty Core. They do
not qualify runtime. Regenerate adapters for layouts, await completion, then
freeze source. Repair cap 120s, final emission 180s, whole 300s; stop 3s after a
reported error. Never lift caps, relax checks or clear live owners to hide errors.

Once the real executable exists, run compiler-goose/tools/qualify_compiler.ts
against it and compiler/zig-out-native-fast/bin/blotc. Eight matching Zig baseline
fixtures pass; Goose CLI/server/OOM/retry/retention have not run. Missing retained
bytes are pending, not zero. No ABI fallback.

Zig source is unchanged. Its prior full gate remains incomplete: all 2974 laws
compile without LLVM; release compilation hit its cap. Smoke, harness and zero
finding lint pass. Do not rebuild that release for each Goose edit. No fresh
current-port Gdev Main/frame exists. Historical Main 9,203,613B/5.523s belongs to
its older release; no reliable compile speed gain. Subsecond compilation,
sub-five-second Main and 1–2MB remain unmet. Environment publication and upstream
messages require explicit requests. Use Astra for concrete snags only; never Terra.
