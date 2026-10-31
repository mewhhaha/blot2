# Continue here — owned-storage integration

## Current cloud frontier

Continue until one real Gdev frame runs in native Pen and inspect the PNG. No
current main Wasm or frame has succeeded. Preserve ABI8/session2, framing26,
the165-field FrameAccess, packet order and the storage capacities below.

Production source expansion remains500,000 expressions per function. Astra xhigh
reviewed one bounded1,000,000 experiment; no further cap increase is authorized.
The latest completed full attempt, `main-378b434395b10721`, reached894,814
expressions in the first exported body, then exhausted the unchanged100,000-node
layout budget in Ink ECS. It took1,138s and10,893,316KiB peak child RSS. No
complete first export or valid real-main module was emitted.

Closed parameterized nominal layouts now use declaration-local substitutions to
prove context-free cache eligibility. Every argument must close, including
phantom arguments; storage capabilities and callables decline. Closed shapes
are built with isolated substitutions so nested semantic witnesses cannot retain
an unrelated caller context. The300-field/200-copy regression fails the old
layout budget and passes unchanged with the cache. Both new native laws pass;
all2,702 compile; nine affected native laws pass, including wrapped exhaustive
OOM checks. Mixed Maybe/Box/Pair witnesses execute in both tiers and sync/async.
The affected guest batch was51passes/1known associated-result layout baseline
failure. Astra xhigh review and changed-file lint/format pass. The private
first-export histogram `main-8544798919476965` still failed at644,559 total
expressions (561,352 root), after681s/6,629,844KiB peak RSS. Direct layout
misses plus proof visits reconcile exactly to100,001;1,331,808 cache hits did
not eliminate repeated open layouts. No cap was raised.

Completed source calls now extract closed, typed machine ranges into private
helpers, after all escape/release/rewind checks. Cross-body and written
read-before-definition i32 registers use private per-root Wasm globals, reset
only at original function entry. Future uses promote every occurrence; zero-only
lanes remain zero. Strict branch closure, exact call signatures, hidden-local
and coordinate guards, reachable acyclicity and final encoded host limits are
checked. Only committed helpers credit their own per-body expression/layout
work; cumulative work is unchanged and provisional limits remain active.

The real update stage `main-93e1c33a68375341` now PASSES production V8 validation
and actual Pen Wasmtime49 Module::validate:13,994,810bytes total,313helpers,
55,227private globals,505,091total expressions,20,378peak body work under the
unchanged500,000limit. Previously update root15,294,397bytes and480,431locals
failed both engines. Stage success does not qualify the real main or frame.

Eight new native laws pass, including exhaustive allocation faults, nested
credit/refcount preservation, captured loop state, future references, tee/packed
metadata, parameter resets, non-i32 parent decline, typed controls, cycles,
unknown dispatch, global bounds and the final50,000combined-local boundary.
All2,711 native tests compile. Affected guests are57passes/1known baseline;
the new padded captured-demand loop asserts actual extraction and executes in
both tiers and sync/async. Changed Zig files have zero analyzer findings. The
required full gate was attempted before checkpointing and remains blocked by
the locked Baba9.0.1 registry proxy fetch. No dependency or lockfile changed.

The actual native Pen attempt is running at
`build/storage-integration/gdev-one-frame/attempt-s1i49tls`, using the matching
default compiler. No real-main success or PNG has been observed yet. Continue
this attempt before launching another full compile.

Retained fixes include exact selected type keys and result snapshots, defining
module obligations for planner closures, semantic witnesses on loaded nominals,
checked fixed scratch fill/generate writer admission and late local compaction.
Gdev's simulation projection excludes unrelated borrowed UI rows while retaining
the165-field public FrameAccess. Ink's concrete generated codec policies preserve
ActorObservation framing and strict malformed-input behavior. Focused native and
executed-Wasm evidence is recorded in
[the cloud-main evidence](tasks/storage-handoff-evidence/2026-10-30-cloud-main.json)
and pinned Git history. Do not relax these contracts to advance integration.

Native Pen, its compiler plugin and Mesa lavapipe are available locally. Keep
unrelated fixture migration and performance work paused. The next qualifying
run must use the real main and produce an inspected native Pen PNG.

## Immediate next step

Get **one real Gdev frame running in Pen**. No current Gdev `main.wasm` has
successfully compiled, and no Pen frame or screenshot has been produced.

The cloud retry built the development compiler with Zig 0.17.0 and Deno 2.9.6.
The actual-main attempt moved beyond the previous Boxing diagnostic. Binding
`text ()` once still exhausted module validation, so Gdev's editor toolbar now
uses the existing per-label `part`/`span_*` exports. Its 46 fields and
evaluation order match the previous toolbar, without changing generated payloads
or budgets.

The latest render frontier is recorded above and in
[the tracked retry evidence](tasks/storage-handoff-evidence/2026-10-30-cloud-main.json).

The machine's command sandbox cannot connect to its proxy; network operations
work through the supported escalated command path. The normal Deno task eagerly
fetches the locked Baba package from unavailable `npm.jsr.io`. For the existing
build script and real-main driver, which need only local modules and Node
builtins, the retry used `deno run --no-config --no-lock` with the permissions
listed in the evidence. No manifest, lockfile, TLS or checksum was changed.

Use the existing four sibling checkouts; do not create a worktree unless asked.
Use Zig **0.17.0**, Deno, and a current Rust toolchain compatible with Pen. Read
`AGENTS.md`, `compiler/guide.md` and `zig-native/CONTRACT.md`. From the Blot
checkout:

```sh
zig version
ZIG_GLOBAL_CACHE_DIR="$PWD/build/zig-global-cache" deno task build:compiler:dev
deno run -A scripts/storage_handoff/build_gdev.ts > /tmp/gdev-main.log 2>&1
python3 scripts/storage_handoff/report.py /tmp/gdev-main.log
```

The retained harness uses the real Gdev `src/main.blot`, `pen.json`, imports,
assets and storage settings, with the compiler cache disabled. It preserves a
unique attempt directory below ignored `build/`. It is now tracked under
`scripts/storage_handoff/`; the old copies and detailed logs under `build/` are
local evidence and will not travel through Git.

After main builds, rebuild Pen on the new machine
(`cargo build --release -p pen` in `../pen`) and run:

```sh
python3 scripts/storage_handoff/run_pen.py --launch
```

This launches the real Gdev through Pen headlessly for one 640×480 frame. It
requires successful exit, exactly one trace, a completed guest/render marker and
a PNG. Inspect the PNG. Configure a software Vulkan driver if the machine needs
one; the script preserves explicitly configured driver environment variables. Do
not substitute a synthetic guest for this milestone.

## Frozen contracts and language

- `func`, explicit `return`, and `->` between curried parameters; `$`
  constructors.
- Primitive `Bool` values are `true` / `false`; logical words are `and` / `or`.
- Array literals always use `#[]`; array capability belongs in the type. Lists
  retain `[]`. Compile-time `#run`, `#if` and `#do` are part of this migration.
- Session owners are named pools. Frame access and borrowed views are invocation
  local; record descriptors are aliases, not snapshots. Host/worker boundaries
  exchange copied numeric packets. Keep worker jobs/data queues; language tasks
  are being retired.
- ABI 8, version-2 numeric session protocol, Gdev schema 26 and packet operation
  order remain fixed. Storage: 2 MiB temporary, 256 KiB persistent, 2 MiB
  transport, 4096 owner slots.
- Gdev's `world_storage.FrameAccess` describes the existing 165-field frame
  record; ten game stages use it. Its four storage callbacks have explicit pure
  effects. Building callbacks use typed forwarding functions.
- Hand's scratch transaction ties input, merged working access and consumer to
  one generic type. Ten replacement fields preserve their types while changing
  owner identities; callback effects remain polymorphic. No full-frame import
  cycle or duplicated schema was introduced.

See [the active task record](tasks/STORAGE_REWRITE.md),
[the memory contract](zig-native/SCOPED_STORAGE.md),
[the design review](zig-native/STORAGE_REWRITE_REVIEW.md), and tasks 110–121.
The scoped data-stack backend exists, but ordinary legacy backend retirement and
full application qualification remain unfinished. Do not claim measured Gdev
runtime or compile-time improvements yet.

## Earlier handoff verification (not rerun)

- Complete native inventory **2,670 tests compiles** with the native Zig
  backend. This is not an exhaustive native execution pass.
- Focused native laws pass for exact generalized row witnesses, same immutable
  row aliases, checked instance ownership retained as rigid facts, and merge
  selection identity with independent admission checks. The row-substitution law
  preserves `Foreign` labels and correlation.
- Both executed-Wasm record-merge laws pass: owner/callback behavior with right
  replacement precedence, and scratch borrow-escape rejection.
- Std/prelude migration: 25 checks passed and one scalar-export law failed. The
  same failure was reproduced against the pre-migration std snapshot. A later
  focused array-contract batch passed ten checks with that same failure. Scoped
  backend global/nonfunction entry support remains pending; do not hide the
  fixture with `#run`.
- The required `deno task test:compiler` was run for this checkpoint. Its smoke
  phase passed three checks and failed the project wire-contract law at
  `zig-native/tests/zig_project_protocol.test.ts:404`: expected diagnostic span
  ends 43/48, observed 42/47. The full gate stopped there; release/exhaustive
  qualification is **not complete**. See the committed evidence note.
- Handoff Zig lint passes with zero findings (553 production files plus the test
  fixture). Three temporary-buffer lifetime warnings in the new native
  regression were fixed using synchronous borrowed inquiry helpers.
- Pen `cargo fmt --all --check` passes in both workspaces.
- Latest semantic compiler before handoff-only changes: binary SHA-256
  `d372edd37b3124b88f8737b1f6c616ae95a0a56ed2142dd19ab0c478e254846b`, raw
  identity `29bc25d3f516f7de415236e372873045a651686c80f0d7f4daa167c46ac45a4a`,
  configured Gdev identity
  `71db1abcb18e7df70ea95c47d8c9061681fbe9222e809043840e6156ceaede9d`. These
  identities are distinct; binaries and caches must be rebuilt locally.

Temporary `NUM_*`, `ROOT_*` and `SOURCE_WORK_FINAL` failure diagnostics remain
in compiler sources. Remove them after the application candidate works, then run
affected checks and Zig lint. The latest final-failure merge diagnostics were
already removed. One output block-break/return inference defect remains tracked
in the task record. Source solver inquiries still discard private existential
equalities; do not thaw all private rigids independently, which would lose
correlation between inquiries.

Older checkpoints are kept in the
[earlier handoff in Git](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/CONTINUE.md).
Their test counts and performance results do not qualify this rewrite.
