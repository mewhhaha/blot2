# Continue here — owned-storage checkpoint, 30 October 2026

## Current cloud frontier

Record matching now indexes field names for 17–256-field records, preserving
first right-side matches, left traversal and every child type/effect/owner
proof. The fixed 512-slot ordinal table allocates nothing; every probe is
bounded and charged. It clears the actual-main validation-budget boundary. A
typed game forwarder with inferred effects, an explicit F32 music result and a
generic sound-policy receiver clear the subsequent tutorial.music_reveal
callback proof. An explicit set.Set math.Vec4 annotation at the clearing-members
allocation clears the subsequent layout error. Attempt `main-a4f8c5d5de900dd9`
now fails at world_storage.application's returned policy record (line684):
selected call type exceeds the supported bound. The guard in
scoped_backend.selectionType combines depth>128 and exhausted work; distinguish
them and identify the repeated/type path before changing code. Do not increase
either bound. No main Wasm or Pen frame has passed.

The earlier zero-span layout diagnostic was an unresolved generic map key, not
evidence of a nested resizable payload. Tracing the existing failure unwind
identified clearing_members at world_storage:186; both clearing APIs already
require set.Set math.Vec4. The allocation annotation preserves that contract,
owner lifetime and separate bucket storage. Diagnostic source was restored
exactly.

All **76** package/core contract laws pass with zero failures, skips, leaks or
logged errors, and all **2,674** native tests compile. The new laws cover record
width thresholds, reordered/colliding/duplicate names, bounded work, missing and
forged children, correlated witnesses, Foreign callbacks and rigid ownership.
The 166-field regression uses 499 debits instead of the former 14,028; this is a
specific comparison law, not an application performance measurement. Changed
production-file Zig lint passes with zero findings. The changed test file has
one preexisting allocation-size warning at line2705, outside the changed laws.

The dictionary-equivalence trace contains 2,963 whole-dictionary entries, 2,961
successful exits and 89 solver lifetimes. **Zero** previous successful exits
match a later entry under the full solver/context/state key. The 1,168 matches
obtained by ignoring store changes justify no proof cache. Negative immutable
header metadata and unchanged failed-comparison epochs remain the only new
reuse; real writes/failures still roll back.

Editor Settings retains its existing Camera/Array U32 callback inputs with
independent effect rows. HUD settings/layout locals are canonical and preserve
arithmetic order. Subsequent station, settings-leaf and generic-layer annotation
experiments were measured and reverted. Do not reapply them or broad whole-frame
render annotations. The unused render_world.finish argument is removed; actual
finish still runs later in present.

Full qualification remains blocked before tests by the locked Baba registry
proxy tunnel; full Zig lint previously had 24 findings outside the changed
production file. Registry additions are saved as a draft, not applied or
published. The Blot formatter is also blocked. Native Pen/plugin builds and Gdev
pen codegen --check pass. Purchase-feedback fixture imports/constructor identity
are repaired, but its existing shared helper still fails type checking; no
fixture assertions were removed.

The
[cloud-main evidence](tasks/storage-handoff-evidence/2026-10-30-cloud-main.json)
and compressed traces preserve the measurements. Temporary diagnostic compiler
sources were restored exactly; normal failure diagnostics remain below.

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
- Gdev's `world_storage.FrameAccess` describes the existing 166-field frame
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
