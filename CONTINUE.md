# Continue the owned-storage rewrite

## Current frontier

Compilation latency is the active priority: **subsecond Gdev compilation**. Do
not repeat the recorded 36-minute main build. Diagnostics default to a
five-second deadline and kill the compiler on timeout.

Completed ground callee prerequisites now share proofs within one equation
inquiry. A nominal depth-ten/eight-call graph that exhausted the unchanged work
budget now completes with **80 expansions and 80 hits**. Requested field
equations still follow their original proof path, and temporary solver
identities never enter receipts.

Covariance and normalization now preserve shared type graphs instead of copying
binary trees. Closing uses its existing exact context memo for source stores
too. The depth-sixteen source probe falls from roughly **3.5 seconds to 0.1
second**, with **858,720 to 6,750 type nodes** and identical **2,935-byte
Wasm**. The deeper case now completes below 0.2 seconds instead of exceeding
five seconds.
[Pinned evidence](zig-native/measurements/proof-and-type-sharing-2026-11-01.json)
keeps intermediate failures, matched pairs, real-workload controls and compiler
identities separate. A smaller Gdev fixture still has a modest latency
regression; the final invariant-leaf shortcut reduces that overhead.

Whole Gdev remains unfinished. The current candidate exceeds five-second main
diagnostics in both optimized and development modes with four optimizer workers;
there is no current whole-game size or fresh frame. Roughly **1 MB** remains the owner's
expectation. The historical frame-qualified main took 2,188 seconds and produced
47.4 MB, mostly code. Release builds and release performance remain pending.

The first type-structure architecture experiment is measured and **rejected**.
Copy-on-change during nonempty substitution passed its semantic laws but reduced
actual render/matrix/settings type-node creation by less than 0.25%; checker
time remained flat. Its larger production patch is archived, not installed.
Fourteen diagnostic counters now separate inclusive node growth and traversal
entries for import, substitution, resolution and covariance. The real render
producer creates 9,427 nodes under resolution versus 1,757 under substitution;
these are counts, not CPU shares. Variable views equal new binders in all three
producers, so historical-view canonicalization has no measured opportunity.
Do not add that optimization or a fresh cache. A deeper type representation
change needs to identify which changed children/rows force normalization copies.
See [the rejected experiment and attribution](zig-native/measurements/type-structure-experiment-2026-11-01.json).

Literal closures now share exact typed definitions across parent generators.
Captures and arguments travel as ordinary parameters; plain aggregate results
use caller-owned scratch. The actual returned-closure Mat4 probe at eight sites
shrinks **21,826 to 19,206 bytes**, with matched median **279 to 255 ms**. One
site grows **403 bytes** from call/scratch overhead. Native laws require one
closure definition reused inside two shared callback-reader parents.

Plain inline keys now omit only constructor refinements erased by that ABI.
Actual Ink easing over nine constructor states drops **10 to 2 definitions**,
**76 to 68 functions** and **9,132 to 8,300 bytes**; compilation time is flat.
Descriptor-reader/writer ownership and initialization facts remain exact.
Qualified/goaled closures and pending array destinations retain conservative
fallbacks. Six prior Ink controls are byte-identical, and Gdev language entries
execute unchanged. See [typed-call evidence](zig-native/measurements/typed-call-sharing-2026-11-01.json).

Ink/Gdev source rewrites are authorized. The first concrete candidate is
`kites.draw`: append directly to the caller frame pool instead of constructing,
freezing and copying a temporary draw array. Its original integration fixture
still exceeds five seconds, so no game source change is installed. Robot
accessory and crystal draw arrays have the same pattern; preserve draw order
and qualify an actual original stream before changing them.

Closed-row certificate paths now hash lazily, preserving exact receipt bytes,
multiplicity and work limits. Native sparse paths require **2 hashes rather than
1,026**, and target-free paths require none. Real producer checking improves
modestly; the smaller language fixture is effectively unchanged. See the
[receipt evidence](zig-native/measurements/receipt-path-hashing-2026-11-01.json).

Closed array locals now omit provably empty generalization, preserving contract,
method, explicit and generative paths. In the actual render-producer probe this
removes 659 generalizations and reduces candidate scans from 359,768 to 50,653.
Three matched pairs improve **882 to 642 ms**, with checking **509 to 258 ms**
and identical tiny-entry output. This is producer checking, not whole-game
emission. See the [array-local evidence](zig-native/measurements/closed-array-locals-2026-11-01.json).

Plain aggregate readers now share definitions and exact admission receipts.
Actual Ink `transform.matrix` reader DAGs at depth six improve **669 to 375 ms**,
**26,185 to 14,266 bytes**, and **96,094 to 4,140 admission visits**. Result keys
bind semantic and physical layout; every caller owns its shape and scratch.
Variant/borrow results keep their existing paths. The Gdev language control is
roughly flat in latency but grows **273 bytes (1.07%)**. See
[aggregate-reader evidence](zig-native/measurements/aggregate-reader-sharing-2026-11-01.json).

Selected-address loads now avoid whole-row scalarization for plain, stable
indexed rows. Actual `render.Settings` with eight blur writes shrinks **18,299
to 7,131 bytes**; marginal write cost falls **1,427 to 89 bytes**. Source-work
charges, bounds checks, alias writes, RHS `self` and post-RHS address validation
remain intact. Matrix control outputs are byte-identical; overall compilation
latency is roughly flat. See
[selected-field evidence](zig-native/measurements/selected-field-loads-2026-11-01.json).

Owned assembly now honors development/optimized tiers, optimizer workers, IO,
profiling and physical machine-code sharing. Its omitted stats previously
reported zero functions even though optimized passes ran. All six Ink controls
remain byte-identical across the old default and all four tier/worker pairs;
three rotated repetitions show roughly flat latency with variance. The matrix
control reports 58 functions and 58 parallel jobs with four workers. Defaults
stay optimized/serial/unshared; complete execution policy already belongs to
retained output identity. See
[owned assembly evidence](zig-native/measurements/owned-assembly-options-2026-11-01.json).

A three-second debugger sample catches actual main in source checking:
`Engine.instantiate -> Store.openCovariant -> memo insertion`, while three
frontend workers wait. This is one observed phase, not a CPU percentage or full
latency measurement. A short follow-up captures two root publications, too few
to rank hot paths. Measure unchanged substitution copies on a completed producer
before changing row opening; preserve fresh rows and exact callback requirements. See
[the bounded checking sample](zig-native/measurements/gdev-checking-sample-2026-11-01.json).

Variant-bearing descriptor helpers remain a separate hypothesis. The real Robot
presentation path carries `Maybe Robot`, and original `robot_flight.blot` also
exceeds five seconds. `stableDescriptorShape` rejects variants for descriptor
reader/writer schemas, but the separate inline-call path already admits plain
variant values. Measure actual misses before widening that guard. Outline bank
slot reuse is secondary: historical globals are huge, but code bodies account
for most of the 47.4 MB. Do not repeat unchanged main diagnostics or reorder
optimization around outlining without new evidence.

The declaration-demand manifest is **diagnostic only**, with exhaustive source
checking unchanged. It now follows existing lazy initializer semantics instead
of seeding every non-function and attributed declaration. On identical sources,
main demand falls **5,277 to 4,241 of 5,957 declarations**, but retains **82.6%**
of original function-body bytes. Tiny-entry retention falls **77.2% to 2.1%**;
actor falls **80.1% to 9.8%**. All three inventory pairs have zero fallbacks and
matching module-source digests. Planning takes about 165/25/47 ms respectively
in these single pairs, not compile-speed measurements. See
[the corrected demand inventory](zig-native/measurements/lazy-declaration-demand-2026-11-01.json).
The earlier [over-rooted inventory](zig-native/measurements/declaration-demand-inventory-2026-11-01.json)
remains pinned historical evidence. Main still retains 98.5% of its previously
selected original body bytes; blanket initializer roots do not explain its
latency. Generated assets are included: 264 loaded modules on main. Unchecked
source names must never become completed typed interfaces.

Earlier descriptor, nominal and scalar call-sharing results remain in their
linked records under `zig-native/measurements/`. Those changes reduce synthetic
Wasm growth; they do not establish a current whole-game result.

This is a greenfield project. Breaking changes are welcome; remove superseded
APIs and implementations. Preserve useful behavior, assertions, deterministic
math, original workloads and independent references. Read `AGENTS.md`,
`compiler/guide.md`, `zig-native/CONTRACT.md` and `tasks/STORAGE_REWRITE.md`.

Actual Gdev main passed one headless native Pen frame on the last
frame-qualified compiler `52e04df6` and matching host. All six checks pass. The
inspected 640×480 startup image and guest trace match the original frame byte
for byte.
[Current exact identities and result](tasks/storage-handoff-evidence/2026-10-31-migrated-frame.json)
reuse
[the identical existing PNG](tasks/storage-handoff-evidence/2026-10-31-first-frame.png).
The earlier e6 compiler's
[first-frame record](tasks/storage-handoff-evidence/2026-10-31-first-frame.json)
remains historical evidence. Broader gameplay, browser, recovery and release
qualification remain open.

The active source/API migration covers the full Ink/Gdev inventories, fixtures,
generators and active documentation. Current language uses `func`, explicit
`return`, curried `->`, `$Constructor`, primitive booleans, `and`/`or` and
`#[...]` arrays. Grammar-rejection fixtures, foreign shader syntax and
historical captures intentionally retain their own text. Generated sources must
come from generator inputs, never manual output patches.

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

Astra xhigh reviewed the semantic and performance boundaries. The current
compiler `fca4f6a1` compiles **2,776 native tests**. All five focused typed-call
laws pass in full fault mode, including allocation failures; **434/435** broader
sampled laws pass with the independently reproduced associated-partial baseline
failure. All **68 affected guests** pass, including mixed aggregate/callback
schemas, descriptor aliases, read replay, both tiers, sync/JSPI and retained
edits. Original Gdev language entries pass six entries/11 assertions per mode;
the same 25,651-byte output remains. Zig lint has zero findings across 572 files.

Body-reuse/text tests now pass **33/33**. Earlier 17/16 unrestricted runs forwarded
`HOME`, enabling disk-cache contamination between retained and supposedly fresh
clients. The body-reuse harness now explicitly disables persistence. Those old
figures were not compiler semantic regressions. The stale five-character `true`
span assertion is also corrected; all 42 protocol tests pass.

The required full gate currently stops at **47 passed, one failed** in smoke. The remaining list/chunk loop owner-escape failure is
independently reproduced on preserved `0faa0cbb`; it is not a passing gate.
Release, full-native and broader integration qualification remain pending.

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
most 30 seconds; a timeout remains incomplete. Defer the Pen frame driver's
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
