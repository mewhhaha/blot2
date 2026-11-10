# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

Actual whole190 stops after **157.73s** with unchanged inputs and no artifacts.
Its sole error is `reuse/artifact_fragment.goose:102`: an incoming Capture value
retains the invocation's `old` reference (§9.2). The previous whole177 module-stamp
and server source-header failures are cleared. See
[whole190](benchmarks/evidence/qualification/2026-11-10-goose-whole190.json.gz).

A focused `prepare` root reproduces that same source error in **2.87s**. This is
an iteration improvement, not compiler throughput. The root traverses actual
preparation with deliberately unstaged inputs; never execute it. Source/diagnostic
history is in [the preparation receipts](benchmarks/evidence/qualification/2026-11-10-goose-prepare-boundary-family.json.gz).
The earlier actual scoped path checks cleanly in 61.47s at e3bf1904; it also uses
invalid empty Core and does not qualify runtime.

The affected five native laws pass in **63.48s**: record ordering, proof/Recorder
leases, identity authority, prepared input/session lifetime and server request
snapshot ownership. Exact closures, C/link/run logs and audits:
[executed family](benchmarks/evidence/qualification/2026-11-10-goose-preparation-owner-laws.json.gz).
The earlier input/server/proof trio passes 53.88s, before final strengthening.
Inventory is now **34**; it has not run together. Complete32 passes 288.97s at
`e514479e`, before the later families. Do not present it as current-source coverage.

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
The next Capture registry repair is prepared off-tree and not checkpointed yet;
reuse its existing registry and preserve the header key at core publish/reset.

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
