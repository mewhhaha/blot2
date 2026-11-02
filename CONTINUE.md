# Continue the owned-storage rewrite

## Current frontier

Compilation latency is the active priority: **subsecond Gdev compilation**, with
the next gate below five seconds. Game diagnostics default to five seconds and
have a hard 30-second iteration cap. Never repeat the recorded 36-minute build
or an unchanged five-minute diagnostic.

The latest completed actual main takes **10.75 seconds** and produces
**29,211,724 bytes of Wasm**, cache disabled. Compiler source is
`6155af2d662a5740d1af7d0481c20648386d3911`, Zig 0.17 fast/LLVM; unchanged
Gdev/Ink code remains `7733add6`/`d520a903`. Same-workload predecessors took
11.81s/31.65MB, 15.15s/32.72MB and 17.45s/38.82MB. These are single completions,
not distributions. See
[latest full-main evidence](zig-native/measurements/gdev-after-owner-word-calls-2026-11-02.json).

The separate profile attributes 10.27s to the backend and 9.25GB requested
allocations. Word calls avoid 196,780 argument-buffer words across 17,519 calls;
primitive resolution avoids 221M impossible environment comparisons. The
five-second gate remains unmet. The configured Gdev launcher now uses the
installed optimized compiler at `zig-native/zig-out/bin/blotc`; the default
handoff runner follows that configured path. That path completes the unchanged
main in 10.57s with the exact same Wasm. Gdev config-only evidence follows its
new source checkpoint separately.

The checked batch removes proven invariant whole-record transport through
branches/loops, completes zero-owner plain functions with the direct word ABI,
skips scalar shadow walks on completed strong keys, sparsifies loop read frames
and reuses raw record-name ordering. Child type inheritance drops proven
shadowed history only when at least75% can be removed. All 2,839 native laws
compile; 80 selected laws pass exhaustive allocation faults, 56 guests pass and
Zig lint is clean. Seven actual renderer streams match. Plain sharing reduces
renderer expressions 7,919->7,056 and shadow visits 28,531->24,891, but
increases Wasm 220,771->224,349B; record-name caching is byte-identical. A
165-field control falls 30,138->17,810B with 2,061 copies avoided; the
local-reference fallback stays byte-identical. The optimized main result above
qualifies this batch. See
[transport evidence](zig-native/measurements/direct-plans-and-aggregate-transport-2026-11-02.json).

Preserve token/epoch, alias, read/write ordering, frozen/init, lifetime and
escape checks. Physical optimization does not weaken complete source/semantic
proofs. Prior
[completed-function](zig-native/measurements/completed-functions-and-immutable-metadata-2026-11-02.json)
and
[context sharing](zig-native/measurements/completed-context-aliases-2026-11-02.json)
evidence pins their exact candidates. Structural global type IDs remain
[rejected after a renderer regression](zig-native/measurements/rejected-global-type-ids-2026-11-02.json).
The
[same source rewrites retested on d8](zig-native/measurements/rejected-source-call-shapes-d8-2026-11-02.json)
remain rejected: only3.1% fewer expressions and0.18% fewer bytes, no latency
win. The two
[source-call shape experiments](zig-native/measurements/rejected-source-call-shapes-2026-11-02.json)
are also rejected and reverted on their named old compiler.

The required full gate still stops at **48 passed/one baseline List/chunk
storage_escape**, bytes312..345. The broader static family has one separately
reproduced ECS storage_unsupported baseline. Full release/native qualification
remains pending. A fresh main frame is also pending: available Pen binaries
predate ABI 8; renderer stream coverage does not qualify a full game frame.

Release snapshots under `build/bench/frozen-release-COMMIT` use plain
`git archive`, not worktrees, and pin source/toolchain/binary hashes. Start LLVM
builds in the actual snapshot directory. Reserve the five-minute build for
meaningful checked candidates; native/noLLVM iterations take seconds.

## Next checked latency batch

Direct word arguments now cover completed owner calls up to 512 parameters.
Scalar/Unit calls avoid argument-buffer owners; aggregate/borrow returns use a
result-only slot. Immutable callable and type witnesses are boxed in their
owning arenas. Primitive resolution skips impossible substitution searches;
structural-key completion removes a repeated hash lookup. All 2,842 native laws
compile, 90 selected laws pass exhaustive faults, 61 guests pass, and Zig lint
is clean. Seven actual renderer streams match; Wasm falls 224,349->211,471B. The
required full gate retains the same 48/1 baseline failure. Optimized actual main
measurement is pending; the latest completed figure remains 11.81s. See
[checked batch evidence](zig-native/measurements/owned-word-calls-and-cold-metadata-2026-11-02.json).

The next allocation-only cut reuses a nested descriptor scratch stack within
each key builder. Exact key/budget/OOM laws pass; all 2,843 native laws compile,
91 selected laws pass exhaustive faults and 61 guests pass. Renderer Wasm and
all seven streams remain identical, with backend allocations 95,585->81,620.
Latency is inconclusive; bundle a larger change before another LLVM build. See
[scratch evidence](zig-native/measurements/type-key-scratch-2026-11-02.json).

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
deno run --no-config --no-lock -A scripts/storage_handoff/build_gdev.ts --compiler zig-native/zig-out-dev/bin/blotc --timeout-ms 5000 > /tmp/gdev-main.log 2>&1
python3 scripts/storage_handoff/report.py /tmp/gdev-main.log
```

Use `--entry tests/language_compatibility.blot` for the small real fixture and
`--profile` for completed-build phase attribution. The diagnostic accepts at
most 30 seconds. Only an explicitly requested full timing measurement may use
`--measure-total --timeout-ms 300000`; the default remains five seconds, and
timeouts remain incomplete. Do not use this long allowance for iteration. Defer
the Pen frame driver's regular application pipeline until bounded compilation is
fast enough. The older PNG does not qualify a later compiler.

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
