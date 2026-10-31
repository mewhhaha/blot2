# Continue here — owned-storage rewrite

## Current cloud frontier

One real Gdev main frame now works in native Pen. The 2026-10-31 run exited
zero, completed exactly one guest trace and one headless step, rendered a
complete frame and saved an inspected 640×480 PNG of the authored startup
letter board. This establishes first-frame integration; broader gameplay,
recovery, browser and release/performance qualification remain pending.

- [Portable result and exact identities](tasks/storage-handoff-evidence/2026-10-31-first-frame.json)
- [Inspected screenshot](tasks/storage-handoff-evidence/2026-10-31-first-frame.png)
- Local artifacts: `build/storage-integration/gdev-one-frame/attempt-eru2w98y`.

The real module is 45,764,043bytes. Its largest function body is 2,245,344bytes,
maximum combined parameters/locals 20,175 and global count 236,431. V8 and actual
Pen Wasmtime49 validate it. All existing source, storage and engine limits held.
The cold compile took 2,188.86seconds; this is evidence, not a performance claim.

The frame used the installed `zig-native/zig-out-dev/bin/blotc` (SHA prefix
`e6ccd2d4`). A separately checked `zig-out-cleanup` candidate (`38d40a78`)
removes temporary compiler prints; its full restoration Wasm is byte-identical.
Keep the exact frame/compiler/source identities in the portable record when
qualifying later candidates. The successful installed binary remains available.

## Current implementation and next work

Read `AGENTS.md`, `tasks/STORAGE_REWRITE.md`, `compiler/guide.md` and
`zig-native/CONTRACT.md`. The rewrite remains unfinished: retire the ordinary
legacy backend and qualify remaining fixtures against named owners, preserving
assertions, deterministic behavior and workload sizes. Greenfield changes are
welcome; do not keep superseded APIs or compatibility implementations.

Retained compiler fixes include closed generic layout caching, exact selected
call/type evidence, defining-module obligations, nominal field witnesses,
checked scratch writer planning, late local compaction and scoped refinement
indexing. Closed machine ranges become private helpers after escape/release
checks. Cross-body registers use private per-root globals reset only on original
function entry. Branch/signature, reachable-cycle, coordinate and indirect-call
guards remain enforced. Only committed helpers credit their own per-body work;
cumulative work and provisional limits remain intact. Detailed laws and failed
predecessors live in the evidence and pinned Git history, not this resume note.

Current source boundaries are concrete: Ink's retained-instance projection keeps
its order/extra guards; generated packet integers and numeric halves use explicit
U32-to-F32 conversions; restoration comparisons select F32 explicitly; station
restore loops alias named owners instead of carrying unrelated access callbacks.
Gdev simulation excludes borrowed UI rows while preserving the 165-field public
FrameAccess. Canonical generated codec policies and packet ordering are intact.

Production main exports one actual game entry. Optional tracing/reference
entries live in `../gdev/performance/*_main.blot`; their older comparison runners
still need migration. Gdev's plugin deadline is 7,200seconds for the cold build;
compiler work, engine, asset/reply and storage limits were not raised.

## Run and inspect a new candidate

Use the existing sibling checkouts. Build matching tools using Zig 0.17.0 with
`-Dllvm=false` for development and the checked-in Pen Rust toolchain. On another
machine configure the native compiler plugin and a headless software Vulkan
driver. Do not open desktop windows or substitute a synthetic guest.

```sh
python3 scripts/storage_handoff/run_pen.py --launch
```

The runner compiles real `../gdev/src/main.blot` with its imports, assets and
storage settings and writes a unique attempt below `build/storage-integration/`.
Require all runner checks and inspect the resulting PNG. For an isolated compile:

```sh
deno run --no-config --no-lock -A scripts/storage_handoff/build_gdev.ts > /tmp/gdev-main.log 2>&1
python3 scripts/storage_handoff/report.py /tmp/gdev-main.log
```

Keep large logs/build outputs ignored; commit concise identities, results and
useful visual evidence. Continue pushing coherent checked batches to `main` and
verify the remote SHA. Environment publication requires an explicit request.

## Frozen contracts

- ABI 8, session 2, saved framing 26 and packet operation order stay fixed.
- Storage remains 2 MiB temporary, 256 KiB persistent, 2 MiB transport and 4096 owner
  slots. The project reply budget remains 64 MiB including Wasm and assets.
- Production expansion remains 500,000 expressions per physical function;
  layout work 100,000. No further cap increase is authorized. Engine limits stay
  7,654,321 function-body bytes, 50,000 combined parameters/locals and 1,000,000 globals.
- Declare independent named owners. Frame/access records alias live pools;
  borrowed views are invocation-local. Copy retained state and host/worker
  numeric packets explicitly. Checkpoint/restore is explicit; renderer rejection
  does not roll simulation back. Language tasks are retired; host workers remain.
- Use `func`, explicit `return`, curried `->`, `$` constructors, primitive booleans,
  `and`/`or`, and `#[]` arrays. Lists use `[]`. Compile-time `#run`, `#if`, `#do`
  remain part of the migration.
- Gdev FrameAccess has 165 fields and four explicitly pure storage callbacks.
  Building callbacks use typed forwarding functions. Hand's transaction keeps
  input, merged working access and consumer tied to one generic type; its ten
  replacement fields preserve types while changing owners and callback effects.

See `zig-native/SCOPED_STORAGE.md`, `zig-native/STORAGE_REWRITE_REVIEW.md` and
storage tasks 110–121 for the remaining design and requirements.

## Qualification still pending

The full compiler gate was attempted again after diagnostic removal, but cannot
fetch locked Baba 9.0.1 from `npm.jsr.io` through the configured proxy. No manifest,
lockfile, TLS or checksum was changed. All 2,716 native tests compile; five affected
native laws and both-tier sync/async restoration checks pass. The cleanup emits
identical restoration Wasm. Changed-file lint is zero; the broad scan reports 25
findings exactly matching the pre-cleanup baseline.

Broader compiler/library/game and host/browser acknowledgement, rollback and
recovery gates remain open. Preserve the known associated-result latent-effect
layout baseline, earlier scalar-export and wire-contract span assertions, and
the output block-break/return inference defect. Source solver inquiries still
discard private existential equalities; do not thaw all private rigids separately
and lose correlation between inquiries. Temporary NUM/ROOT/SOURCE_WORK prints
have been removed.

Historical measurements and the complete integration trail remain in
[tasks/storage-handoff-evidence/2026-10-30-cloud-main.json](tasks/storage-handoff-evidence/2026-10-30-cloud-main.json)
and pinned Git history. They qualify their own candidates; the first-frame
record above identifies the candidate actually inspected.
