# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

**No complete C/header/native Goose compiler exists.** The latest complete build,
whole 290, stopped at partial expectation interning in 163.377s with unchanged
461 inputs and no artifact. Use grouped backend diagnostics for repairs: they
reproduce and advance the relevant frontier in about 75–78s. These are partial,
check-only probes and never qualify the full compiler.

Backend 295 clears shared-map interning, emission index borrows, infinite lookup,
closed-local module/body references, nullable fields and recursive array borrowing.
It stops after 77.441s, unchanged source, at `backend_representations.goose:38`:
generic bridge binding stores a projected state reference into the global bridge.
Migrate production callers to the existing checked `bridgeForGenerator` accessor;
retain generic representations for lexical contexts.
[Latest backend receipt](benchmarks/evidence/qualification/2026-11-10-goose-backend-borrow-walk295.json.gz).

Array walkers now receive the original borrow engine as an invocation parameter
instead of storing it in each recursive walker. No new pool/registry/cache copy.
The actual captured-borrow law passes in 2.848s, including absent/present sinks,
repeated reads and public captured-read updates. Three artifact hooks also narrow
nullable references locally. Earlier shape/index/closed-local families have
focused native receipts in the index; none qualifies whole runtime.
[Borrow law](benchmarks/evidence/qualification/2026-11-10-goose-borrow-walk-laws.json.gz).

Previous checked families clear Run preparation, startup planning, declaration
scanning, bridge cleanup/publication, physical interning and fixed conversion
stacks. Physical layouts retain scalar publication/effect keys; invocation-local
views come from existing registries and pools, with exact identity/generation
checks. Append-only growth preserves child views; reset with a live child rejects.
Conversion stacks retain their 128-owner/128-binder limits in fixed backing,
including overflow rejection and nested-error unwind. No payload clones/new pins.

The last complete component inventory passed 36/36 on its pinned source in
307.14s summed stages. The current 46-law inventory has not run in full; focused
family receipts qualify only their exact inputs. The cleanup-wrapper retirement,
68 map adapters and all rejected prototypes remain in pinned history and
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
Its parent finite-input-root precision has 33 lifetime/3 runtime/24 semantic controls;
the combined metadata/traversal build repeats 33 lifetime/24 semantic controls.
Unknown/inexact/local/recursive/over-64-root paths keep the conservative behavior.
Metadata-only options tracing is enabled with GOOSE_OPTIONS_ROOT_TRACE=1.
Traversal-local nominal buckets roughly halve TypeEq counts, but 150s versus 154s
is a single pair and establishes no robust speed gain. Installed Goose unchanged.

Selected roots are partial, check-only; scoped uses invalid empty Core. They do
not qualify runtime. Regenerate adapters for layouts, await completion, then
freeze source. Repair cap 120s, final emission 180s, whole 300s; stop 3s after a
reported error. Never lift caps, relax checks or clear live owners to hide errors.

Once the real executable exists, run compiler-goose/tools/qualify_compiler.ts
against it and compiler/zig-out-native-fast/bin/blotc. Eight matching Zig baseline
fixtures pass; Goose CLI/server/OOM/retry/retention have not run. The runner now
covers cold and retained-revision request OOM/retry plus 2 warmup/6 measured
edit/restore revisions under a 16MiB process-tree RSS growth budget. Its format,
type and lint checks pass. This does not measure allocator live bytes; those
remain unavailable. No ABI fallback.

Zig source is unchanged. Its prior full gate remains incomplete: all 2974 laws
compile without LLVM; release compilation hit its cap. Smoke, harness and zero
finding lint pass. Do not rebuild that release for each Goose edit. No fresh
current-port Gdev Main/frame exists. Historical Main 9,203,613 B/5.523s belongs to
its older release; no reliable compile speed gain. Subsecond compilation,
sub-five-second Main and 1–2MB remain unmet. Environment publication and upstream
messages require explicit requests. Use Astra for concrete snags only; never Terra.
