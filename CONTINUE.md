# Continue here — owned-storage checkpoint, 30 October 2026

## Current cloud frontier

A negative-only immutable prerequisite-header memo is now implemented. Its new
native regression and four existing authority/correlation laws pass; all 2,671
native tests compile. The first candidate still exhausts validation at the same
render call. Full qualification is pending: the compiler gate cannot fetch Baba
from blocked `npm.jsr.io`, and full Zig lint reports 24 findings outside the
changed file. Registry additions are saved only as an environment draft.

Next measure `groundSharedFieldOwner` copy, deep-resolution and matching costs.
Prefer the existing head-only physical-field proof path if that measured work is
excessive; do not prune supposedly unrelated goals or weaken private-witness
correlation.

The bounded brush, element-clock and deposit contracts cleared their earlier
numeric type-evidence diagnostics. Main still fails at `game.blot:384`, the
`render_world editing access presentation` call: checked module validation work
is exhausted. No main Wasm or real Pen frame has passed.

The unused `render_world.finish` argument is removed; the real finish callback
still runs later in `present`. Whole-frame annotations increased work and were
reverted. A temporary diagnostic build shows the render body itself completes in
59,455 work debits; the enclosing `game_using` consumes 31,252,019 of the
module's shared 32-million allowance before failure. Nested prerequisite work is
the next investigation target. Identify expensive declarations and distinguish
identical retries, failed alternatives and distinct substitutions before adding
reuse. Inclusive trace records must not be summed across nesting levels.

The cloud-main evidence JSON and compressed trace in Blot's
`tasks/storage-handoff-evidence/` preserve the measurements. Compiler source was
restored exactly; no proof rule or budget changed. Native Pen and its compiler
plugin builds pass, as does Gdev `pen codegen --check`. The Blot formatter is
still unrun because the locked Baba host `npm.jsr.io` returns proxy HTTP 403.

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

The finite render-boundary review is **not implemented**: if the next blocker
requires it, pin `game.layer`, `render_world`, and the single shadowing goals
layer callback to existing FrameAccess/Presentation/render.FrameAccess types;
preserve callback effect parameters and editor policy types.

Older checkpoints are kept in the
[earlier handoff in Git](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/CONTINUE.md).
Their test counts and performance results do not qualify this rewrite.
