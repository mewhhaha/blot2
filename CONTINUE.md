# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

**No complete C/header/native Goose compiler exists.** Actual whole272 fails in
**162.42s**, unchanged461 inputs, at the same prepare/reset loan through Run's
first attempt. Scalar Frame removed Run.workspace but later optional views and
four owner-bearing CompileOptions fields still reach mutable storage. Selected
root progress did not prove that the actual whole frontier cleared.
[Whole272 receipt](benchmarks/evidence/qualification/2026-11-10-goose-whole272.json.gz).

Complete **36/36 native component laws pass** on the same frozen source as the
whole attempt: summed stage time **307.14s**,30s/stage,600s outer cap. Includes
Frame accessor identity, actual bucket growth/dedup across Frame teardown,
read-only header subranges/shared journals and all prior ownership laws.
Component success never qualifies complete generation or CLI/server runtime.
[Full receipt](benchmarks/evidence/qualification/2026-11-10-goose-complete36-scalar-cleanup-map-laws.json.gz).

All **92 synthetic recursive cleanup wrappers are removed** across6files:
82recognized by a guarded offset-preserving transformer and10manually audited
exclusions. Every return evaluates before cleanup; scopes, aliases and control
flow remain.22authoring controls and qualified original/transformed executable
witnesses pass (nested order, tuple side effects, loops, reference identity and
mutation). The one-time transform/idempotence pass fell62s→35.7s→**2.97s** after
rescan fixes; this is tooling time, not compiler throughput. The authoring tool
and complete evidence stay in the reproduction capsule, not production tooling.
[Controls/capsule](benchmarks/evidence/qualification/2026-11-10-goose-cleanup92-controls.json.gz).

**68map adapters /134publications across14files** now publish exact named-pool
slot ranges instead of a borrowed local Map view. Full-capacity identity/bounds
checks preserve data, counters, growth and no-op reserve behavior. No new owner,
payload copy or allocation. [Map audit](benchmarks/evidence/qualification/2026-11-10-goose-map-publication68.json.gz).

Principal region callbacks use scalar requests and owned output; constant
initializers keep scalar Body/Binding snapshots. CompileRun uses scalar Frame
with validated registry access. The focused compile advanced to type/effect
bucket publication before the broad map batch; actual whole still repeats the
Run loan. [Phase evidence](benchmarks/evidence/qualification/2026-11-10-goose-scalar-frame-frontier.json.gz).

Next coherent boundary is in copied preparation: replace Run's9optional workspace
views with enabled flags and Frame getters; replace previous/principal/query
Capture refs and checkpoint ref in its options with existing validated registry
keys. Public options, actual owner retention and success/error transport stay
unchanged, with no new registry or copy. Do not promote
partial descriptor patches or claim whole acceptance without a fresh build.

Complete read-only StampView reconstruction remains74fields/65slice leaves,
with full-allocation recovery before prefix/interior subspans. Valid shared pinned
journals work; nonempty capture leaves must belong to those journals. Scanning
costs remain unbenchmarked. Memo ends before replay; scalar counters reach publish.
All rejected prototypes, exact source identities and prior scope are linked in
[the receipt index](benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json).

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
