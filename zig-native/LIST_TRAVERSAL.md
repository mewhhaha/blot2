# List traversal qualification

This record preserves the implementation boundary, measurements and remaining
work for packed List traversal. It supplements the public
[collection guidance](../std/PERFORMANCE.md) and the
[ownership contract](CONTRACT.md).

## Direct-loop span check

The List span experiment started from `632b461`, with the task inventory added
at `cb212f4`. It changes only the checked packed-row read in direct List loops.
Other row reads, including cursor extraction, keep their existing checks.

A direct loop resolves a nonempty immutable leaf before reading its row. Its
locals retain that leaf's allocation base, start word and exclusive end word.
The loop already proves that the row starts inside this span. `readListRow`
therefore needs only to check whether the entire row ends in the same leaf. Rows
crossing leaves retain checked per-word lookup. List storage bounds make the end
addition safe from unsigned overflow. The row still receives owned storage; this
change introduces no borrowed interior pointer.

Keeping the span in loop locals matters: a nested traversal can replace the List
descriptor's lookup cache, and a nested collecting loop can move the allocation
frontier. The immutable leaf remains reachable through the List. The span end is
reset each time the source loop starts, including when it is inside another
loop. No library names, user types or source spelling select the optimization.

### Pinned inputs

The ignored prototype remains at `build/experiments/list-span-source/`. Its only
changed existing source files were `src/core_backend.zig` and
`src/collection_tests.zig`; it also added `tests/list_span_execution.test.ts`.
The production port formats the two tests without changing their semantics.

| Input                                      | SHA-256                                                            |
| ------------------------------------------ | ------------------------------------------------------------------ |
| Packed main baseline executable            | `4abce406794c6ce6f6a9cad5e206bc981677205ade5a4b2d8111128d8ac0f1e3` |
| Experimental release executable            | `fb34ef7acf8575feeeb60d03e5b99f5cab3dc5cfb4a3de203c1b583ad0113cf1` |
| Production port executable                 | `034d660ce38691df9a18c895ab228c4d0a76d618aa1969117d16604e06ee2833` |
| Baseline compiler-identity file            | `66ab1d30f803e86341cfae61e41aedc247b6ffe7127f1c707d23e8fb0104853a` |
| Experimental compiler-identity file        | `65674e7fbd1593e5d1e2b5a0029898b3cda55c8542e8c87cc506f06220f147e0` |
| Production port compiler-identity file     | `454c9f8d22559647ee571c274cbbaed9c967ae7c252127f5c64ce32bedc811cc` |
| Experimental `core_backend.zig`            | `a4f33391a7800b22656f8f72271b053dc13828893261f27e389e0e393b6d2f48` |
| Experimental `collection_tests.zig`        | `3135b979fc7c1254e631e9a8a5535bfe360a2d57f4e42395dd754b5db694858d` |
| Experimental `list_span_execution.test.ts` | `07a0682624e3bd4140c27f996545879742518e3238b56c8bf329520c0f4034b2` |

The packed baseline was copied to `build/bench/list-span-baseline/` before the
production build. It matched the main executable at the start of qualification.
These are separate from the older boxed baseline,
`build/compiler-hills/final/blotc`, whose executable hash is
`150c2b032b43490434ba99c0bd91911de4bc8723fa3d4e4cf803d0f8fb88c413`. Its role and
provenance are recorded in the preserved packed-row qualification at
`build/compiler-hills/packed-rows-final/identity.json` and
`build/compiler-hills/qualified-packed-rows/runtime-qualified/report.json`.

### Validation

Qualification uses Zig 0.17.0 and Deno 2.9.7 (V8 15.0.245.2-rusty). Logs, raw
samples, input identities and differential artifacts are under the ignored
`build/bench/list-span-qualified/` directory. No private workload source is
included in this record.

- The focused executed-Wasm batch passed all 17 tests: the new span test,
  packed-row execution and revisions, cursor forks, and collection execution.
  Widths 1–16 include zero, one and two rows; either side of the first leaf
  boundary; multiple leaves; and 1,000 rows. Nested traversals, early break,
  sliced/appended snapshots, F32 values, effects and reference fallbacks are
  covered by this batch.
- The experimental source analyzer checked 285 Zig files with zero findings.
- A differential batch made 610 compiler invocations across 305 fixture/guide
  cases. It compared success, diagnostics, constant steps, code instances,
  deterministic work counters and teardown ownership. There were no semantic
  mismatches. All successful Wasm outputs matched except the guide's loop
  example, which shrank from 5,144 to 5,124 bytes. That 20-byte change is the
  intended direct packed-loop check removal.
- The native filter passed: 16 tests, comprising 15 suite discovery tests and
  `packed List span emission preserves immutable Core under allocation failure`.
  The targeted test uses explicit `@u32.add` intrinsics, so its source requires
  no implicit prelude. It compares the frozen Core stamp after both successful
  emission and the exhaustive failing-allocation sweep.
- All 488 successful differential Wasm modules passed `WebAssembly.validate`.
  Executing both versions of the changed guide module returned 45 for
  `sum_to 10`, 26 for `weighted` and 5 for `first_five`.
- The production source analyzer also checked 285 files with zero findings.
  `deno task test:compiler` passed the full native suite and all 590
  guest/client tests after the production port.

### Runtime measurements

`scripts/bench_packed_rows.ts` used ten warmups and 25 alternating samples for
each compiler. Values and guest-memory page counts matched for every fixture.
The machine was loaded; process CPU is reported separately from wall time.

| Fixture              | Baseline CPU, ms | Span CPU, ms | Baseline wall, ms | Span wall, ms |
| -------------------- | ---------------: | -----------: | ----------------: | ------------: |
| Retained Array rows  |            0.145 |        0.143 |            0.1444 |        0.1411 |
| Retained List rows   |            0.401 |        0.303 |            0.3983 |        0.3004 |
| Retained List cursor |            0.548 |        0.525 |            0.5593 |        0.5222 |
| Generated Array rows |            2.572 |        2.537 |            2.6660 |        2.6053 |
| Comprehension rows   |           20.173 |       20.355 |           24.8836 |       24.9186 |
| Indexed Array rows   |            0.290 |        0.292 |            0.2934 |        0.2979 |
| List round trip      |            4.294 |        4.278 |            4.8381 |        4.9273 |
| Reference rows       |            1.290 |        1.258 |            1.3210 |        1.2859 |

Only the retained List-row fixture changed Wasm, from 5,420 to 5,400 bytes. Its
committed guest memory stayed at 1,441,792 bytes. The measured CPU reduction is
about 24%; unchanged fixtures do not establish additional improvements.

`scripts/bench_runtime_costs.ts` also passed all 13 workloads with each
executable (1,000 warmups, 31 samples of 16 calls). Both compilers emitted the
same module, SHA-256
`a64ee782e4dbc0702495d587206aa55f1ff7995ae83026a787e222601b5a421c`. Requested
compiler allocation was 8,905,356 bytes, peak requested memory was 2,155,291
bytes and teardown live bytes were zero for both. Guest memory matched per
workload. Timing variation for this identical module is not a speedup.

### Compiler measurements and decision

Seven alternating pairs used the frozen 394,294-byte gdev workload. The first
batch enabled an isolated restart cache; a separate batch disabled persistence
for ordinary fresh compilation. Every cross-compiler and same-compiler
fresh/retained/restart Wasm comparison passed without disabling byte checks.

| Measurement                           |           Packed baseline CPU, ms | Span CPU, ms |
| ------------------------------------- | --------------------------------: | -----------: |
| Fresh, persistence disabled           |                               938 |          940 |
| Retained population                   |                             1,070 |        1,070 |
| First retained literal edit           |                               240 |          240 |
| Subsequent edit/revert                |                               220 |          220 |
| No-op                                 | Below 10-ms accounting resolution |           10 |
| Cold cache population, separate batch |                             1,051 |        1,048 |
| Process restart, separate batch       |                               657 |          645 |

With persistence disabled, both requested 321,239,456 bytes cumulatively and
peaked at 78,947,905 requested live bytes. Both had 2,036 inference regions,
8,041 scopes in the largest region, 35,215 constraint visits and 42,410 occurs
visits. Cold cache population requested 386,068,597 bytes and peaked at
125,685,698 bytes in the baseline; cache serialization is additional work, not
ordinary fresh compilation.

Host load was 31–46 on 16 CPUs during the restart batch and 52–34 during the
no-cache batch. These absolute timings cannot replace the earlier qualified
647-ms baseline. No compiler speedup is claimed. Raw records are in `compile/`
and `compile-no-cache/` beneath the qualification directory.

Decision: merge the bounded direct-loop span change. The production release,
native suite, all 590 guest/client tests and zero-finding analyzer gate passed.
The changed guide module and packed-row fixture execute correctly; all other
qualified differential and gdev outputs preserve their required byte equality.
The prototype and its baselines remain available for comparison.

The full read-only List regression remains open. This experiment improves one
three-field fixture against the packed baseline and leaves cursor emission
unchanged. Closing the regression requires paired measurements against the
preserved boxed compiler over every supported row width, with boundary,
snapshot, nested-loop and cursor coverage. Neither this result nor the older
1.9× fold / 1.5× cursor measurements prove that broader gate has passed.

## Sequential leaves and private row views

This follow-on implementation is under qualification. Task 002 remains open
until its full release, ownership, differential and all-width performance checks
pass. The pre-change production binary is preserved at
`build/bench/list-field-qualified/pre-walk-blotc`, SHA-256
`034d660ce38691df9a18c895ab228c4d0a76d618aa1969117d16604e06ee2833`.

The initial all-width comparison confirmed that the span check alone left a
substantial gap. Two independent costs mattered: copying every field through
temporary row aliases, and restarting a tree lookup at each packed leaf. Wider
rows visit more leaves for the same number of logical elements. A diagnostic
large-leaf experiment supported that diagnosis; it was discarded. Production
keeps the existing 248-word leaf limit and persistent-edit layout.

`list_traversal.zig` emits a private traversal with at most 64 pending right
subtrees. A separate word roots the original List for the entire traversal. The
storage is cleared before initialization and owns only allocation-base
references. Advancing pops a pending subtree and descends its left edge, saving
right children. Each request advances to the immediately next leaf because the
caller consumes every intervening field. Stack-position locals advance by word
addresses, while stored references remain allocation bases. Each tree edge is
visited once. Nested traversals have independent progress and do not consult or
overwrite each other's state.

`row_projection_uses.zig` admits a whole-row binding only when every use is a
direct projection of a checked scalar field. Its bounded walk rejects aliases,
whole-row captures, implicit carries and unsupported forms. Flat tuple patterns
can bind their scalar fields directly, including values later captured or
returned. All other rows keep their owning representation.

Admitted rows use a private view into a leaf. The view never becomes a source
value. A row crossing a leaf boundary is copied, without numeric conversion,
into a lazily allocated scalar buffer of at most 64 bytes. This buffer is reused
only after the previous row's last possible use. An inner loop handles rows
known to fit in the current leaf; the outer loop performs boundary work and
recovers the next logical row index. The leaf bound also proves the inner loop
cannot pass the List's final row. Direct field loads use checked constant
offsets. A bounded decision tree selects constant copy sizes for crossing
fragments, allowing the host to inline these small copies.

Both private allocations are scoped to one dynamic traversal. Empty traversals
allocate neither. Normal exits, breaks, returns and cancellation release only
allocated storage. The original collection root remains live until those
releases. No interior address enters a collection, closure, demand, cursor or
host value.

Scalar replacement separately computes the fields demanded by each snapshot,
propagating demand backwards through copy edges to a fixed point. This reduces
unused scalar slots and transfers without merging lexical versions. Copy sources
are read before destination writes; unused store operands still execute in
order. A new native law checks selective copies, immutable inputs and every
allocation-failure point. `wasm_sroa.zig` is now explicitly imported by the test
root, so focused filters execute its laws rather than only suite-discovery
tests.

Prototype results, which precede the final explicit collection root, are in
`build/bench/list-field-qualified/`. They validate the direction but do not
qualify the final binary. Five added executed-Wasm laws cover all row widths,
tuple bindings, old-row snapshots, raw floating-point bits, live fields across
nested collection, synchronous/JSPI resumption, request cancellation through
break/return, host exceptions and subsequent recovery. Existing packed-row,
iterator, revision and effect laws remain required. Release measurements must
include both modes of `scripts/bench_list_traversal.ts`, the original packed-row
benchmark, compiler allocation/retained edits, and runtime memory.

The cursor path still uses its existing immutable cursor and cached lookup. Its
remaining cost is a separate required gate in task 047; direct-loop results do
not establish cursor performance. The tracing baseline also has a pre-existing
nested-loop retention limit: with 90 outer rows, increasing each inner loop from
8 to 200 discarded 8,192-word arrays grew committed memory from 43,515,904 to
942,211,072 bytes in both the baseline and prototype. Task 035 must cover this
case while preserving live outer values. The new regression law uses a fixed
repeated workload to check that row views remain live and private traversal
storage is reusable; it does not claim that tracing limit is resolved.

### Sequential implementation qualification

The intermediate implementation is committed as `bcff12b`. Its behavior and
ownership gates pass; the all-width performance gate remains open.

The production candidate is pinned at
`build/bench/list-sequential-qualified/blotc`, SHA-256
`742c3e91faf3dd682d33873d8d02da13eefa0f252c62da570c3fb3b0bc068053`. Its compiler
identity is `335693d2f998b635913318c2b72e5092b4a7a3b3ce52b1989ba93e461ff684cd`.
The directory's `manifest.json` records the source and harness hashes, both
baselines and measurement commands. Later memory instrumentation has its own
entry; it does not replace the historical scalar-only harness hash.

Zig 0.17.0's full native suite and all 595 guest/client tests passed. The
analyzer checked 287 Zig files with zero findings. The 305-case differential
made 610 invocations with identical success, ordered diagnostics, semantic
counters and teardown ownership. All 488 successful Wasm files validate. Fifty
intentional Wasm changes reflect the traversal and scalar-replacement lowering;
both guide modules return 45, 26 and 5 for the previously qualified calls. Gate
logs are `build/bench/list-leaf-qualified/compiler-gate-final.log` and
`analyzer-final.log`; older interrupted logs are not passing evidence.

Seven alternating gdev pairs retain strict same-compiler fresh, retained and
restart byte equality. Intentional cross-compiler changes use the separately
qualified `--allow-wasm-diff` option. The following are process CPU medians,
with ordinary fresh compilation measured without a persistent cache.

| Measurement                           | Task 001 CPU, ms | Sequential CPU, ms |
| ------------------------------------- | ---------------: | -----------------: |
| Fresh, persistence disabled           |              981 |                973 |
| Retained population                   |            1,110 |              1,110 |
| First retained literal edit           |              260 |                250 |
| Subsequent edit/revert                |              230 |                230 |
| No-op                                 |         Below 10 |           Below 10 |
| Cold cache population, separate batch |            1,064 |              1,054 |
| Process restart, separate batch       |              647 |                659 |

Fresh requested allocation changes from 321,239,456 to 321,026,930 bytes; peak
requested live memory changes from 78,947,905 to 78,908,053 bytes. Semantic work
counters remain 2,036 regions, 40,387 scopes, 8,041 scopes in the largest
region, 35,215 constraint visits and 42,410 occurs visits. The small allocation
decrease does not establish the final compiler-allocation target. Host load was
108→104 on 16 CPUs during the no-cache batch and 104→133 during the restart
batch; these absolute timings do not replace the qualified starting baseline.

The original packed-row harness measured the retained List fold at 0.291→0.106
ms CPU against task 001, with unchanged committed memory of 1,441,792 bytes. The
cursor measured 0.613→0.630 ms. All 13 general runtime workloads retained their
previous committed memory. The explicit cursor still uses persistent progress,
cached lookup and owned row extraction. It does not inherit a direct loop's
private sequential traversal; the cursor cost remains required work.

### All-width boxed comparison

`scripts/bench_list_traversal.ts` uses 16,384 retained rows, 20 warmups and 31
alternating paired samples, with 128 traversals per sample. An otherwise unused
aggregate entry exposes the arena to the guest API; both variants use the same
entry and reset behavior. The harness rejects an unavailable arena. Earlier
scalar-only reports remain in `boxed-record/` and `boxed-tuple/`, but their zero
memory fields are unavailable measurements. Corrected reports are in
`boxed-record-memory/` and `boxed-tuple-memory/`.

CPU entries below are candidate/boxed ratios of process-CPU medians. Memory
entries are committed KiB after folds and match between the two row shapes. They
include constants and runtime storage, rather than only the traversal buffer.
Cursor runs can commit another 64 KiB at widths 9 and 10.

| Width | Record fold | Tuple fold | Record cursor | Tuple cursor | Boxed KiB | Packed KiB |
| ----- | ----------: | ---------: | ------------: | -----------: | --------: | ---------: |
| 1     |       0.275 |          — |         1.167 |            — |       704 |        192 |
| 2     |       0.368 |      0.348 |         1.369 |        1.378 |       704 |        256 |
| 3     |       0.474 |      0.432 |         1.664 |        1.442 |       704 |        320 |
| 4     |       0.504 |      0.483 |         1.434 |        1.326 |       704 |        384 |
| 5     |       0.615 |      0.658 |         1.670 |        1.369 |     1,216 |        448 |
| 6     |       0.796 |      0.689 |         1.880 |        1.426 |     1,216 |        512 |
| 7     |       0.852 |      0.758 |         1.820 |        1.663 |     1,216 |        576 |
| 8     |       0.797 |      0.734 |         1.653 |        1.363 |     1,216 |        640 |
| 9     |       0.908 |      0.854 |         2.074 |        1.636 |     1,216 |        704 |
| 10    |       0.935 |      0.829 |         2.053 |        1.748 |     1,216 |        768 |
| 11    |       0.935 |      0.866 |         1.994 |        1.716 |     1,216 |        896 |
| 12    |       0.970 |      0.854 |         1.996 |        1.562 |     1,216 |        960 |
| 13    |       0.989 |      0.989 |         1.984 |        1.640 |     2,240 |      1,024 |
| 14    |       1.021 |      0.907 |         2.076 |        1.723 |     2,240 |      1,088 |
| 15    |       1.016 |      0.950 |         2.135 |        1.765 |     2,240 |      1,152 |
| 16    |       1.044 |      0.917 |         1.935 |        1.554 |     2,240 |      1,216 |

The record fold remains above the boxed baseline at widths 14–16. The tuple fold
medians improve at every width, but the width-13 margin is small. This does not
close the all-width fold requirement. Every cursor remains slower and is tracked
by task 047. No storage fallback was introduced to hide a regression.
Correctness, ownership and the large improvement in the original packed fold
justify preserving this intermediate implementation; they do not justify marking
task 002 complete.

Host load was 127.08→121.74 for records and 121.74→86.40 for tuples on 16 CPUs.
The outer runner records these values in the manifest; the restricted Deno
process could not read `/proc/loadavg` and explicitly records `null`. Process
CPU and paired order reduce scheduling noise but do not establish idle-machine
timing or a speedup for near-equal cases.

### Rejected follow-on experiments

The following probes used separate source copies and were not merged. Their five
focused row-view and effect execution tests passed; none establishes the full
compiler or all-width qualification gate.

- Replacing exact short copies with overlapping power-of-two prefix/suffix
  copies made widths 12–16 1.3–4.5% slower than the committed implementation.
  Source, binary and samples are preserved in
  `build/bench/list-crossing-prototype/`.
- Copying a crossing row's first fragment directly before walking later leaves
  produced median ratios of 0.987, 0.980, 0.962, 1.014 and 1.002 at widths
  12–16. Paired distributions overlapped substantially. This does not resolve
  the wide-row gate; the probe remains isolated in
  `build/bench/list-crossing-first-fragment-prototype/`.
- Grouping adjacent fields into 128-bit loads and extracting scalar lanes made
  widths 12–16 9.4–37.6% slower. The result is rejected; records are in
  `build/bench/list-vector-loads-built-prototype/`. An earlier run started after
  a failed build and is explicitly invalidated in
  `build/bench/list-vector-loads-prototype/`; it is not evidence for this
  change.
- An input-only probe balanced the U32 sum without changing the compiler. Ratios
  of 0.975–1.028 against the original expression showed no consistent
  improvement. Its changed input is not the task's acceptance workload.

- Computing field addresses explicitly and using zero load offsets produced
  ratios of 0.991, 1.032, 0.993, 0.991 and 0.996 at widths 12–16. This also
  fails to establish a reliable improvement. The source and samples remain in
  `build/bench/list-zero-offset-loads-prototype/`.

V8's generated graphs for the committed compiler show one bounds check per
scalar field in the wide fold and a 4,828-byte optimized body, versus 1,560
bytes for the boxed compiler. These observations motivate further investigation;
the rejected probes do not prove that bounds checks alone cause the remaining
gap. The graphs and input-only probe are preserved beneath
`build/bench/list-sequential-qualified/` and
`build/bench/list-balanced-input-probe/` respectively.

### Contiguous wrapping-sum candidate, 9 October 2026

A later serialized-leaf alignment probe still measured record fold ratios of
1.025 and 1.010 at widths 14 and 15. It did not close the regression and remains
unlanded in `build/bench/list-aligned-leaf/`.

The current independent candidate keeps the original List layout. It recognizes
a straight-line wrapping U32 sum over 8–16 distinct, adjacent four-byte fields
of one base address. Every discarded temporary has exactly one definition and
one use in the entire function. It combines exact four-word loads, adds their
integer lanes and extracts four final lanes, retaining scalar tail fields. It
never widens the accessed byte range or reassociates floating-point addition.
The match is structural and names no source function or collection operation.

The pass runs after ownership lowering. That ordering preserves scalar pointer
provenance while lifetimes are decided; inserted cleanup calls prevent a match
across a release. Calls, control flow, noncontiguous fields, repeated fields,
observed temporaries and other operators also prevent the transformation. Moving
it ahead of ownership lowering would erase information needed by the lifetime
analysis and is not the intended implementation.

The development candidate is SHA-256
`5515c093f2d516f581de778d045175412b90255aed2f90274208a280d13a135c`, pinned in
`build/bench/list-row-reduce-after-lifetimes/`. All 16 U32 record widths and 15
U32 tuple widths beat the preserved boxed fold baseline in that batch. Record
widths 14/15/16 measured 0.578/0.641/0.518 times boxed CPU; tuple widths
13/14/15/16 measured 0.940/0.923/0.964/0.913. Explicit cursors remain slower.
These loaded-host development measurements are not the final release gate.

Three native laws pass, including exhaustive allocation failures, exact byte
coverage for every admitted width and conservative rejection cases. The native
filter reports 18 passing tests including discovery checks. Thirteen existing
row, snapshot, cursor and effect execution laws pass. Two new execution laws
cover U32 overflow, scalar tails, empty input, bounds-failure recovery and
order-sensitive F32 sums. A 305-case corpus comparison (610 invocations, 244
successful cases) has no semantic, diagnostic or Wasm differences. Its ordinary
fixtures do not establish performance for the new wide-row kernel.

The traversal harness also accepts an optional final `u32` or `f32` argument.
F32 workloads convert each row index to binary32 and compare against a scalar,
source-ordered `Math.fround` reference. This preserves the original default U32
workloads and exposes floating-point behavior rather than inferring it from
integer timings.

The F32 record and tuple batch passed its value checks but exposed a remaining
regression: wider record folds measured roughly 1.03–1.06 times boxed CPU, and
wider tuple folds roughly 1.03–1.06. Reports are in `f32-record/` and
`f32-tuple/` beneath `build/bench/list-row-reduce-after-lifetimes/`. A separate
probe groups loads while retaining the original scalar F32 addition order; its
qualification is still pending.

The U32 candidate's release is SHA-256
`2546adaf4041999a8f7ef5221ec92cb4b5e9998123059d7a44eae680974d1aad`, pinned in
`build/bench/list-row-reduce-release/`. Its fifteen focused execution laws pass.
Seven no-cache compiler pairs measure 948/963 ms fresh CPU, 1,120/1,120 ms
population, 250/240 ms first edit and 220/230 ms subsequent edit,
baseline/candidate. Seven restart pairs measure 1,035/1,032 ms cold population,
635/641 ms process restart, 1,090/1,090 ms retained population, 250/240 ms first
edit and 220/220 ms subsequent edit. No-op CPU is below 10-ms accounting
resolution. All Wasm comparisons pass, including cross-compiler comparisons; the
intentional-change permission was not needed by this workload. These loaded-host
measurements establish no compiler speedup.

The order-preserving F32 load probe is SHA-256
`386f9e2cf66349e521b4bcba3bb58e1e620c8dac469a4bc15642a98f1b292059`, in
`build/bench/list-float-loads/`. Nineteen focused native checks and the analyzer
pass. Execution checks cover all widths of Arrays and Lists, alternate field
orders, cancellation, subnormals, empty inputs, leaf crossings and failure
recovery. The first execution invocation lacked the private checkout's `build/`
directory; only the corrected and expanded execution logs are passing evidence.

Its generated record loops contain the grouped loads; tuple loop bytes are
unchanged. The F32 batch still measures roughly 1.02–1.06 times boxed CPU at
many wider widths. This additional transformation is not accepted for landing.
The widths with crossing rows motivate a separate whole-row static leaf probe;
that probe remains unqualified. The source is isolated in
`/tmp/blot-row-reduction-only-prototype/`; none of these partial results
complete task 002 or the broader SIMD task.
