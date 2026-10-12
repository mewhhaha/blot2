# Rolling and summary implementation qualification

Tasks [045](../tasks/045-implement-rolling-reductions.md) and
[046](../tasks/046-implement-composable-summary-trees.md) implement the
[accepted contract](ROLLING_SUMMARIES.md) in ordinary source at local
implementation `4013b10` on 12 October 2026. Both tasks are complete. Broader
compiler cutoff and tracing replacement remain assigned to 024/035.

Qualified tree `3688e1965213b06e36a1ad5118ab1c6f1c1de54b`, compiler source
`48f7bf8cd3219535013dd8eb96b28e0c67702bcd`, standard LLVM/Fast executable
SHA-256 `44af80a95af5de58c521a7d520c5d8c6ea993e09aae1c06e9031f3d5dbd9ec2b`
(43,593,088 bytes), compiler identity
`96551c0168b67c28d63df67103be50bfc1bfa23dc9b798f29405f0b52de2df20`. Exact
source, patch, binary, script and report pins are in ignored
`build/bench/joint-024-035-045-046/qualification-pins.json`.

The APIs live in [rolling](../std/rolling.blot) and
[summary](../std/summary.blot), sharing a private
[persistent AVL tree](../std/_summary_tree.blot). No library name grants
compiler privileges. Callers explicitly provide the algebra; closed pure arrows
do not prove associativity or inverse laws. Ordered fold retains the existing
full-window reduction order and supports effectful reducers.

## Algorithms and ownership

Monoid windows buffer the first complete window before invoking the reducer,
then cache subtree summaries. Subsequent pulls drop the oldest leaf and join one
new leaf through balanced boundary spines. Group windows use the same persistent
queue, applying one inverse and two combines per subsequent result. Its queue
caches the supplied identity instead of recomputing user summaries. The dummy
combiner captures only that identity.

Summary construction merges equal-height runs in an at-most-32-entry forest,
then joins the remaining runs in source order. Query combines cached contiguous
subtrees; set and concat copy and balance changed spines. Empty joins return the
existing operand. Bounds checks use subtraction before addition, including U32
maximum inputs. Old cursors and trees keep their own immutable versions.

Checked source layouts retain reference-bearing fields, including cyclic values.
The compiler follow-ups used by these ordinary libraries restore publication for
Array copies and use one concrete checked physical instance for eligible
single-use generalized local producers. Unknown, captured or multiple physical
instances keep the conservative representation. These are general compiler
facts, documented in [the ownership contract](CONTRACT.md) and
[tracing replacement](TRACING_REPLACEMENT.md).

## Executed laws

`zig version` reports 0.17.0. `deno task test:compiler` passes the full LLVM
native suite and 961 guest/client tests, including all eight unchanged
allocation budgets. The analyzer passes 351 Zig files with zero findings. The
library laws exercise both codegen tiers. Laws cover:

- U32 recomputation at empty/singleton/uneven/full/over-wide windows, wrapping
  sums and maximum widths; associative noncommutative groups and summaries.
- Sequential F32 cancellation, subnormals, infinities, NaNs and signed zero.
- No pulls for take 0; one iterator creation; no reducer on a short initial
  window; no prefetch; ordered effect traces and rejected fast effect arrows.
- Reference snapshots, host rejection/retry, suspended request cancellation,
  strong memo/State cycles and finite long streams.
- Every query range through 257 elements, uneven concatenations, bounds before
  callbacks, old versions across updates/pressure/resets and retained source/
  dependency/checkpoint failure/recovery parity.
- A shared 31-level tree represents 2^31 leaves without materializing that many
  values. Its last-leaf update preserves the old tree and exact U32 totals;
  doubling it traps for length overflow before a deliberately trapping combiner,
  and a later call still succeeds. Both codegen tiers pass.

The tests are in [rolling_execution](tests/rolling_execution.test.ts),
[summary_execution](tests/summary_execution.test.ts),
[reductions_ownership_execution](tests/reductions_ownership_execution.test.ts)
and [reductions_revision](tests/reductions_revision.test.ts). The registered
[native law](src/rolling_tests.zig) releases frontend ownership before backend
emission, checks frozen-Core immutability and injects backend allocation
failures, including reference-bearing summaries.

## Counts and storage

Preserved inputs, executables, Wasm, scripts, raw samples and failures are under
ignored `build/bench/rolling-045/`. Final reports use the pinned release above;
earlier provisional/failed reports remain separate. Compiler comparisons use
seven alternating release pairs; primary guest comparisons use 31 alternating
warmed pairs after eight warmups. Instrumented copies measure callbacks and heap
payload separately from unmodified guest CPU.

Private instrumentation widens callback arrows and sequences their calls with
`use`, preserving algorithm bodies/grouping to count user calls. Shipped
callbacks stay closed and pure. Five outputs at width 257 take 1285 ordered
combines,322 monoid combines, or 265 group combines and four inverses. At 4096
leaves, build takes 4095 combines; representative query/set/concat paths take
10/12/12. All 4096 singleton concatenations retain height 13 with at most 13
combines per operation. An uneven 257-leaf build takes 263 combines because
final balancing revisits a bounded boundary spine; the build contract is linear,
not exactly n−1 calls for every length.

Release heap profiling records all requested physical payload, including journal
pages. Width 257 monoid/group windows peak at 20600/14068 bytes; ordered windows
peak at 8524. Growing the stream from 4096 to 65536 items leaves those peaks
unchanged. A31-leaf current summary plus its original snapshot peaks at 6472
bytes for both 4096 and 65536 updates. The cached 4096-byte journal page remains
after a call and releases at shutdown, which leaves zero live payload and no
roots or leases. These are requested payload counts; allocation headers and
capacity are reflected in committed memory. At width 257, monoid commits 196608
bytes and group/ordered 131072, independently of stream length.

Original/current tree profiling at 512/4096/16384 leaves peaks at 41216/188804/
631284 payload bytes and commits 327680/1114112/3473408 bytes. A4096-leaf tree
with 0/1/8/64 saved update versions peaks at 151860/151996/154436/174148 bytes,
charging shared structure and retained changed spines. Every fresh profiling
instance releases all payload at shutdown. The instrumenter checks helper
signatures before inserting counters and changes no heap layout.

Actual summary-build profiling exposed repeated cycle trials of live scalar
trees: fourfold input growth caused about 16-fold trial vertices. The isolated
035 acyclic proof now avoids those candidate scans while preserving typed-edge
traversal from real cyclic candidates. It consults every constructor in the
emitting source unit and declines foreign, unknown or mutable payloads. Added
callable variants revoke old claims through fresh/retained/checkpoint/OOM laws.
The failed `summary-runtime-prototype` report is retained.

## Runtime and compiler costs

The scalar rolling matrix spans 4096/16384 items and widths 1/3/31/257, compared
with ordinary windows plus full recomputation under the same qualified compiler.
Ordered ratios are 0.9938–1.0156, monoid 0.0826–0.5049 and group 0.0892–0.6264.
The widest fast windows are about 11–12× faster. Growing input fourfold grows
current work about fourfold at fixed width.

Summary construction at 512/4096/16384 leaves takes 0.483/3.774/15.587 ms: the
quadratic scan is removed and measured construction is linear. A plain fold
control takes 0.155/1.242/5.133 ms and does not build a tree; summaries cost
about 3× that control. Query workloads including setup and 1024 interval queries
take 1.623/5.767/18.638 ms versus 38.747/316.862/1228.427 ms for Array range
folds. Persistent set and concat workloads cost more than exclusive Array edits:
ratios 4.04–18.66 and 3.24–7.41 respectively, including setup. These are
recorded costs, not universal update/concat speedup claims. Source callback/path
counts separately establish the promised logarithmic operations.

Reference/cyclic payloads retain ordinary runtime ownership costs. Thirty-one
warmed samples charge actual cycle trials: at 16384 items and widths 31/257,
monoid takes 110.93/216.61 ms and group 116.91/209.53 ms. Fixed-width input
growth from 4096 to 16384 is about 4×, with committed storage unchanged; width
257 commits 196608 bytes. Genuine candidate walks remain and depend on the
reachable graph, so navigation/callback bounds do not promise a constant-time
collector pause. Reference summary payload graphs and explicitly saved versions
add their real retained cost; an arbitrary combine's own work is not constant by
assumption.

Seven public compiler pairs against qualified `850793f` preserve diagnostics,
semantic work and per-binary determinism. CPU ratios are 0.9945–1.0234,
requested allocation deltas−31880..+12039 bytes, peak deltas zero and teardown
zero. The new private acyclic helper intentionally changes 12 of 13 public Wasm
modules; the scalar control stays identical. Four synthetic workloads preserve
exact cross-compiler/fresh/retained/restart output and compared counters. Their
small CPU medians are coarse; no general compiler speedup is claimed.

## Remaining scope

The specified ordinary APIs, semantic laws, callback/navigation bounds,
persistent ownership and release qualification are complete. Task 047 owns
eliminating generic iterator allocation. 024/035 own broader body reuse and
physical tracing removal, including the historical ownership CPU gate. The
caller still supplies a valid total algebra; the compiler does not certify it.
Nothing is pushed and old artifacts remain preserved.
