# Continue the owned-storage rewrite

## Current frontier

Compilation latency is the active priority: **subsecond Gdev compilation**, with
the next gate below five seconds. The throughput target is a fresh, reachable
50k source lines in 0.5 seconds (100k lines/second), then one million lines/second.
Use `deno run -A scripts/bench/compiler_throughput.ts --compiler PATH --lines 50000`;
it reports exact lines, bytes, estimated tokens, emitted work, Wasm size and
executed checks. Generation and cold compilation remain visible; `--profile`
is a separate diagnostic run. The target is not yet qualified.
Game diagnostics default to five seconds and
have a hard 30-second iteration cap. Never repeat the recorded 36-minute build
or an unchanged five-minute diagnostic.

The latest fresh actual main takes **7.26–7.42 seconds total**, producing
**22,346,701 bytes of Wasm**, cache disabled. A separate profile takes 7.35s;
the configured-path run takes 7.42s with the same compiler identity and complete
Wasm hash. The preceding nominal-access release took 8.30s. These are individual
completions, not distributions. The five-second gate remains unmet. Exact
compiler/source identities are pinned in
[latest main evidence](zig-native/measurements/gdev-after-walks-and-bounds-2026-11-02.json).
Compiler snapshot is `a87c33c9` plus patch `9adda4ca4438`.

Getter selection now reuses the existing successful bounds receipts inside one
compile's immutable unit context. Exact method catalog, budget and privacy
checks still run. Plain/stable shape and Reader-width queries borrow child
metadata during recursion; stable shape checking uses one walk. This changes
no emitted Wasm bytes: the complete main hash matches the preceding release.
Backend time falls 7.41s->6.36s, with requested bytes/allocations essentially
unchanged at 6.17GB/5.74M. All 2,864 native laws compile; 113 selected laws pass
full allocation faults, 84 guests pass and Zig lint is clean.

Gdev FrameAccess is now fixed zero-argument single-constructor data. The compiler
keeps its wrapper/full source/type witnesses while passing only payload fields
proved observable by the complete existing footprint. Getter, missing-field,
whole-use and rich nominal cases retain full fallback. Hand transactions keep
the same resource scopes and generic consumer; ordered same-type field updates
replace their structural merge. A nominal-only source control lost most field
slicing and took 11.29s; the combined design restores that slicing.

The preceding nominal-frame profile put 7.41s in the backend, requesting
6.17GB through 5.74M allocations. That batch compiled 2,863 native laws and
passed 112 selected full-fault laws, 84 guests and Zig lint.
The final optimized release passes seven original world/editor checks and 160
new hand isolation/commit checks in sync and JSPI. See
[batch evidence](zig-native/measurements/nominal-frame-and-payload-slicing-2026-11-02.json).
Original elements_game retains its three assertions but hits the same baseline
emit-layout gap under both source forms; the new witness does not replace it.

The launcher selects the exact release and a fresh configured-path run verifies
its identity and identical complete Wasm hash. The tracked native frame runner
loads that artifact without recompiling, but installed Pen rejects ABI 8 before
rendering; no new frame/PNG is qualified. Its config parser/generator are also
older than the checkpointed inputs. Preserve generated bindings.

Closed-fragment replay, early scalar-key skipping and paged outliner facts are
held after neutral or worse CPU pairs. The callsite BodyInstance cache also
stays held after low measured preparation coverage. A later typed-body/type-node
representation must remove repeated resolution and Builder work rather than
wrap it in another cache. Both canonical type-store replacements now pass
focused correctness but remain held: World backend improves about 12%, renderer
3–4%, below their 20% gate for roughly 300 added production lines. Direct owner
inputs for Salt/Rock reduce bytes 1.3% but leave main CPU unchanged; trivial math
lambda flattening already happens in the parser. Extra pointer queries are also
neutral. No held patch changed live compiler/library/game sources. See
[probe evidence](zig-native/measurements/after-walks-and-bounds-probes-2026-11-02.json).

The private outliner preview shortcut passes its bound/OOM laws and improves a
synthetic component 9.65%, but the matched World backend is neutral
(2.738s versus 2.728s). Host CPU tuning is also neutral. Both remain held, with
no extra LLVM builds or live changes.

A bounded query ledger now measures exact repeats within actual body expansions,
with rollback-restored substitution identities and nested-query suspension. The
uncensored 1/128 cohort has no overflow: roughly 52–53% of resolution/scan work
repeats in World, but only 7.3% of layout work and 0.7% of admission work. These are
sampled work counts, not CPU savings. Builder serialization and mapping/refinement
outside these spans remain unmeasured. The result does not justify the proposed
resolution/layout-slot IR or its 25% backend gate; no new representation is
implemented. Do not reuse the initial censored run or multiply broad CPU family
unions by these ratios. A different typed-body design remains an open question.

## Latest checked transport batch

One physical argument preparation now feeds owned/Reader probes. Full original
source proof, mapping, goals and callbacks precede projection; Reader history
and expanded fallback retain originals. Wide callback-free anonymous records
use the existing complete source-footprint and root guards. Small recursively
plain, stable inline results return through eagerly allocated instance-private
word registers, copied immediately into fresh caller locals after all callee
cleanup. Other shapes retain the checked buffer path.

All 2,858 native laws compile; 106 selected laws pass exhaustive faults, 82
guests pass and Zig lint is clean. Seven renderer streams match, with Wasm
136,886->118,677B. The final optimized release passes seven world/editor checks
in sync and JSPI; that witness falls 997,699->711,173B. This does not qualify a
full-game frame. See
[transport evidence](zig-native/measurements/prepared-arguments-and-inline-returns-2026-11-02.json).
The launcher selects the new release at `zig-native/zig-out/bin/blotc`. A fresh
configured-path build takes 9.17s with matching compiler identity and identical
complete Wasm hash.

## Checked latency batches

Scalar literal arrays now create ordinary fresh checked owners and bulk-copy
immutable data placed beyond all owner/transport regions. Exact literal global
initializers retain ordinary source proof, mapping, effects and escape checks;
no supplied destination enters the shortcut. All original expression limits
remain: actual main peaks at 47,131 steps against 500,000. Tail rollback, scalar
bits, mutation, reset, retained length/value edits and empty arrays have focused
coverage.

Closed constant nominal records retain their complete source-body proof while
field projection emits only the selected primitive constant. Caller dictionary
spelling is mapped through source record destinations; unused invalid or
nonliteral siblings cannot bypass checking. Actual main folds 1,432 projections
and skips 283,832 fields. It also stores 50,020 literal bytes instead of
emitting 12,505 per-element writes. The preceding local-declaration grouping
preserves slot order/types/indices and is included in this release.

All 2,853 native laws compile; 101 selected laws pass exhaustive faults, 76
guests pass and Zig lint is clean. Renderer Wasm falls 211,471->136,886B with
seven complete streams identical. The final optimized release passes all seven
world/editor checks in sync and JSPI; that witness falls 1,663,892->997,699B. It
does not qualify a full game frame. See
[literal data/projection evidence](zig-native/measurements/literal-data-and-record-projection-2026-11-02.json)
and the preceding
[local encoding evidence](zig-native/measurements/local-declaration-groups-2026-11-02.json).

The launcher selects the exact new optimized binary at
`zig-native/zig-out/bin/blotc`. A fresh configured-path build verifies its
compiler identity and identical complete Wasm hash. Keep token/epoch, alias,
initialization, freeze, ordering, lifetime and escape checks strict. Physical
optimizations retain complete source/type evidence.

Earlier checked requirements and exact candidates remain in
[callback bundles](zig-native/measurements/nominal-callback-bundles-2026-11-02.json),
[word calls](zig-native/measurements/owned-word-calls-and-cold-metadata-2026-11-02.json),
[key scratch](zig-native/measurements/type-key-scratch-2026-11-02.json),
[primitive memo](zig-native/measurements/primitive-type-key-memo-2026-11-02.json),
[transport](zig-native/measurements/direct-plans-and-aggregate-transport-2026-11-02.json),
[completed functions](zig-native/measurements/completed-functions-and-immutable-metadata-2026-11-02.json)
and
[context sharing](zig-native/measurements/completed-context-aliases-2026-11-02.json).
Structural global type IDs remain
[rejected](zig-native/measurements/rejected-global-type-ids-2026-11-02.json), as
do the earlier
[source call-shape probes](zig-native/measurements/rejected-source-call-shapes-d8-2026-11-02.json).
Private pooling, eager-schema, primitive-environment, pointer-query and
callback-path probes did not establish CPU gains. Tag-only reads and the typed
ECS view bridge are held: actual activation is small and the bridge increases
net world-witness bytes. Removing Gdev's remaining text bundle also stays
private: one full-main completion is smaller but does not establish a latency
win. Do not copy these held patches into the compiler or siblings.

The required full gate still stops at **48 passed/one baseline List/chunk
storage_escape**, bytes312..345. The broader static family has one separately
reproduced ECS storage_unsupported baseline. Full release/native qualification
remains pending. A fresh main frame also needs a matching ABI 8 Pen host;
renderer streams and the world/editor witness do not qualify full gameplay.

Release snapshots under `build/bench/` use plain `git archive`, not worktrees,
and pin exact source/toolchain/binary hashes. Uncommitted checked candidates use
a pinned base plus a source patch and per-file hashes. Reserve LLVM builds for
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
- Gdev nominal FrameAccess has 165 fields and the concrete pure hooks bundle.
  Preserve exact generic field types and real latent callback effects.

Continuously commit coherent checked batches to each `main` and verify remote
hashes. Preserve unrelated work. Environment publication requires a separate
explicit request. Older checkpoint narratives remain in pinned Git history and
portable evidence, rather than duplicate continuation documents.
