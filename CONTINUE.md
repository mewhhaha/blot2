# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

Latest focused prepare209 stops in **21.29s** at its caller: `prepare` shrinks
resolved-body payloads while local `Run` remains live (§5.1). The prior incoming
Capture store and global stamp scratch errors are cleared on that path. A copied
lifecycle split is next: validate source keys before reset, create the lexical
memo after reset, end its scope before final Run cleanup. Never execute the
unstaged preparation root. See
[the stamp iteration receipts](benchmarks/evidence/qualification/2026-11-10-goose-stamp-iteration-family.json.gz).

Four affected native laws pass in **58.26s**: exact stamp snapshots and mutation
tokens, independent lexical memos, live Capture/header keys, prepared input/session
lifetime, and actual resolved-body/shared-gate teardown. Exact closures and logs:
[executed family](benchmarks/evidence/qualification/2026-11-10-goose-lexical-stamp-owner-laws.json.gz).
The stamp law does not keep a memo across Frame; the Capture law separately keeps
real adopted semantic pins across Frame. Shared-gate checks reuse the existing
resolved-body fixture; adding full Gate construction to Capture hit its 30s cap.

The latest actual whole build is still whole190: **157.73s**, unchanged inputs,
no artifacts, incoming Capture store error. It predates this family. See
[whole190](benchmarks/evidence/qualification/2026-11-10-goose-whole190.json.gz).
Inventory is **35** and has not run together. Complete32 passed 288.97s at
`e514479e`, before later repairs; it is not current full coverage.

Capture views reborrow their existing registry slot/token, validate canonical
pointer identity, and preserve keys on core publish/reset. Fragment importer
leaves reborrow named Pools and module-header runs. Checkpoint readers use the
existing checked slot/generation. Shared gates retain owned flag runs and borrow
only the explicitly supplied exact source/identity pair.

Stamp entries are invocation-local growing storage; the workspace/global memo,
retirement counter and duplicate source-pointer/optional memo fields are removed.
Source binding validates exact publication/Context owners; scalar keys reborrow
those same headers. Entries still snapshot full headers by value, preserving
header-change tokens and digest/comparison behavior. Local growth replaces pooled
stamp capacity; its cost has not been benchmarked.

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
