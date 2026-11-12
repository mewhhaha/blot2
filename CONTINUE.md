# Finish the Goose compiler experiment

Repair ownership, build the actual complete C/header/native compiler, then qualify
CLI/server, request OOM/retry and retention against Zig. A whole compiler executable now builds
([first executable](benchmarks/evidence/qualification/2026-11-12-goose-first-executable.json)); it is not qualified yet. Keep compiler/ as the oracle; never forward Goose requests to it.

## Current frontier

`python3 compiler-goose/build.py --goose build/goose-port/upstream-d5ae5bb/build-observer/goose
--cc clang-23 --stdlib build/goose-port/upstream-d5ae5bb/source-precision/stdlib --inference-budget 1000000
--stage-timeout 900 --total-timeout 1200` (under the heavy lock; wrapper build/goose-port/whole451/run.py)
checks the full program, emits 224 MB of -O0 C and links `compiler-goose/build/blotc-goose` in about 560s
at 8.8 GiB peak (emit ~500s, clang ~55s). The checker is upstream Goose d5ae5bb, still upstream HEAD,
plus [series](compiler-goose/tools/upstream-32a4f44/series) 01-19 (18 shares body-event chunks;
19 ports the runtime allocation observer the OOM injection needs).

The oracle is compiler/zig-out-native-fast/bin/blotc rebuilt from current source (sha 71ae7ab9…); the
2026-11-08 binary kept beside it predates `type X is opaque` and cannot read the current std.

[Ink parity](benchmarks/evidence/qualification/2026-11-12-goose-ink-parity.json): Ink's Pen test suite
through the project server matches the oracle on all 73 modules (243 passed, 1 failed, 9 rejected with
the same diagnostics), 328s at 2 jobs against 121.5s at 4. Getting there fixed three server faults
(44ee94f4): a 120s request limit, a seed-prefix rebind that rejected entries interning new symbols, and
parallel codegen sending the module image with every job. Run it with copies of ../ink whose pen.json
names the compiler (build/goose-parity/ink-zig, ink-goose) and Pen/plugin rebuilt from ../pen source.

Gdev Main compiles on Goose (1197s against the oracle's 110s) to the same 9,203,613 bytes except 36:
one function (code-section index 5077) numbers locals 70-78 in a different order. That local-order
divergence is the open parity bug; the remap in wasm_stackify matches Zig, so look earlier (local
allocation, coalescing or declaration order). Getting here also fixed `wasm.appendInstruction`, which
recopied a body to the shared array's tail on every switch between functions and overflowed a 2 GB
data stack; moves now reserve geometric filler. `scripts/integration/build_gdev.ts --compiler X
--timeout-ms 3600000` runs it.
That Goose main.wasm renders Gdev's first frame through Pen identically to the oracle's (same PNG and
frame trace; `run_pen.py --launch --hardware --compiled-main`, since no software adapter is installed).

[Qualification 3](benchmarks/evidence/qualification/2026-11-12-goose-qualify3.json.gz) (scoped
functional checks: CLI, executed ABI 8, project lifecycle, request OOM/retry, 16 MiB retention) passed
on the older binary against the stale oracle; rerun it on the current pair.

Diagnostic roots, each alone: all 20 pass on 44ee94f4 source; compile takes 235s and server 374s (over the
300s cap). Checking all 20 in one process gives one cross-probe error (assemble), not production.

**Next:** find the Gdev local-order divergence (loop-carried locals: Zig numbers a group of six before a
group of three, Goose the reverse);
rerun qualification on the current oracle; land the checker speed patches (separate PR); measure an
optimized (`--release`) Goose build's compile speed and size against the oracle.

To find a server fault: capture Pen's serve-project stream with a tee wrapper, replay it
(build/goose-parity/repro/replay.py), and build a diagnosis-only binary from the emitted C
(same-line traces at error creation sites, or a runtime fault handler that prints a backtrace;
build/goose-parity/debug). gdb loses the request supervisor's fork/vfork chain.

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

Current checker: upstream Goose d5ae5bb plus the series 01-19, built by
compiler-goose/tools/upstream-32a4f44/build.sh (build-observer/goose, sha256 c947f304…). Peak
memory is about 9 GiB for the whole program; run heavy jobs one at a time under the heavy lock.
`GOOSE_SHRINK_ORIGINS=<callee or *>` adds the original shrink witness to an error. Installed Goose is
unchanged.

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
