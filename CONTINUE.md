# Continue here — owned-storage integration

## Current cloud frontier

Continue until one real Gdev frame runs in native Pen and inspect the PNG. No
current main Wasm or frame has succeeded. Preserve ABI8/session2, framing26,
the165-field FrameAccess, packet order and the storage capacities below.

Production source expansion remains500,000 expressions per function. Astra xhigh
reviewed one bounded1,000,000 experiment; other limits are unchanged and there
is no further automatic increase. The latest completed full attempt,
`main-7d1564b64ec56839`, passed trails/map and stopped at569,125 in
`robots.claimed_as` because Activity had no equality implementation. Gdev
`e9127dd` supplies the five constructor comparisons; all25 pairs and real claim
mutation pass in both tiers and sync/async. Its full retry
`main-133334896341e559` was stopped after focused probes found later failures.

Use compile-only probes of the real `game.played.update` and `.render` with
`world.with_owners`, `host.with_frame` and canonical FrameAccess to isolate late
failures cheaply. Both stages now finish source emission, after invocation-local
global borrows and concrete generated codec policies. Gdev37775ff and
Inkb0ec918 preserve exact ActorObservation framing and pass strict encode/decode,
inspection and malformed-input checks in both tiers/sync-async. Native generation
check and Astra xhigh review pass. General contract-method lowering is deferred.

The current blocker is emitted root size: update15,294,397bytes and
render13,958,167bytes, above the7,654,321function-size limit. Both V8 and actual
Wasmtime49 reject update. Ignored diagnostic clients captured the bytes without
altering production validation. Compaction runs (1,258,823->480,431locals), but
large callback-heavy gameplay remains inline. Per-inline instruction costs and
filtered writer-decline diagnostics are identifying the precise admission gate.
Do not raise engine, source or storage caps to conceal this failure. Probe drivers
live below ignored build/; tracked full-main/Pen runners remain authoritative.

Planner closures now retain obligations from their defining module. Named and
closure planning scope and restore active goals; factory arguments are planned
in the caller first. A minimal imported nested-callback law reproduces the old
index93/length51 panic and passes with U32/F32 in both tiers and sync/async. The
native law proves the caller goal exceeds the helper's complete type table and
passes exhaustive OOM. Four affected native laws also pass; all2,696 tests
compile. The guest batch is35passes/1recorded baseline associated-result layout
failure. Astra xhigh reviewed the code; changed Zig lint and TS formatting pass.

Inline specialization results now capture their selected type substitutions. A
Pose3 argument had the correct physical identity but an empty generic witness
that resolved as Robot after a previous argument. Actor/Pose/Actor with
identical word layouts reproduces the old failure; Some/Nothing combinations
pass both tiers/sync-async with the snapshot. The new low512 native law passes
exhaustive OOM; recursion rejection passes and all2,697 tests compile. The guest
batch is 37passes/1recorded baseline failure. Astra xhigh reviewed the one-line
fix; lint/format pass and the required full gate was attempted (registry
blocked).

Loaded user nominal fields now retain checked semantic witnesses. Closed
cached layouts carry empty-context evidence; open generic layouts capture the
selected substitutions. Imported Vector/Pose readers reproduce the old add
dispatch failure and execute in both tiers/sync-async with retained values,
owner mutation and signed zero. The native law passes exhaustive OOM; all2,698
native tests compile and the affected guest batch is39passes/1known baseline
associated-result layout failure. Astra xhigh review and changed-file lint pass.

Late scoped-only local compaction is retained (`d2a09a2`): single-definition i32
locals confined to one straight-line segment reuse dead slots after ownership
and safepoint lowering. Parameters, default-zero reads, other types, multiple
writes and cross-control values stay separate; hidden-local markers decline. The
original101×250 ordered-Foreign guest now executes in both tiers/sync-async.
Five native laws pass, including exhaustive OOM and50,001 input locals reduced
to one. No source-expression or guest limit changed in that checkpoint.

Ink map.locate's explicit Maybe U32 result (`fbe379b`) passes five key-policy
probes and existing map laws. Brush edges now build into a GrowArray and freeze
once; the focused cube witness passes geometry, uniqueness, vertex degree and
output independence in both tiers/sync-async. Retained compiler/source fixes and
detailed evidence live in
[the cloud-main evidence](tasks/storage-handoff-evidence/2026-10-30-cloud-main.json)
and pinned Git history, including exact generic contexts/keys, ordered writer
scratch footprints, checked getters/partials, return termination and private
append regions. Do not relax those contracts while fixing later failures.

The required full compiler gate was attempted and remains blocked before tests
fetching locked Baba9.0.1 through the registry proxy. Registry additions are an
unapplied saved draft; dependencies, lockfiles and TLS are unchanged. Native
Pen, its compiler plugin and Mesa lavapipe are available locally. Keep unrelated
fixture migration and performance work paused.

If the bounded main experiment completes below1M, Astra supports a deliberate 1M
production policy checkpoint with peak per-function work, total work, time/RSS
and default/boundary laws recorded. Then make the next full compile the real Pen
run, avoiding another standalone rebuild. If1M exhausts, keep that ceiling and
reduce the measured expansion. A real PNG still requires inspection.

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
