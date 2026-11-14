# Fast compilation: the direct backend, then the language rewrite

The owner's order (14 November 2026): make the direct backend
(compiler/src/direct/, [plan](tasks/FAST_COMPILE.md)) the only backend and
delete the scoped one ([deletion](tasks/DELETE_SCOPED.md)), then carry out
the approved [language coherence list](tasks/LANGUAGE_COHERENCE.md) (memory
model first), then port the result to Goose.

## Current frontier

- **Direct backend.** The only code generator `blotc` runs; the CLI and the
  project protocol no longer select a backend or a codegen tier. The scoped
  backend's code is still in the tree until its deletion lands.
- **Gdev Main.** On a release compiler it builds in 1.15 s against the scoped
  backend's 6.61 s (backend 95 ms against 5,533 ms), producing 2.7 MB of Wasm
  against 9.2 MB. Its first Pen frame is byte-identical (frame.png 19a03f0a…,
  frames.trace 86d50101…). Its guest frame time is 0.079 ms median against
  2.45 ms.
- **Ink.** Ink's suite matches the scoped backend on all 64 modules both
  compile. The direct backend also passes extractions, retained and
  simd-batches, which the scoped backend rejects.
- **Guest suite.** Tests of scoped internals and dropped features are
  deleted, expectations follow the approved changes (aliased writes,
  instantiation-time constants, required signatures), and every remaining
  case passes or is ignored with its reason. tasks/DELETE_SCOPED.md lists the
  ignored cases by kind.

**Next:** delete `backend/`, `eval/`, `runtime/` and the scoped parts of
`reuse/` (tasks/DELETE_SCOPED.md, "Code deletion plan"), then fix the
ignored cases that emit invalid Wasm or wrong results.

## Commands

- **Fast compiler:** `zig build install -Doptimize=fast -Dllvm=false --prefix zig-out-direct`
  in compiler/, under the heavy lock.
- **Direct fixtures:** `deno test -A tests/guest/direct_backend_execution.test.ts -- compiler/zig-out-direct/bin/blotc`
- **Guest suite:** `deno test -A --parallel tests/guest tests/host -- BLOTC`.
- **Gdev:** `deno run -A scripts/integration/build_gdev.ts --compiler X OUT`,
  then `run_pen.py --launch --hardware --compiled-main OUT/main-*/main.wasm --expected-wasm-sha256 …`.
- **Ink:** copy ../ink, point pen.json's `plugins.blot.run.blotc` at the
  compiler, and run `pen test-blot --project COPY` using
  ../pen/target/release/pen.

## Parked: the Goose port of the old compiler

compiler-goose/ ports the scoped-backend compiler. It builds a whole
executable and matched the oracle on Ink and on Gdev Main's frame, but it
ports code that is now being deleted. Phase 7 ports the rewritten compiler
instead. The full narrative, commands and evidence are pinned at b9875a88
(CONTINUE.md there); its evidence files stay under benchmarks/evidence/.

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

