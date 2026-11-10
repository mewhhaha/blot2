# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

**No complete C/header/native Goose compiler exists.** Actual whole283 advances
past the long-standing Run prepare/reset loan and startup planner loan, then
fails in declaration_dependencies.scheme at its visited-dictionary insert.
**162.11s**, unchanged461inputs, no C/header/native artifact.
[Whole283](benchmarks/evidence/qualification/2026-11-10-goose-startup-whole283.json.gz).

CompileOptions now carries source-completion and validation identities by value.
Zero/stale/reused-generation receipt laws pass; snapshot/Prepared still own and
release the receipts. Exact input identity/digest/order spans name their original
journals. The private checker preserves bounded complete sets of exact global
input roots, rather than collapsing them to a depth-only class. Actual whole282
confirms all5roots survive through compileAttempt, clearing the Run loan.
[Receipt law](benchmarks/evidence/qualification/2026-11-10-goose-scalar-source-receipt-law.json.gz),
[Whole282](benchmarks/evidence/qualification/2026-11-10-goose-scalar-source-receipts-whole282.json.gz).

Startup planning now takes a scalar Frame and reborrows its existing named
planning header only after dependency queries. StartupDependencyQuery/RecheckProof
hold scalar requests; callbacks use the canonical region Session and explicit
owned selected-output transfer. Two native laws pass18.58s summed stages,
including planning identity and mutation through the original workspace.
[Native laws](benchmarks/evidence/qualification/2026-11-10-goose-startup-frame-laws.json.gz).

Declaration scans replace the visited hash with fixed binding-indexed u32
generation marks in append-only stable local owners. Normal scans reset in O(1);
only generation rollover clears all marks. A new executed native law passes
cycles/repeats at63/64/65, DFS order, selection, per-body reset, invalid targets
and forced rollover. A bitset prototype was superseded before whole integration
to avoid a full binding-table clear per body. Whole284 fails160.00s at Capture.work.pop live alias; the complete scratch
family is next. No whole artifact.
[Declaration law](benchmarks/evidence/qualification/2026-11-10-goose-declaration-generation-law.json.gz).
CLI/server/OOM/retry/retention still require the actual executable.

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

Run retains scalar Frame/registry authority and enabled workspace flags.
CompileOptions now uses four scalar keys at its public construction boundary;
the late sanitizer and duplicate Run keys are removed. Immutable input spans
are reborrowed from the original journal; source receipts use exact canonical
registry addresses. Timing labels remain statically reconstructed.

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

Current private experimental checker:
build/goose-port/finite-root-diagnostics/goose; binary/source hashes and exact
recipes in [the controls](benchmarks/evidence/qualification/2026-11-10-goose-options-roots-and-traversal.json.gz).
Its parent finite-input-root precision has33lifetime/3runtime/24semantic controls;
the combined metadata/traversal build repeats33lifetime/24semantic controls.
Unknown/inexact/local/recursive/over64root paths keep the conservative behavior.
Metadata-only options tracing is enabled with GOOSE_OPTIONS_ROOT_TRACE=1.
Traversal-local nominal buckets roughly halve TypeEq counts, but150s versus154s
is a single pair and establishes no robust speed gain. Installed Goose unchanged.

Selected roots are partial, check-only; scoped uses invalid empty Core. They do
not qualify runtime. Regenerate adapters for layouts, await completion, then
freeze source. Repair cap 120s, final emission 180s, whole 300s; stop 3s after a
reported error. Never lift caps, relax checks or clear live owners to hide errors.

Once the real executable exists, run compiler-goose/tools/qualify_compiler.ts
against it and compiler/zig-out-native-fast/bin/blotc. Eight matching Zig baseline
fixtures pass; Goose CLI/server/OOM/retry/retention have not run. The runner now
covers cold and retained-revision request OOM/retry plus 2 warmup/6 measured
edit/restore revisions under a16MiB process-tree RSS growth budget. Its format,
type and lint checks pass. This does not measure allocator live bytes; those
remain unavailable. No ABI fallback.

Zig source is unchanged. Its prior full gate remains incomplete: all 2974 laws
compile without LLVM; release compilation hit its cap. Smoke, harness and zero
finding lint pass. Do not rebuild that release for each Goose edit. No fresh
current-port Gdev Main/frame exists. Historical Main 9,203,613B/5.523s belongs to
its older release; no reliable compile speed gain. Subsecond compilation,
sub-five-second Main and 1–2MB remain unmet. Environment publication and upstream
messages require explicit requests. Use Astra for concrete snags only; never Terra.
