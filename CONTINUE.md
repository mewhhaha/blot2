# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

**No complete C/header/native Goose compiler exists.** Actual whole261 failed in
154.61s on a prepare/reset loan across retry, unchanged460 inputs. Subsequent
lexical retry Result cleanup clears that blocker in selected compile262; no newer
actual whole attempt yet. [Whole261](benchmarks/evidence/qualification/2026-11-10-goose-whole261.json.gz).

Combined phase266 reaches **69.78s**, frozen source, and now reports one deeper
principalEvidenceFallback context-shrink error at core_eval1069. All earlier
header/memo/diagnostic/mapping frontiers are cleared in that check. These roots
are unstaged, check-only and **NEVER executable**. A direct diagnostic/unit-use
root reduces that specific repair loop to **2.67s**; full recording plus replay
passes a copied check in **11.25s**.
[Boundary receipt](benchmarks/evidence/qualification/2026-11-10-goose-memo-diagnostic-boundaries.json.gz).

Seven affected native laws pass after the full source family, summed stage time
**74.10s**: full header equality, exact full/prefix/interior slice identity and
contents, shared journals without unique access, scalar snapshot stability,
retention across owner teardown, leases, pipeline, server component and diagnostics.
[Native receipt](benchmarks/evidence/qualification/2026-11-10-goose-readonly-lifecycle-laws.json.gz).
Complete36/36 is the preceding checkpoint's frozen evidence (290.53s summed stage
time), not current complete inventory or actual compiler/CLI qualification.
[Historical complete36](benchmarks/evidence/qualification/2026-11-10-goose-complete36-refinement-laws.json.gz).

Complete read-only header reconstruction covers **74 fields / 65 slice leaves**,
generated from actual schemas and56 concrete typed pools. It validates existing
publication journals, recovers full allocation extents before returning subspans,
and preserves every snapshot field/identity without new copy/allocation. Shared
valid journals work; nonempty capture leaves must belong to those pinned journals.
Journal scans and the interior linear fallback are unbenchmarked costs. Arbitrary
headerPrint callers remain. Reduced-header prototypes stay rejected/non-promotable.
[Full observer proof](benchmarks/evidence/qualification/2026-11-10-goose-readonly-retry-frontier.json.gz).

Memo scope now ends after recording, before replay resets the generator; only
scalar counts reach publication. Original Core snapshots, token/digest behavior,
replay/error order and final timing lap stay. Failed retry Results end scope
before the next attempt. Diagnostic publication reads registered Session fields
directly, preserving arbitrary text and metadata without extra copy. Emitter
mapping selection uses direct branches and scalar outcomes. JSON output locals
match the existing writer; optional pin stamps emit array/null like Zig.

Next: repair the principal fallback context owner; retry the actual whole build.
There are92 remaining generated recursive cleanup wrappers in6files. A copied,
fail-closed batch transformer is being explored with exact inventory/control
requirements; no such broad transformation is promoted. Native/phase evidence
never qualifies full generation or CLI/server/OOM/retry/retention runtime.

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
