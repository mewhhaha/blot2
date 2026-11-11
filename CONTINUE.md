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

Status on 11 November 2026: 17 of the 20 diagnostic roots pass (run them all with
`--engines <all> --jobs 4`). The `server` root exceeds the 120s cap, both under
contention and alone, so it stays unqualified. The `compile` root is the frontier;
it now takes 111–119s of its 120s cap. Receipts run from
[backend 316](benchmarks/evidence/qualification/2026-11-11-goose-backend-flow316.json.gz)
to [compile 416](benchmarks/evidence/qualification/2026-11-11-goose-compile416.json.gz).

**Next:** `backend/runtime_pipeline.goose:85` reports that `root_borrows.run` shrinks
`backing_origins_code_module_static_fields` while the pipeline `module` is live.
No visible callee of `run` shrinks module storage. Find the summary's source before
changing code, using the reach-trace build or a narrow root (below).

Repair patterns that cleared the 316–416 errors. Prefer them over one-off rewrites:

- **Shrinking indexes → fixed-bucket indexes.** Replace a dictionary or other
  grow-shrink index with a fixed bucket table chained through grow-only records
  that are reused by count. Lookup compares stored keys, and clearing zeroes the
  heads. Done for numeric terms, plan slots, sinks, runtime operation symbols,
  substitution keys and provider guard positions.
- **Held Core/layout/evaluator slices → per-index reads.** Rewrite them as
  `for i in 0..E.len { let x = E[i]; ... }`, or inline the accessor at each use.
  Copy small capped runs (call arguments, at most 16) into fixed locals.
- **`self_` reaches the storage it shrinks (`s == l`) → remove the reachability.**
  Keep scalar keys or flags instead of references. Examples: `Generator`'s
  `retained_enabled`, `Owner`'s `frame`, and builders that pass `context` beside
  them. Analyses tabulate the module facts they need per body instead of holding
  the module.
- **Callee resets → caller resets.** Callers reset views before they bind module
  references, and functions avoid reassigning whole structs that contain arrays.
- **Recursion-cycle functions are declared `recursive fn`.** The checker accepts
  unneeded `recursive`.
- **Generated adapters and backing.** `write_compile_workspace_backing.py` has
  drifted from its checked-in output (eight owners' reset behaviour). Edit both
  consistently; don't regenerate blindly.

Diagnosis aids:

- **Narrow roots.** Write a temporary `_numeric_probe.goose` exporting a
  no-argument function, then run
  `GOOSE_DIAGNOSTIC_ROOTS=<namespace>::<fn> <goose> check <file> --stdlib …`.
  See [the example](compiler-goose/tools/narrow_root_example.goose). These only
  reproduce context-free errors, and the file must be removed before full probes.
- **Reach-trace build.** `build/goose-port/reach-trace-diagnostics/goose` is a
  diagnosis-only rebuild of the pinned checker source. Running it with
  `GOOSE_GLOBAL_REACH_TRACE=1 GOOSE_GLOBAL_REACH_HOLDER=<global> GOOSE_GLOBAL_REACH_ARRAY=<array>`
  prints the store chain behind "global X may hold a reference into Y".

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
