# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

Latest actual whole212 stops in **152.92s**, unchanged460 inputs, no artifacts.
The old Capture/global-stamp failures are cleared. Its outer scoped/count wrapper
loan is repaired afterward; no newer actual whole attempt yet. See
[whole212](benchmarks/evidence/qualification/2026-11-10-goose-whole212.json.gz).

Focused preparation211 passes21.48s. New direct phase probes collect independent
errors together, all check-only/unstaged and NEVER executable. Latest seven-phase
batch232 stops112.76s: capture counter sign conversion (now fixed), specialization
row iteration across recursive layout mutation, and ambiguous substitution-buffer
header publication into an inactive sentinel. Both latter source families are now repaired; the next phase check is pending. Split probes as needed; keep120s repair cap. See
[phase family](benchmarks/evidence/qualification/2026-11-10-goose-phase-owner-family.json.gz).

Native Result diagnostic law passes **6.64s**: text survives scratch mutation and
source Frame cleanup, moved allocation/startup/explanation snapshots remain live,
detach is idempotent. Cohort/pipeline law passes **9.25s**: ordinary+preborrowed
bodies and region metadata detach, source mutation/teardown leaves the view
unchanged, replacement avoids recloning, repeated cleanup works. Exact receipts:
[Result](benchmarks/evidence/qualification/2026-11-10-goose-result-diagnostic-laws.json.gz),
[cohort](benchmarks/evidence/qualification/2026-11-10-goose-cohort-owned-laws.json.gz).
All48 lease retainers now return the same validated named-pool range, rather than
an incoming slice; no new copy/owner/allocation. Native lease/Recorder family
passes **6.92s**. [Lease law](benchmarks/evidence/qualification/2026-11-10-goose-retained-range-laws.json.gz).

Controlled filename and timing-census differentials isolate two retained caller
roots. Direct filename pool reads and static canonical census callers clear them;
label bytes/counters and allocation behavior remain. Timing keeps arbitrary owned
Result labels; the internal caller catalog/unknown-label assertion is unchanged.
[Controls](benchmarks/evidence/qualification/2026-11-10-goose-lease-timing-owner-boundary.json.gz).

Complete **36/36** native component inventory passes in **310.32s**, frozen source,
30s per stage and600s outer cap. [Full component receipt](benchmarks/evidence/qualification/2026-11-10-goose-complete36-owner-laws.json.gz).
This includes all prior laws plus Result diagnostics and strengthened cohort
storage. It does not qualify actual whole C/header/native or CLI/server execution.
Complete32 and the four-law4edf3a39 batches remain historical evidence.

Memo scratch is lexical after preparation reset and ends before Run cleanup.
Source validation/error/retry/publication order stays. Captures use existing
canonical registry keys. Outer backend routes are lexical; diagnostics own text
before cleanup. Cohort views eagerly copy instructions and optional region spans
into existing owners; activation models copy growing substitutions; source-origin
views own one identity snapshot. These added copies are unbenchmarked. Startup
graph builders use fixed temporary runs, freed after scalar graph construction.
All exact header snapshots, tokens/digests, ABI/session contracts remain.

CompileRun drops its duplicate module header and reads the existing pinned input
owner. Workspace/prior Pools reborrow checked canonical owners. Recorder reset
clears transient fields in place, preserving its tables and lease/generation.
Server source headers are invocation-local; the global scratch pool is removed.
Source/deletion/UTF8/assets validation and existing snapshot text copies remain.
Record-name maps hold scalar unit/name spans, resolving text in O(1) for exact
lexical ordering, duplicate checks and fallback. No name copying or new owner.

Compile identities now state their authority: CLI Metadata pools or a retained
project journal. Read-only observers validate exact existing runs; journal reads
work while shared and never call unique/mutable. All three journal producers pass
their actual owner key. The unused arbitrary-View entry is removed. No new pool,
registry or copy. Reusable server header capacity becomes local growth, and name
reads add an O(1) module lookup; these costs have not been benchmarked.

Scoped diagnostic carriers remain scalar; all original strings and 61 exact
lookup/render IDs are preserved. Assembly scratch is lexical and retains its
original cleanup/error/retry order. Current native leaf controls do not qualify
full generation, process scheduling, CLI/server or retained compilation runtime.
The complete compiler lifecycle and CLI/server/OOM/retry remain unqualified.

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
