# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. **No whole compiler
artifact exists.** Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

The latest complete build, whole 290, stopped at partial expectation interning in
163.377s with 461 unchanged inputs and no artifact. Repairs advance through the
grouped backend probe, which takes about 85–100s:

```sh
flock /var/tmp/blot2-heavy.lock systemd-run --user --scope -q -p MemoryMax=14G -p MemorySwapMax=2G \
  python3 compiler-goose/tools/check_engines.py --goose build/goose-port/finite-root-diagnostics/goose \
  --engines compile record_artifact emit --jobs 1 --timeout 120 --output build/goose-port/<name>
python3 compiler-goose/tools/seal_probe.py build/goose-port/<name> <date>-goose-<name> --audit "..."
```

The checker reports one error per run. These are partial, check-only probes and
never qualify the full compiler.

Backend 316 (101.165s, unchanged source) clears all of `backend_emission`'s
borrowed-Core-slice family:

- Closure captures, static-closure bindings and task-move captures are read per
  index instead of being held across key interning and emission.
- Resolved-flow `Join`, `Match`, `Loop`, `RequestLoop` and exits hold Core `List`
  ranges. Consumers read merges, arms, inputs, carries and break values per index
  from their unit.
- Spawn applications build `ModuleRef` views at the call. The oracle's
  `spawn_units` becomes a `spawn_tasks` flag.
- Published update-field plans rebase their slices onto their owning pools.
- 29 scalar fixed scratch arrays are zero-initialized.

[Receipt](benchmarks/evidence/qualification/2026-11-11-goose-backend-flow316.json.gz).

Backend 326 (97.465s, unchanged source) clears the specialization, retention and
numeric-owner batch:

- `namedSink` copies Body span/root before refinement.
- Instance argument runs (capped at 16) are copied into a fixed value before
  `Service.named`.
- `retainedCapture` keeps only pooled buffer handles across its recursion (§7.8).
- Stale `Owner.mappings` assignments use `mapping_read`/`row_read` keys.
- Numeric `intern` inlines its literal-complement self-call, with the same visit
  charge.
- `body` re-reads its contract header at each use.
- `numericCheck` uses the `Module[:]` analyze overload.

[Receipt](benchmarks/evidence/qualification/2026-11-11-goose-backend-numeric326.json.gz).

**Next:** `check/numeric_proof_core.goose:327`: "cannot call version, which may
shrink self_ while self_ (bound at 322) is still used". The same
`prepareNumeric → analyzePrepared → body` chain passes under a narrow root, so the
error depends on reaching it inside the recursive emission cycle.
`GOOSE_SHRINK_ORIGINS` gives no witness. Find what `version` may shrink
(`Store.intern`'s dictionary insert or `account`) before restructuring.
Never clear owners or relax checks.

A narrow root is a ~1.5s loop for context-free errors. Write a temporary
`compiler-goose/src/_numeric_probe.goose` exporting a no-argument function, then
run `GOOSE_DIAGNOSTIC_ROOTS=<namespace>::<fn> <goose> check <file> --stdlib …`.
Remove the file before a full probe, because full probes hash every source.
[A copy](compiler-goose/tools/narrow_root_example.goose)
of the prepareNumeric root is kept in tools.

The last complete component inventory passed 36/36 on its pinned source in
307.14s summed stages. The current 49-law inventory has not run in full. Focused
receipts qualify only their exact inputs. Rejected prototypes and superseded
families stay in pinned history and
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
- Physical layouts keep scalar publication/effect keys with exact
  identity/generation checks. Conversion stacks keep their 128-owner/128-binder
  limits with overflow rejection and nested-error unwind.
- `backing_origins_code_module_types` is detached diagnostic Wasm ValueType
  scratch, not Core input types; reborrows cannot revive a discarded Core input.
- Native leaf laws never qualify full generator/probe/tape/CLI/server runtime.
  Known pending API coverage: artifact_import factory across Frame and
  host_cleanup_shapes.copyFields. Full invocation emission and actual
  preparation probes stay explicit opt-in, capped and unqualified.
- Requirements and rejected experiments remain in
  [the storage task](tasks/STORAGE_REWRITE.md),
  [the language migration](docs/language/NEXT_MIGRATION.md) and the receipt index.

## Tools and next checks

Private experimental checker: build/goose-port/finite-root-diagnostics/goose
(sha256 689721da…). Binary/source hashes and recipes are in
[the controls](benchmarks/evidence/qualification/2026-11-10-goose-options-roots-and-traversal.json.gz):
33 lifetime/3 runtime/24 semantic controls. Unknown/inexact/local/recursive/
over-64-root paths keep the conservative behavior. `GOOSE_OPTIONS_ROOT_TRACE=1`
enables metadata-only options tracing. Installed Goose is unchanged.

Caps: repair 120s, final emission 180s, whole 300s; stop 3s after a reported
error. Never lift caps, relax checks or clear live owners to hide errors.

Once the real executable exists, run compiler-goose/tools/qualify_compiler.ts
against it and compiler/zig-out-native-fast/bin/blotc. It covers CLI/executed
ABI 8, project lifecycle, cold and retained-revision request OOM/retry, and
2 warmup/6 measured edit/restore revisions under a 16MiB process-tree RSS growth
budget. Allocator live bytes remain unavailable. No ABI fallback.

Zig source for the Goose oracle is unchanged. Its prior full gate remains
incomplete: all 2974 laws compile without LLVM; release compilation hit its cap.
No fresh current-port Gdev Main/frame exists. Historical Main 9,203,613 B/5.523s
belongs to its older release. Subsecond compilation, sub-five-second Main and
1–2MB remain unmet. Environment publication and upstream messages require
explicit requests. Use Astra for concrete snags only; never Terra.
