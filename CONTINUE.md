# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

Actual whole261 stops in **154.61s**, unchanged460 inputs, **no C/header/native
artifacts**. It still finds a prepare/reset loan through the first Result in
compileLocals before retry. Lexical outer wrappers alone did not clear it.
Next audit both constant-receipt and speculative-local retry Result scopes
against the Zig catch paths. [Whole261 receipt](benchmarks/evidence/qualification/2026-11-10-goose-whole261.json.gz).

Complete **36/36** native component inventory passes on frozen source: summed
stage time **290.53s**, 30s per stage, 600s outer cap. This includes nested hook
restore to exact previous references/null, retained Image sharing across Frame,
real code-artifact key-cache equality, optional timing Scope and prior owner laws.
The whole attempt subsequently regenerated source identity. Component coverage
never qualifies complete generation or CLI/server execution.
[Full receipt](benchmarks/evidence/qualification/2026-11-10-goose-complete36-refinement-laws.json.gz).

Refinement, named/closure/runtime initializer emission and replay now use lexical
cleanup. Named substitution descriptors replace local growers stored in emitter
Config; added scratch-owner allocation costs are unbenchmarked. Retained capture
traversal uses scalar cursors. Refinement hooks resolve the registered Session;
returned results reborrow their existing owned runs. Validation-image sharing
reborrows the same named bytes without new copy/allocation. Capture field/hash/
counter adapters match their actual types. ABI/session/error/cleanup order stays.

Seven-phase259 stops **53.45s** with replay equal buffer type, associatedTarget
Generator origin, and persistent ModulePin.header origin errors. The first two
are repaired afterward; next combined check pending. All probes are unstaged,
check-only and **NEVER executable**. [Phase evidence](benchmarks/evidence/qualification/2026-11-10-goose-refinement-artifact-phases.json.gz).

Header controls isolate StampView slice fields, not the Module pointer. Whole
header reborrows, scalar-owner construction and referenced snapshot prototypes
are rejected; the latter only moves retention into module_runs. A names-only
control reborrowing the exact dependency_payload byte pool clears that origin;
it omits other fields and is never promotable. Next generate complete read-only
leaf reconstruction preserving every snapshot field and exact slice identity.
No checker rule is weakened. The [receipt index](benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json)
links all negative and positive controls and earlier checkpoints.

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
