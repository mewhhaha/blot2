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
both tiers and sync/async. Its extended U32/F32 cases also preserve signed zero,
infinity and NaN across repeated invocations (four tests pass). Changed Zig files have zero analyzer findings. The
required full gate was attempted before checkpointing and remains blocked by
the locked Baba9.0.1 registry proxy fetch. No dependency or lockfile changed.

The actual native Pen attempt is running at
`build/storage-integration/gdev-one-frame/attempt-5442nr03`, using the matching
default compiler. The prior `attempt-s1i49tls` hit Pen's default 300-second
plugin deadline, which killed and reopened the active compiler; its retry was
stopped and its evidence retained. Gdev now configures a reviewed 7,200-second
cold-build deadline through the existing plugin setting. Compiler work, engine
and storage limits are unchanged. The subsequent four-export attempt
`attempt-5rjaql86` was stopped for reviewed packaging cleanup: production main
now has one unchanged gameplay entry; optional trace/reference entries and names
are preserved in dedicated Gdev performance fixtures. The partial first-export
forecast was about 31 MB, while the 64 MiB reply also carries assets. This is
an intentional packaging change, not a measured completed-module size failure.
All four entry files parse and source-body identity checks pass; performance
consumer migration remains deferred. No real-main success or PNG has been
observed yet. Continue the active attempt before launching another full compile.

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

## Run and inspect the frame

Resume the active native attempt above before launching another full compile.
On a new machine, read `AGENTS.md`, `compiler/guide.md` and
`zig-native/CONTRACT.md`; build the matching compiler, Pen and plugin using the
pinned toolchains and existing sibling checkouts.

The tracked runners use Gdev's real `src/main.blot`, `pen.json`, imports,
assets and storage settings. For an isolated main diagnostic:

```sh
deno run --no-config --no-lock -A scripts/storage_handoff/build_gdev.ts > /tmp/gdev-main.log 2>&1
python3 scripts/storage_handoff/report.py /tmp/gdev-main.log
```

For the actual frame:

```sh
python3 scripts/storage_handoff/run_pen.py --launch
```

Pen compiles the project through its native plugin, runs one headless 640×480
frame and saves a unique directory under `build/storage-integration/`. Success
requires zero exit status, exactly one guest trace, completed guest/render
markers and a PNG. Inspect that PNG. Use a configured software Vulkan driver
when needed; do not substitute a synthetic guest for this milestone.

The normal Deno task currently cannot fetch locked Baba from `npm.jsr.io`
through the configured proxy. The local-only diagnostic driver works with the
flags above; no manifest, lockfile, TLS or checksum has changed. Build outputs
and detailed logs are ignored local evidence; keep portable results in the
[tracked record](tasks/storage-handoff-evidence/2026-10-30-cloud-main.json).

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

## Deferred qualification

The full compiler gate and broad library/game fixture migration remain pending.
Besides the current associated-result baseline, earlier qualification recorded
a scalar-export fixture failure and a project wire-contract diagnostic-span
mismatch. Preserve their assertions when those gates resume. Current native
Pen/plugin builds and generation checks do not qualify the full host/browser
acknowledgement, rollback and recovery matrix.

Temporary `NUM_*`, `ROOT_*` and `SOURCE_WORK_FINAL` diagnostics remain in compiler
sources. Remove them after the real frame works, then run affected checks and
lint. The task record also retains an output block-break/return inference defect.
Source solver inquiries still discard private existential equalities; do not
thaw all private rigids independently and lose correlation between inquiries.

Historical counts, identities and detailed checkpoints remain in
[Git history](https://github.com/mewhhaha/blot2/blob/093bcc2c767e718e0082f9385d6515b61bf9fb33/CONTINUE.md)
and the tracked evidence. They do not qualify the current combined candidate.
