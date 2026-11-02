# Continue the owned-storage rewrite

## Current frontier

Compilation latency is the active priority: **subsecond Gdev compilation**, with
the next gate below five seconds. Game diagnostics default to five seconds and
have a hard 30-second iteration cap. Never repeat the recorded 36-minute build
or an unchanged five-minute diagnostic.

The latest completed actual main takes **9.87 seconds total**: 10.6ms session
startup plus 9.86s build, producing **28,996,417 bytes of Wasm**, cache
disabled. Compiler source is `46e435504c69ed60e8813ec11d3cff1f84aa420b`, Zig
0.17 Fast/LLVM; workload pins are Gdev `b60f8c76` and Ink `7085c97e`. The
preceding completed workload took 10.64s/29.21MB; earlier checkpoints took
11.81s/31.65MB, 15.15s/32.72MB and 17.45s/38.82MB. These are single fresh
completions, not distributions. See
[latest full-main evidence](zig-native/measurements/gdev-after-nominal-hooks-2026-11-02.json).

A separate phase profile puts 8.83s in the backend, 0.52s in checking, 0.12s in
lowering and 0.10s in validation. Backend allocation requests total 8.40GB. CPU
sampling attributes substantial work to copying 256-byte metadata values,
recursive shape checks, structural keys and descriptor/type resolution.
Pointer-based recursive queries did not establish a timing win and remain
private. The active larger probes select literal catalog fields without
materializing whole records and bulk-initialize scalar literal arrays from
static data. The five-second gate remains unmet.

The configured Gdev launcher now uses this exact optimized release at
`zig-native/zig-out/bin/blotc`; the handoff runner follows that path. Delivery
verification produces identical Wasm. Its 10.07s timing may overlap sampling and
is not an isolated performance comparison. Preserve token/epoch, alias,
read/write ordering, frozen/init, lifetime and escape checks. Physical
optimization does not weaken complete source or semantic proofs.

## Checked latency batches

The next checked encoding cut groups consecutive equal Wasm local declarations
without changing slot order, types or indices. All 2,847 native laws compile; 95
selected laws pass exhaustive faults, 63 guests pass and Zig lint is clean.
Renderer Wasm falls 211,471->200,300B with all seven streams identical. On the
existing full-main artifact, grouped headers would save 1,633,402B (5.63%); this
is an encoding-size counterfactual, not a newly compiled release or a CPU win.
The required gate retains the same 48/1 baseline. See
[local declaration evidence](zig-native/measurements/local-declaration-groups-2026-11-02.json).

Gdev groups its four world callbacks in one concrete `Hooks` nominal with the
same closed effects, captures and forwarding. `FrameAccess` remains structural.
The compiler finds nested callbacks within depth/work bounds and applies its
existing physical field projection. Source/method/owner proofs and full semantic
witnesses remain unchanged. All 2,846 native laws compile; 94 selected laws pass
exhaustive faults, 63 guests pass and Zig lint is clean. All seven renderer
streams match. The final optimized release passes the world/editor witness's
seven checks in both sync and JSPI modes. See
[bundle evidence](zig-native/measurements/nominal-callback-bundles-2026-11-02.json).

The preceding batches complete direct word calls for owner arguments, box
immutable witnesses, avoid impossible primitive substitution scans, reuse nested
key scratch and canonicalize primitive key memo atoms. Exact semantic witnesses
retain their units/environments. Allocation-only timing remains inconclusive.
Their checked requirements and exact evidence remain in
[word calls](zig-native/measurements/owned-word-calls-and-cold-metadata-2026-11-02.json),
[key scratch](zig-native/measurements/type-key-scratch-2026-11-02.json) and
[primitive memo](zig-native/measurements/primitive-type-key-memo-2026-11-02.json).
Earlier
[transport](zig-native/measurements/direct-plans-and-aggregate-transport-2026-11-02.json),
[completed-function](zig-native/measurements/completed-functions-and-immutable-metadata-2026-11-02.json)
and
[context sharing](zig-native/measurements/completed-context-aliases-2026-11-02.json)
records qualify their exact candidates.

Structural global type IDs remain
[rejected after a renderer regression](zig-native/measurements/rejected-global-type-ids-2026-11-02.json).
The
[source call-shape retests](zig-native/measurements/rejected-source-call-shapes-d8-2026-11-02.json)
and earlier
[source experiments](zig-native/measurements/rejected-source-call-shapes-2026-11-02.json)
remain rejected. Private pooling, eager-schema, primitive-environment and
callback-path allocation probes did not establish CPU gains and are not landed.
Direct ECS indexing also remains private: it loses the existing mixed fixed/
resizable-array source contract. Tag-only match reads are a separate bounded
probe; they do not yet qualify ECS `.at` calls or establish a speedup.

The required full gate still stops at **48 passed/one baseline List/chunk
storage_escape**, bytes312..345. The broader static family has one separately
reproduced ECS storage_unsupported baseline. Full release/native qualification
remains pending. A fresh main frame is also pending: available Pen binaries
predate ABI 8; renderer streams and the world/editor witness do not qualify a
full game frame.

Release snapshots under `build/bench/frozen-release-COMMIT` use plain
`git archive`, not worktrees, and pin source/toolchain/binary hashes. Start LLVM
builds in the actual snapshot directory. Reserve the five-minute build for
meaningful checked candidates; native/noLLVM iterations take seconds.

## Checked compiler fixes

The last frame-qualified compiler is the reviewed contract-method candidate, SHA
`52e04df6262c1572f07e9f16d474019a77dbdfbfd5fc1c042ea8fa3cb3242004`. Older exact
candidates may be absent locally; portable evidence qualifies its named
candidate rather than every later revision.

- [Imported opaque layouts](tasks/storage-handoff-evidence/2026-10-31-opaque-layouts.json)
  use exact closed producer metadata while preserving public opacity.
- Loop refinements, literal SIMD forwarding, proven-empty nested rows and
  impossible pattern fallbacks have executed regression coverage in the linked
  records under `tasks/storage-handoff-evidence/`. Original hauling and full
  packet fixtures now run without dummy rows or altered algorithms.
- [Lexical schemes](tasks/storage-handoff-evidence/2026-10-31-lexical-schemes.json)
  use bounded immutable lists, avoiding sparse temporary-fact saturation.
- [Indexed mutation](tasks/storage-handoff-evidence/2026-10-31-indexed-fields.json)
  preserves original owner and selected-field equations, including two indices.
- [Callback values](tasks/storage-handoff-evidence/2026-10-31-callback-values.json)
  align source/Core recipe classification while keeping invocation and no-store
  checks strict. All six original Gdev restore tests and both rejection tests
  pass. The latest native inventory compiles 2,730 tests; 435/436 affected laws
  pass with the same independently reproduced associated-partial baseline
  failure. All 61 affected guest tests pass.

[Contract methods](tasks/storage-handoff-evidence/2026-10-31-contract-methods.json)
now select exact visible implementations with full signature/effect evidence and
context-sensitive reusable calls. Original Gdev language tests and Ink
custom-codec persistence, including all 260 truncated inputs, pass on the final
candidate. Actual main now passes the recorded native frame on this binary.

Astra xhigh reviewed the semantic and performance boundaries. The earlier
typed-call compiler `fca4f6a1` compiles **2,776 native tests**. All five focused
typed-call laws pass in full fault mode, including allocation failures;
**434/435** broader sampled laws pass with the independently reproduced
associated-partial baseline failure. All **68 affected guests** pass, including
mixed aggregate/callback schemas, descriptor aliases, read replay, both tiers,
sync/JSPI and retained edits. Original Gdev language entries pass six entries/11
assertions per mode; the same 25,651-byte output remains. Zig lint has zero
findings across 572 files.

Body-reuse/text tests now pass **33/33**. Earlier 17/16 unrestricted runs
forwarded `HOME`, enabling disk-cache contamination between retained and
supposedly fresh clients. The body-reuse harness now explicitly disables
persistence. Those old figures were not compiler semantic regressions. The stale
five-character `true` span assertion is also corrected; all 42 protocol tests
pass.

The required full gate currently stops at **48 passed, one failed** in smoke.
The remaining list/chunk loop owner-escape failure is independently reproduced
on preserved `0faa0cbb`; it is not a passing gate. Release, full-native and
broader integration qualification remain pending.

## Remaining execution work

Source checks are distinct from emitting original exports and running
assertions. The `52e04df6` Ink inventory passes all 325 files: 322 valid files
and three intended semantic rejections, with matching end-of-run source digest.
Gdev's `52e04df6` inventory also passes all 441 current files:438 valid files
and three intended rejections. Both complete audits have matching end-of-run
source digests. Exact records and reproduction commands are in
[the migration evidence](tasks/storage-handoff-evidence/2026-10-31-source-migration.json).

All 68 original prepared-physics comparisons now pass on `9902355f`, including
all three modes at2,048 fixed bodies, with named source/proxy owners and
unchanged limits. All nine adapter entries pass 71 cases per mode. On
`52e04df6`, all six Gdev language/Format entries, six restore entries, both
restore traps and actor presentation's66 checks pass. The parser's typed leaves
execute, while its complete original module reaches the checked layout budget.
Full affordance, salt-clicks and remaining original-export qualification stay
open. Preserve original workloads and assertions while resolving those gaps.

Ordinary legacy backend retirement is still unfinished (task 120). Some pure
programs still emit ABI 3; do not fake ABI 8 with unused owners or claim that
the whole rewrite is complete. Task 121 covers final behavior and measurements.
Release/performance claims require the qualified release compiler.

## Integration and checks

Use the existing sibling checkouts. Build with Zig 0.17.0, checking
`zig version` first, and `-Dllvm=false` for development/native tests. Use
coherent affected batches and the required full gate as documented in
`AGENTS.md`.

Run actual Gdev main through native Pen, including its real imports and assets:

```sh
python3 scripts/storage_handoff/run_pen.py --launch
```

The default command recompiles every run. To retry rendering an already checked
actual main, use its exact artifact hash (the current record above identifies
this build):

```sh
python3 scripts/storage_handoff/run_pen.py --launch --compiled-main ../gdev/.pen/runtime/game.wasm --expected-wasm-sha256 63a4ae23b2ff61198b0d02ad47c2cd1342a524f33f16becc0a193ec2374fef0c
```

This copies the unchanged Wasm and starting scene into a fresh bundle, retaining
the original assets/text/locales/presets and all six host checks. It uses Pen's
standard raw-Wasm loader. Explicit Vulkan driver settings are respected; the
runner can also find the optional onboarding Mesa sysroot. No source compilation
or optimization runs in this mode. Rebuild after semantic changes rather than
reusing an older artifact.

Require every runner check and inspect the PNG. For a compile-only diagnosis:

```sh
deno run --no-config --no-lock -A scripts/storage_handoff/build_gdev.ts --timeout-ms 5000 > /tmp/gdev-main.log 2>&1
python3 scripts/storage_handoff/report.py /tmp/gdev-main.log
```

Use `--entry tests/language_compatibility.blot` for the small real fixture and
`--profile` for completed-build phase attribution. The diagnostic has a hard
30-second session-plus-build cap; the default remains five seconds, and timeouts
remain incomplete. It reports startup, build and total compile time separately.
There is no multi-minute diagnostic override. Defer the Pen frame driver's
regular application pipeline until bounded compilation is fast enough. The older
PNG does not qualify a later compiler.

The reusable frontend inventory checks unused declarations through overlays:

```sh
deno run --no-config --no-lock -A scripts/migration_audit.ts --project ../gdev --expectations ../gdev/tests/migration_expectations.json --report /tmp/gdev-audit.json
```

It does not emit original exports or execute their assertions. Its project
source digest excludes external library snapshots; rerun after dependencies
settle. Keep large outputs ignored and commit concise portable evidence.

## Frozen contracts

- ABI 8, session 2, Gdev saved framing 26 and packet order remain fixed.
- Gdev storage: 2 MiB temporary, 256 KiB persistent, 2 MiB transport, 4,096
  owners. Reply budget: 64 MiB including assets.
- Production expansion: 500,000 expressions per physical function; layout work:
  100,000. Engine bounds: 7,654,321 body bytes, 50,000 parameters/locals and
  1,000,000 globals. Do not raise these limits to pass fixtures.
- Named owners are independent. Access records alias live pools. Borrowed views
  remain invocation-local; copy retained history and host/worker packets.
  Preserve callback effects and explicit checkpoint/restore. Renderer rejection
  is not rollback. Language tasks are retired; copied-packet workers remain.
- Gdev FrameAccess has 165 fields and four explicitly pure storage callbacks.
  Preserve exact generic field types and real latent callback effects.

Continuously commit coherent checked batches to each `main` and verify remote
hashes. Preserve unrelated work. Environment publication requires a separate
explicit request. Older checkpoint narratives remain in pinned Git history and
portable evidence, rather than duplicate continuation documents.
