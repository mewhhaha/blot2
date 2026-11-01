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

Whole Gdev remains unfinished. The graph-sharing candidate exceeds both a
five-second diagnostic and one bounded thirty-second run; there is no current
whole-game size or fresh frame. Roughly **1 MB** remains the owner's
expectation. The historical frame-qualified main took 2,188 seconds and produced
47.4 MB, mostly code. Release builds and release performance remain pending.

Closed-row certificate paths now hash lazily, preserving exact receipt bytes,
multiplicity and work limits. Native sparse paths require **2 hashes rather than
1,026**, and target-free paths require none. Real producer checking improves
modestly; the smaller language fixture is effectively unchanged. See the
[receipt evidence](zig-native/measurements/receipt-path-hashing-2026-11-01.json).

The next measured frontend target is local array generalization. A bounded
observer finds hundreds of closed `ResizeArray F32` rebindings in the real
`encode_render_views` producer, each surrounded by unrelated generic field
requirements. Skip generalization only when its quantifiers and retained
predicates are provably empty; preserve contract, method, explicit and
generative paths. The same-imports/tiny-entry ablation still exceeds five
seconds, so producer checking alone needs improvement. The game imports about
45,000 source lines across 207 modules, including the prelude.

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

Astra xhigh reviewed the semantic fixes and performance batches. Earlier gate
attempts on the frame candidate were blocked fetching locked Baba 9.0.1. This
host reaches protocol preflight and fails on existing operand-span ends,
independently reproduced with the preserved baseline compiler. Full
qualification remains pending. The graph-sharing batch's seven focused laws and
28 guests pass on its pinned candidate. The receipt batch compiles **2,754
native tests**, passes **350/351** broader sampled laws with the same
associated-partial baseline failure, and passes all three exact eager-oracle
laws without heap allocation. The original Gdev language fixture passes six
entries/11 assertions per sync/JSPI mode. The body-reuse suite remains **17
passed/16 failed** on both baseline and candidate; those existing work
assertions are not a pass. Full Zig lint reports zero findings across 567 source
files. The required full gate still stops at the existing protocol operand-span
preflight failure. Broader integration and release coverage remain open.

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
