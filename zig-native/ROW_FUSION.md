# Checked packed-row producer and consumer fusion

Task 040 extends flat scalar row borrowing into ordinary named source consumers
and small producer/consumer compositions. Admission uses checked layouts and
bounded use evidence, with no library-name recognition. Array/List storage,
logical lengths, saved snapshots and evaluation order keep their existing
contracts. Widths 1–16 qualify; reference-bearing, nested and larger rows keep
ordinary storage.

The emitter already owns loop row views. An admitted named consumer rebinds that
same view to its checked parameter instead of capturing an allocated row. The
concrete layout must match exactly and the callee's bounded use proof must
accept. In-loop flat-row parameters expose small bodies to the existing
64-node/depth6/4096-emitted-instruction inlining bounds, allowing a producer's
fields to reach ordinary scalar replacement in its consumer. There is no new
emitter field, map, collection ABI or general interprocedural escape analysis.

Direct Array loops now use the same checked view rule as List leaves. A call may
use a bare row only through a known eager function arrow; demand parameters
decline. A consumer that needs a whole value receives a newly owned row base,
copied as raw 32-bit words in field order. It never receives an interior Array
or List-leaf pointer. Aliases, captures, loop carries and unsupported forms keep
the ordinary representation. Unknown calls may materialize a value; they grant
no permission to borrow it across a call or defer its evaluation.

Effects and arithmetic are emitted in source order. No reduction is reassociated
and no callback/trap is hoisted. Callee body preparation records the existing
exact inline-body dependency before emission; changing an inlined producer or
consumer invalidates its executable caller even when its type stays equal. Core
remains immutable and all prepared emitter state follows existing OOM cleanup.
The merged optimizer interpretation is v7, including compact roots, associated
types and root-frame demand; stale settings are optional misses.

## Focused laws and rejected attempts

The native consumer control fills either collection with a static 3-field row,
then consumes each row through an ordinary named function. Its optimized caller
has no scalar row allocation call. List directory scratch retains its mixed
owned allocation. Exhaustive backend allocation failures preserve the Core
snapshot and release partial publication.

Executed controls cover 31 record/tuple widths in both optimized and development
tiers (62 Array/List entry functions per tier), 600 rows, a 257-row slice
crossing leaves, a saved original and individually rounded F32 operations.
Cancellation, NaNs, infinities, subnormals and signed zero are included. Further
laws cover U32 wrapping; composed producers; saved updates; early break/return;
rows saved through calls, closures and demands; callback order; traps and
recovery.

Source and compiled dependencies each change the producer and consumer body,
reject an invalid edit, recover and restart from an owned checkpoint. Successful
retained/restarted bytes equal fresh bytes; failed diagnostics equal fresh
diagnostics and failed publication leaves the last checkpoint exact. Existing
row/cursor/width17/reference-bearing/suspension laws run alongside these checks.

Focused qualification on the old 002/034 base passes 22 executed laws and the
native consumer/OOM law. Porting onto the qualified 039/055 release passes 8
additional LLVM guest laws and the analyzer: 348 files, zero findings. All
original worktrees/logs remain; copied evidence lives in ignored
`build/bench/row-fusion-040/`.

The first machine-only consumer-inlining prototype passed native tests but left
source row copies and increased emitted bytes. It was rejected and reverted;
`wasm-consumer-prototype.patch` preserves it. The initial native assertion also
counted producer/List-directory allocations and was too broad; the final control
isolates temporary scalar row boxes. Initial guest fixtures incorrectly used
`@list.get`, and a revision test needed explicit TypeScript failure narrowing.
Those failed logs remain separate from accepted checks.

## Pinned release measurements

The isolated source tree is `e191930790cbc616fbbcfc6fb1e7695aa4dac91f`, based on
record `f80a1f7`. Standard Zig 0.17.0 LLVM/Fast binary SHA256:
`468aa4e851cb65c08e9991dd38bc245319d0a8b195f12855c1573264cda886af`. It is
immutable at`build/bench/row-fusion-040/blotc-isolated`. The baseline is the
accepted 039/055 binary
`47021c966f75fbb6063b9de52d476fe944a8aa16dc6bc47aeae66cfbf4dd9095`. Pins,
sources, Wasm, 31 raw paired samples and compiler phases are in
`row-fusion-040/{pins.json,isolated/report.json}`.

The merged 024/035/040 initial release is
`9ea894d41e157824dd951e5f92827284da98c59af47c8b5831ebd04623688b21`,
implementation tree`92e09418c4449fd772c0037ead43cd922e51fb6a`, compiler
source`497069ed0c61181232520acdb249b35828334ae1`. Its rows report is
`build/bench/joint-024-035-040/rows/report.json`. CPU 7, 12 warmups and 31
alternating pairs use unmodified production Wasm and 100,000 retained rows:

| Fixture                          | Baseline guest CPU ms | Merged guest CPU ms |  Ratio |
| -------------------------------- | --------------------: | ------------------: | -----: |
| Array named consumer             |                 4.748 |                .102 |  .0215 |
| Array composed producer/consumer |                 4.815 |                .102 |  .0212 |
| List named consumer              |                 1.420 |                .074 |  .0521 |
| List composed producer/consumer  |                 1.818 |                .075 |  .0413 |
| Array direct field-read control  |                  .094 |                .098 | 1.0426 |
| List direct field-read control   |                  .089 |                .073 |  .8202 |

Array committed high-water is 2,228,224 bytes and List 1,441,792 bytes for both
binaries. Removed allocation traffic is not a reduction in committed pages:
baseline boxes are reclaimed/reused. The native zero-box control, rather than
memory page equality, establishes elimination. The isolated consumer ratios are
.0206–.0646, with direct controls 1.0347/1.0000; the merged List direct gain
also includes 035's smaller ownership journal. Neither measurement attributes
all combined behavior to 040.

Seven alternating compiler pairs compare fresh compilation and 20 hot seed edits
of the six combined fixtures. Fresh wall medians are 4.492→4.271 ms; childCPU is
below the 10 ms accounting tick. 20-edit CPU medians are 40→40 ms, wall
87.413→77.746 ms. Every shape's fresh/retained bytes are exact within its
compiler; intentional optimization changes permit cross-compiler byte changes.
These tiny phases do not establish a general compiler CPU improvement.

## Integrated qualification

Implementation `2689ad5` is complete for task 040. The pinned tree above passes
`deno task test:compiler`: full native suite and 925 guest/client tests, all
eight unchanged allocation budgets. `deno task lint:zig` with the pinned local
analyzer reports 349 files and zero findings. Zig 0.17.0 was checked before each
build batch. Exact commands, source/binary identity, raw logs and every
comparison are in `build/bench/joint-024-035-040/qualification-pins.json`. No
source correction or repeated full gate was needed after combining the
focused-green slices.

Seven alternating cold public pairs preserve diagnostics, semantic/prepared
counters and each compiler's output stability. CPU ratios are .9946–1.0501;
requested allocation deltas −3,855..+31,041 bytes, all peak deltas zero and
teardown zero. Twelve public Wasm modules change through the ownership/fusion
optimizations; scalar bytes are identical. Seven synthetic fresh/retained/edit/
restart pairs preserve all bytes even across compilers, with teardown zero.
These costs qualify the combined batch; no general compile speedup is claimed.
Task 024's general forms/edit target and 035's tracing-removal/CPU gates remain
open independently of completed 040.

The reproducible benchmark command is:

```sh
taskset -c 7 deno run -A build/bench/row-fusion-040/measure.ts \
  build/bench/joint-024-035-039-055/blotc-final-candidate \
  build/bench/joint-024-035-040/blotc-initial-candidate \
  build/bench/joint-024-035-040/rows
```

Fusion remains bounded and opportunistic. Large/deep functions, lazy or escaped
row uses, unknown shapes/effects and rows beyond the admitted scalar width use
ordinary owned values. Removing collection construction, all row boxes or all
generic iterator state is not claimed; tasks 041/047 cover separate later hills.
