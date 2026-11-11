# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. A whole compiler executable now builds
([first executable](benchmarks/evidence/qualification/2026-11-12-goose-first-executable.json)); it is not qualified yet. Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

`python3 compiler-goose/build.py --goose build/goose-port/upstream-d5ae5bb/build-precision/goose
--cc clang-23 --stdlib build/goose-port/upstream-d5ae5bb/source-precision/stdlib --stage-timeout 900
--total-timeout 1200` (under the heavy lock) checks the full program, emits 224 MB of C and links
`compiler-goose/build/blotc-goose` (79 MB) in about 555s at 9 GiB peak. The checker is upstream
Goose d5ae5bb plus [series](compiler-goose/tools/upstream-32a4f44/series) 01-18; patch 18 shares
unchanged body-event chunks and took the server root from the 14G cap to about 7.4G.

Smoke: on examples/scalar.blot, lex/parse/check reports match the Zig oracle apart from timings and
the unavailable allocator counters, and scalar.wasm is byte-identical. Four other examples are
rejected with the oracle's first diagnostic.

[Qualification 3](benchmarks/evidence/qualification/2026-11-12-goose-qualify3.json.gz)
(`deno run -A compiler-goose/tools/qualify_compiler.ts --goose-compiler compiler-goose/build/blotc-goose
--zig-oracle compiler/zig-out-native-fast/bin/blotc --output DIR --overall-ms 900000`) passes its scoped
functional checks: Goose 20 pass, recursion unsupported exactly as the oracle (ABI 8 recursive
selected calls). That covers CLI, executed ABI 8, the project lifecycle, request OOM/retry and
the 16 MiB revision-retention budget. It used the checker built with series 01-19 (patch 19 ports
the runtime allocation observer the OOM injection needs); full runtime qualification is still
pending.

**Next:** broaden parity beyond the fixtures (Ink/Gdev/Pen builds and Gdev frames against the
Zig oracle), measure compile speed and size against the oracle, rerun the 20 diagnostic roots on
the current checker, and split the compile root, which is near its 300s cap.

Narrow roots (`GOOSE_DIAGNOSTIC_ROOTS=blot_numeric_probe::probe`) type-check one path in seconds to
minutes; the whole build reports the first full-program error in about 6 minutes.

Repair patterns that cleared the 316–445 errors. Prefer them over one-off rewrites:

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
- **References stored in struct fields → owned fields.** The checker loses which
  array a `T[>..<]&` field refers to and falls back to every same-typed array
  the caller can reach, so a scratch `clear()` becomes "may shrink module".
  Give the struct its storage instead: a `root struct` for several resizable
  fields (`root_borrows.Analysis`), or one final resizable field (`wasm.Wire`).
  Pass plain `T[>..<]&` arguments to helpers rather than wrapper structs.
- **Results never read back through a local run.** Write snapshots that hold slices
  straight into the `Result`, and copy only scalars out of `CompileRun`. Run
  teardown keeps the grow-only plan payload pool; `resetGenerator` empties it.
- **Never shrink a pool other code may view.** Reuse records by count (plans, sinks)
  instead of `pool=[]`; the checker otherwise matches every live view by element type.
- **Store grow-only copies.** A slice of a `T[>..<]` local may not be stored (§5.2);
  copy canonical paths and messages into `T[>..]` buffers before storing them.
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
- **Return-root trace.** Adding a `GOOSE_RETURN_ROOT_TRACE=<name>` print to the
  return check in `typecheck_calls.h` (build/goose-port/upstream-d5ae5bb/build-trace)
  shows which function first returns contents rooted in a parameter.
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

Current checker: upstream Goose d5ae5bb (one stdlib-only commit past 32a4f44)
plus [the ported series](compiler-goose/tools/upstream-32a4f44/series) 01-17, built
by its `build.sh` into build/goose-port/upstream-d5ae5bb/build-precision/goose
(sha256 490e1f80…). It reports the same first errors as the old 2e2bedef checker
on 19/20 roots, runs about 1.5x slower and needs over 14G for the server root
([comparison](benchmarks/evidence/qualification/2026-11-11-goose-upstream-32a4f44.json)).
Run roots one at a time; three in parallel exceed 14G. `GOOSE_SHRINK_ORIGINS=<callee or *>`
adds the original shrink witness to an error. Installed Goose is unchanged.

Caps: repair 300s on the current checker, final emission 180s, whole 300s; stop 3s after a reported
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
