# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

Actual whole173 checks 458 unchanged build inputs in **151.03s**, then stops:

- `backend/scoped_backend.goose:2604`: publishing the emitted diagnostic inside
  recursive `run` crosses the recursive-store boundary (§7.8).
- `backend/resolved_body.goose:60`: `process_requests` may retain payloads through
  `driver/project_executor.goose:61` (§5.1).

There are no C/header/native artifacts. The prior whole160 footprint/effect-key
failures and the assembler Session/Matcher stores are cleared. Exact source and
raw diagnostics: [whole173](benchmarks/evidence/qualification/2026-11-10-goose-whole173.json.gz).

The complete **32-law component inventory passes in 288.97s**, with unchanged
import closures and actual C emission, linking and native execution. Every stage
retains its 30s cap. This qualifies the component laws, not the complete compiler.
See [complete32](benchmarks/evidence/qualification/2026-11-10-goose-complete32.json.gz).
The affected assembler/outline/worker trio separately passes in **18.06s**:
[assembly family](benchmarks/evidence/qualification/2026-11-10-goose-assembly-family-laws.json.gz).

Assembly retries now own their scratch directly. The nested recursive attempt is
removed; cleanup remains bodies → parallel → matcher → passes → profile, with
original error/retry order. Worker packets own copied arrays. Profiling and
collector analysis choose source/detached instruction views lexically. The new
law executes empty/nonempty assembly, collector rejection cleanup, packet/image
round trips after Module retirement and type/instruction-buffer reuse, and
profile hash parity and changed-instruction inequality. It does not exercise nonempty
names/data retirement, Frame spanning, real process scheduling or full CLI/server.
Slice-only packet copies stage through a grow array; cost is not benchmarked.

Two next repairs are prepared off-tree and are not part of this checkpoint:
remove compileScoped's recursive `run`, keeping result construction outside a
cleanup-only helper; reify exact existing packet allocations before lower/check
request publication. Review found all scoped diagnostic details are static
strings, so this path needs no extra text owner. Preserve result-before-cleanup
order and original cleanup/error priority. Run a strict actual boundary afterward.

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
