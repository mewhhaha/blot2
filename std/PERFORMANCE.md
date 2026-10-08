# Standard library API and performance audit

## Semantic compilation performance

This batch follows `8b44ee6` and uses the same frozen gdev workload as the
packed-row checkpoint. Every optimization follows source, type, effect and
ownership evidence; none recognizes prelude names.

| Approved track | Implemented boundary | Remaining work |
| --- | --- | --- |
| Smaller inference regions | Opt-in independent checking of closed first-order calls, with recursive guards and ordinary fallback | Higher-order and recursive-component summaries |
| Specialization deduplication | Session-local index of complete refinement answers in fresh CLI and retained builds | Reusable principal schemes for arbitrary caller-independent bodies |
| Immutable semantic sharing | Closed source type graphs share imports within one region; variables remain scoped | Broader sharing across region owners |
| Semantic early cutoff | Unchanged caller type answers can survive a changed runtime callee after its exact closed judgment is freshly established | Stable identities for arbitrary structural edits |
| Transactional revision metadata | Published certificates retain successful dependency validation with exact source stamps and foreign bounds | Full metadata deltas and changed-only graph updates |
| Constant/data retention | Completed scalar constants no longer prevent enclosing code-fragment reuse; current values and types must match | Reusing aggregate evaluation and serialized data |
| Portable semantic artifacts | Explicit backend checkpoints include eligible nonempty principal type/row results with complete dynamic inputs | Arbitrary specialization and evaluation persistence |
| Resolved backend IR | Opt-in scalar SSA includes structured branches and joins with selected-arm trap behavior | Calls, loops and heap ownership |
| Relocatable optimized bodies | Bounded exact call-graph matching reuses owned optimized output across changed direct-call indices | Broader layout-independent fragment identities |
| Parallel semantic work | Opt-in independent call judgments use private Sessions/solvers and deterministic publication order | Measured adaptive scheduling of general semantic jobs |

Local refinement reuse owns its receipts even when a fresh CLI build is not
recording backend artifacts. Keys include the root, expected shape, type/row
seeds, evaluation options, depth and observed dynamic facts. Only complete
answers without evaluation or value publication qualify. Results are copied
into caller-owned storage; failed allocation cannot publish a partial answer.
Closed source sharing never merges independently scoped variables, and rollback,
physical mutation or changed depth limits revoke imported answers.

Across revisions, receipts distinguish collected source bodies from consumed
closed-call judgments. An unchanged caller can keep its type answer after a
callee's runtime body changes when that judgment has already been established
in the new Session. Executable and staged-value dependencies still rebuild.
Dependency-validation certificates similarly prove only validation, not semantic
or executable reuse. They belong to the successful candidate snapshot and do
not mutate the preceding revision on failure.

Portable nonempty results validate source/effect variables and reject duplicates
before importing closed evidence into the new owner. The archive still requires
an exact ordered Core/catalog/namespace image, including literal bits, followed
by dynamic-input validation. Unsupported providers or generative identities
decline. Optimized-body relocation separately checks the complete direct-call
graph, signatures, globals, imports and lifetime summaries; it rewrites an owned
output copy and preserves retained input bytes.

Inference partitions and semantic workers remain opt-in.
The partition experiment accepts 963 of 968 attempted gdev boundaries, reducing
the largest diagnostic region from 13,863 to 10,335 scopes. Its fresh-session
pairs improve by roughly 11–14%, but retained-edit samples show no clear win.
These diagnostic runs are not cold CLI measurements and do not justify changing
the default. Ordinary source inference remains the fallback. Worker tests compare
one, two and four workers for deterministic results, with allocation-failure
injection on the serial path. A whole-project speedup is not established.

Five alternating fresh-process pairs and five retained-session pairs compare
the default path with the frozen compiler at `8b44ee6`, on the same 53-file,
394,294-byte gdev snapshot. The edit changes `robots.blot`'s floor extent from
60.0 to 61.0, then reverts and repeats a no-op. Retained population excludes
opening the session; fresh CLI includes launching the monitor/compiler, output
writing and teardown. No builds, tests or lint from this task ran during timing.
Filesystem caches and other host activity were uncontrolled.

| Median measurement | Previous checkpoint | Candidate |
| --- | ---: | ---: |
| Fresh native CPU | 1,195.71 ms | 1,182.08 ms |
| Retained population CPU | 1,520 ms | 1,470 ms |
| First edit CPU | 350 ms | 310 ms |
| Revert CPU | 330 ms | 290 ms |
| Fresh CLI wall | 19,275.44 ms | 9,543.01 ms |
| Retained population wall | 24,407.33 ms | 25,934.10 ms |
| First edit wall | 3,723.67 ms | 3,534.58 ms |
| Revert wall | 2,805.44 ms | 2,147.56 ms |
| No-op wall | 56.50 ms | 30.75 ms |
| Fresh requested allocation bytes | 433,590,389 | 425,441,209 |
| Fresh allocation calls | 1,457,497 | 1,405,703 |
| Peak requested live bytes | 58,404,972 | 57,907,712 |
| Fresh peak RSS | 75,684 KiB | 76,424 KiB |
| Retained peak RSS after revert | 160,744 KiB | 157,984 KiB |

The host was severely contended. Fresh CLI ranges were 6.95–23.94 seconds before
and 3.44–19.80 seconds after; retained population ranged from 1.96 to 36.16
seconds across both compilers, and even no-op wall time reached 1.49 seconds.
The apparent halving of cold wall time is **not an established latency gain**.
Keep the CPU/work comparison separate: cold CPU is nearly unchanged, while
median first-edit and revert CPU fall about 11% and 12%. Retained CPU uses
10 ms process ticks; a zero no-op reading means below that measurement's
resolution. These results do not establish the 500 ms cold / 100 ms edit goals.

Structural work falls more than total CPU. Population executes 8,539 → 1,490
refinement regions; a first edit emits 432 → 282 fresh named/closure bodies,
reuses 691 → 841 bodies, and replays 289 completed scalar constant jobs. Source
graph sharing reuses 150,772 imports during population. Fresh allocation traffic
falls 1.9%, peak requested live bytes less than 1%, and tracked live storage
after teardown remains zero. The large cold inference region is still present:
the diagnostic profile records 13,863 scopes and 267,068 nodes for gdev's
`sandbox` construction. Its wall timings also include contention, so they are
not isolated CPU costs. Higher-order body summaries remain the main open
architectural work.

Every original/candidate output matches exactly, including fresh compilation
of the edited source; all Wasm validates. Both produce 629,339-byte modules.
Original/revert output SHA-256 is
`ae2714abc40f1cea82105c252c10bb198f9611b9e3781267a89dbca00905981b`;
edited output is
`75ae524926a3e53b97e044464e2a01818362374c3a14a825a38dbd3a2d9d2fa3`.

The release build and 1,095 native tests pass. All **548 guest/client tests**
pass across the full run and focused retries. The full run initially reported
541 passes and seven environmental failures: standalone packaging exhausted
`/tmp`, and six artificial peers exceeded their existing two-second startup
deadline. The standalone retry and all 35 transport tests pass without source
changes. Zig-analyzer reports the same 120 warnings, no errors, across 285
files. Zig formatting, the new TypeScript test's formatting/type check and
`git diff --check` pass.

Raw samples and distributions are in
`build/compiler-hills/qualified-semantic/gdev/{samples.jsonl,summary.json}`;
the driver is `build/compiler-hills/paired-semantic.ts` (`deno run --allow-all`
is required for its own child-process `/proc` metrics). Retained runs resumed
after three complete pairs following an interrupted command; completed samples
were preserved. The diagnostic profile is `qualified-semantic-profile.jsonl`.
Build/test/lint logs and the qualification details are recorded in
`build/compiler-hills/semantic-final/manifest.json`. The pinned binary SHA-256 is
`f2df77df9757a8fff122a7fb6493edca940a517b111ffdebc6f6f8a470d5c3ed`.
These changes are not installed locally. The ten implementations above are
bounded progress, not completion of every architectural endpoint in the plan.

## Production packed scalar rows

The 2026-10-08 transfer makes flat tuples and structural records of 1–16 checked
scalar fields consecutive payload words in both Lists and Arrays. Construction,
constants, updates, structural copies, cursors and conversions share this rule.
Source lengths still count rows; List tree ranges count words. Extracted values
own their storage, and nested/reference-bearing/nominal/erased/wide rows keep
boxed storage. Distinct List/Array APIs are preserved.

Direct field reads and ordinary scalar replacement remove temporary boxes.
Plain loop bindings no longer hide definitions inside unnecessary failure
blocks. A general bounded inlining pass exposes straight-line allocation
producers to scalar replacement, with complete callee dependencies for reuse.
Packed cursors and direct loops keep leaf spans; crossing rows use checked word
lookups. None of these optimizations recognize prelude names.

The comparison is against the preceding compiler-performance checkpoint in
`build/compiler-hills/final/`, not the original compiler at `586e0ae`.
`scripts/bench_packed_rows.ts` compiles eight ordinary programs with both
compilers and runs ten warmups plus 25 alternating runtime pairs. All results
are checked. Guest calls return scalars; `memoryBytes()` reports linear-memory
page high-water, not exact live heap bytes. Host contention affected wall time,
so this table reports median process CPU during each call; raw wall samples are
also retained. No builds, tests or lint from this task ran during benchmarks.

| 100,000-row fixture | CPU before → after | Wasm page high-water before → after |
| --- | ---: | ---: |
| Retained Array fold | 0.137 → 0.148 ms | 3.625 → 2.062 MiB |
| Retained List fold | 0.218 → 0.420 ms | 3.562 → 1.375 MiB |
| Retained List cursor | 0.428 → 0.653 ms | 3.562 → 1.375 MiB |
| Generate + generic fold | 16.622 → 2.604 ms | 5.000 → 2.875 MiB |
| Comprehension + generic fold | 23.768 → 20.896 ms | 6.750 → 6.812 MiB |
| Generate + indexed fold | 0.772 → 0.267 ms | 3.625 → 2.062 MiB |
| Array/List round trip + fold | 18.356 → 4.622 ms | 6.250 → 4.000 MiB |
| Reference-row fallback | 1.640 → 1.671 ms | 6.688 → 6.688 MiB |

Generation/folding uses about 6.4× less CPU, indexed construction about 2.9× less,
and the conversion fixture about 4.0× less. Retained packed List storage falls
61%, and packed Array storage 43%. These are fixture results, not whole-program
speedups. Read-only List folds use about 1.9× as much CPU and cursors 1.5×;
retained Array reads are also slightly slower. The comprehension fixture uses
one additional Wasm page. Closing those traversal costs and eliminating generic
iterator step/cursor allocations remain open. This is not a universal runtime
performance improvement.

Five alternating fresh-process pairs and five retained sessions per compiler
use the same 53-file, 394,294-byte frozen gdev snapshot. Retained edits change
`robots.blot`'s floor extent, then revert and repeat a no-op. Session population
is measured separately and excludes opening the session. Fresh wall time
includes the Python process monitor, compiler launch, output writing and
teardown; retained time includes the client round trip and byte delivery.
Wasm validation and hashing follow the measured interval. Filesystem caches and
other host activity are uncontrolled.

| Compiler measurement | Previous checkpoint | Packed-row candidate |
| --- | ---: | ---: |
| Fresh CLI wall median | 1,466.04 ms | 1,605.73 ms |
| Fresh native CPU median | 1,192.85 ms | 1,220.94 ms |
| Retained population | 1,800.74 ms | 1,770.88 ms |
| First edit | 388.51 ms | 398.75 ms |
| Subsequent edit/revert | 353.27 ms | 370.38 ms |
| No-op | 6.44 ms | 6.46 ms |
| Fresh peak RSS median | 76,308 KiB | 75,752 KiB |
| Retained peak RSS median | 162,216 KiB | 161,372 KiB |
| Fresh requested allocation bytes | 433,294,622 | 433,590,389 |

There is no compiler-latency win: cold CPU increases about 2.4%, cold wall about
9.5%, and measured edits also slow slightly. Peak requested live bytes remain
58,404,972, and tracked live bytes after teardown remain zero. The 500 ms cold /
100 ms edit targets are unmet. Each compiler's retained outputs exactly match
its own fresh results, including the edited source; all Wasm validates. Output
changes from 629,240 to 629,339 bytes because representation/emission changes.

`deno task test:compiler` passes the native suite and **546 guest/client tests**.
Focused laws cover source evaluation/trap order, raw F32 bits, snapshots, leaf
crossings, escaped values under collection, allocation failures, changed layout
and callback dependencies, failed revisions and fresh/retained parity.
Zig-analyzer checks 280 files with 120 existing warnings and no errors. Formatting,
TypeScript checks and `git diff --check` pass.

Raw runtime samples are in
`build/compiler-hills/qualified-packed-rows/runtime-qualified/report.json`;
gdev samples and summary are in `qualified-packed-rows/gdev/`, driven by
`build/compiler-hills/paired-packed-rows.ts`. The successful full gate is
`build/compiler-hills/packed-rows-qualified-gate-2.log`. Binary, compiler identity
and qualification manifest are frozen in `build/compiler-hills/packed-rows-final/`.
The binary SHA-256 is
`453a09fc9a73f24785e059ba90685974468e241044eecd6c7270e689b623de38`.
These changes are not installed locally. The manifest records their state at
measurement time, before the source checkpoint commit.

The next work is reducing packed traversal overhead and broader typed row
fusion/SIMD, followed by ragged builders, rolling reductions and composable
summaries. Query rewrites, caches and worker facilities remain separate measured
follow-ups.

## Compiler performance program: final default-path check

The final combined default path was compared with the frozen compiler at
`586e0ae` using five alternating pairs on the same 53-file, 394,294-byte gdev
snapshot. No builds, tests or lint jobs from this task ran during measurement;
other host activity remained uncontrolled. The original/candidate comparison
within this run is valid; absolute times should not be compared across batches.

| Median | Original | Final candidate |
| --- | ---: | ---: |
| Fresh CLI wall, including monitor launch | 1,353.99 ms | 1,294.01 ms |
| Fresh native process wall | 1,324.94 ms | 1,264.80 ms |
| Retained population | 1,909.19 ms | 1,797.57 ms |
| First edit | 983.77 ms | 377.54 ms |
| Subsequent edit/revert | 982.47 ms | 375.60 ms |
| No-op | 6.33 ms | 7.75 ms |
| Fresh peak RSS | 75,536 KiB | 75,388 KiB |
| Retained peak RSS | 159,660 KiB | 161,508 KiB |
| Fresh requested allocation bytes | 503,461,351 | 433,294,622 |
| Fresh allocation calls | 1,584,139 | 1,457,381 |

First and subsequent edits improve about 62%; cold compilation improves about
4%. Allocation traffic falls 14%, while peak tracked live bytes stay at
58,404,972. Peak RSS is essentially unchanged. Every Wasm hash matches the
original, including the changed-source result. The 500 ms cold / 100 ms edit
targets remain unmet. Opt-in tiers, sharing, workers, restart checkpoints and
the private SSA prototype are excluded from this default-path comparison.

The release build, native suite and 539 guest/client tests pass. Lint reports
120 existing warnings and no errors across 279 files. Raw samples and summary
are in `build/compiler-hills/qualified-final/`; the driver is `paired-final.ts`.
The exact binary and qualification manifest are frozen at
`build/compiler-hills/final/`. At measurement time it was not installed or committed.

## Compiler performance program: first batch

The first batch after `586e0ae` retains fully optimized runtime bodies with exact
source/callee/lifetime dependencies, includes captured static values in anonymous
closure identities, memoizes immutable layout roots, shares bounded inference
scratch, and indexes callable definitions once per compilation. Projected
principal receipts replay closed call proofs across primitive literal edits
when the complete structural input and observed semantic inputs match. Ordinary
evaluation still executes changed values and preserves traps. This is a bounded
principal-query optimization, not general body-level incremental checking.

Five alternating pairs compare the frozen original binary against the candidate
on the frozen 53-file, 394,294-byte gdev workload. Retained sessions include
initial cache population, `robots.blot` literal 60.0 → 61.0, revert, and no-op.
No build, test or linter ran concurrently with these measurements.

| Median | Original | Candidate |
| --- | ---: | ---: |
| Fresh CLI wall | 902.16 ms | 902.11 ms |
| Fresh native CPU | 871.76 ms | 864.07 ms |
| Retained population | 992.71 ms | 974.75 ms |
| First edit | 562.36 ms | 241.04 ms |
| Subsequent edit/revert | 543.48 ms | 230.37 ms |
| No-op | 2.85 ms | 2.56 ms |
| Fresh peak RSS | 75,944 KiB | 76,708 KiB |
| Retained peak RSS | 160,708 KiB | 161,988 KiB |
| Fresh requested allocation bytes | 503,461,351 | 437,771,206 |
| Fresh allocation calls | 1,584,139 | 1,476,830 |

Fresh wall time includes launching the Python process monitor, the native
compiler, output writing and teardown. Filesystem caches are uncontrolled;
“fresh” means a new compiler process, not a guaranteed cold disk cache. Retained
time includes the public client round trip and byte delivery, excluding the
additional output hash. The first edit is about 57% faster. Cold latency does not
improve measurably, and both the 500 ms cold / 100 ms edit targets remain unmet.
Allocation traffic falls 13%; peak tracked live bytes remain 58,404,972, so the
allocation reduction must not be described as a 13% reduction in peak memory.

Every original/candidate output hash matches: population/revert/no-op produce
629,240 bytes with SHA-256
`5cc558f49e8121632b9b78a5099fbe6d85b63fcaa15d1acfb4eebe1791476cf7`;
the edited result is
`d37615ab9a2246821abe1eba9a895f41fef4cf3aec7d67de3d1999bdef60b2b5`.
The full compiler gate passes, including 536 guest/client tests. Allocation
failure laws cover retained publication and scratch ownership; executed tests
cover static capture distinctions, changed staged values, errors and recovery.

Local raw artifacts are under `build/compiler-hills/qualified-stage2/`:
`samples.jsonl` and `summary.json`; the harness is
`build/compiler-hills/paired.ts`, and the gate log is
`build/compiler-hills/gate-stage2.log`. The original binary and identity are in
`build/compiler-hills/before/`; the qualified candidate is frozen at
`build/compiler-hills/principal-reuse/blotc`. Detailed profiling is opt-in through
`profileBackend`; its timings are not mixed into the paired measurements.

## Compiler performance program: closed evidence and query imports

The next qualified checkpoint prepares a checked principal graph importer once
per valid owner and shares repeated closed evidence imports within an inference
region. Sharing includes depth and owner/physical-clock validity; it never
merges open solver variables. Rollback, physical mutations, a changed depth
limit and pooled-owner reuse revoke cached answers. Ordinary chronological
substitution semantics remain unchanged.

Five new alternating pairs use the same frozen workload, original compiler,
monitor and edit sequence as the first batch. These are within-run comparisons;
absolute timings from the earlier run are not a valid estimate of the marginal
gain from these additions.

| Median | Original | Candidate |
| --- | ---: | ---: |
| Fresh CLI wall, including monitor launch | 807.49 ms | 773.14 ms |
| Fresh native process wall | 788.91 ms | 754.60 ms |
| Retained population | 906.60 ms | 884.92 ms |
| First edit | 508.21 ms | 183.69 ms |
| Subsequent edit/revert | 500.07 ms | 170.58 ms |
| No-op | 2.62 ms | 2.67 ms |
| Fresh peak RSS | 75,800 KiB | 75,900 KiB |
| Retained peak RSS | 160,348 KiB | 161,388 KiB |
| Fresh requested allocation bytes | 503,461,351 | 433,294,622 |
| Fresh allocation calls | 1,584,139 | 1,457,381 |

Cold compilation improves about 4%; first and subsequent edits improve about
64% and 66%. Allocation traffic falls 14%, while peak tracked live bytes remain
58,404,972. Both latency targets remain unmet. All output hashes remain identical
to those listed above. Native tests, allocation-failure laws and 536 guest/client
tests pass; zig-analyzer reports 120 warnings and no errors across 263 files.

An independent opt-in profile attributes about 567 ms of cold backend work to
inference and only 16 ms to assembly/optimization. The largest principal region
visits 13,863 scopes and creates 295,105 solver nodes. The profiled first edit
replays 1,438 closed call proofs, spends about 59 ms in remaining inference and
6 ms in assembly. These profiles locate work; their instrumented times are not
mixed into the paired distributions.

Raw samples and summary are in `build/compiler-hills/qualified-stage3/`;
the driver is `build/compiler-hills/paired-stage3.ts`. The candidate binary and
identity are frozen in `build/compiler-hills/closed-imports/`. Native, guest,
release and linter logs have the `closed-import` prefix. This report qualifies
the default path, before the later opt-in tier/sharing/parallel prototypes.

## Compiler performance program: tiers, body sharing and workers

The opt-in development tier, exact private machine-body sharing and coarse
optimizer workers pass 1,077 native and 537 guest/client tests. Sharing preserves
logical function/table identities, public function identities, captured values,
traps and fresh/retained parity. Development still performs checking, evaluation
and lifetime cleanup. Worker failures join every job and release its storage;
allocation-failure tests account for schedule-dependent arena growth.

Five rotating/reversed runs compare each option on the frozen gdev workload.
Other applications contended for this machine; no compiler build, test or linter
from this task ran concurrently. Total population medians ranged from 1.58 to
1.80 seconds, with similar process CPU totals. This run does **not** establish an
end-to-end compilation speedup or a default-path regression.

| Option | Cold assembly median | Physical Wasm bodies | Wasm bytes |
| --- | ---: | ---: | ---: |
| Optimized, serial | 30.3 ms | 1,536 | 629,240 |
| Development, serial | 17.4 ms | 1,536 | 605,222 |
| Exact private body sharing | 30.2 ms | 1,264 | 580,188 |
| Two optimizer workers | 24.8 ms | 1,536 | 629,240 |
| Four optimizer workers | 17.7 ms | 1,536 | 629,240 |

Sharing removes 272 duplicate bodies and reduces output size by 7.8%. Parallel
output is byte-identical to serial output; all variants match their respective
fresh rebuilds after edits. Two changed bodies on a retained edit fall below
the parallel threshold. Serial optimized compilation without sharing remains
the default: semantic inference dominates this workload.

Raw samples and summaries are in `build/compiler-hills/qualified-stage4/`,
with driver `options-stage4.ts` and frozen binary/identity in
`build/compiler-hills/optimization-options/`. Final native and guest logs are
`native-stage4-final.log` and `guest-stage4-corrected.log`. The linter reports
120 warnings and no errors across 271 files.

## Compiler performance program: portable backend checkpoints

The explicit `exportCheckpoint()` / `checkpoint` API retains empty-result
principal-query proofs and optimized bodies across compiler process death. It
checks the complete Core/catalog and symbol image, observed semantic inputs,
compiler identity and optimizer dependencies before reuse. Source validation
and compile-time evaluation still execute. Failed edits preserve the last
successful checkpoint; stale and corrupt candidates fall back to fresh work.
The full compiler gate passes, including 538 guest/client tests.

The frozen gdev checkpoint is 3,217,806 bytes. It restores 1,438 closed call proofs
and all 1,536 optimized bodies. Every initial/edit/revert/no-op output matches the
fresh compiler byte-for-byte. Five alternating pairs include checkpoint file
reading, process spawn, open/decode, source checking, compilation and response.
Filesystem caches are warm; Deno launch and process close are excluded.

This machine was heavily contended during the run. Fresh-process wall medians
were 2,987 ms without a checkpoint and 2,482 ms with it, with fresh samples ranging
from 2,569 to 5,485 ms. These absolute numbers cannot be compared with the quieter
773 ms CLI measurements above or used as a target-latency result. Median child
CPU work fell from about 1.44 s to 1.01 s (100 Hz process counters), approximately
30%. CPU totals for subsequent edits were essentially unchanged. Cold peak RSS
was about 107 versus 109 MiB; retained peak RSS was about 154 versus 160 MiB.

Cache creation is visible: the one recorded population took 1,474 ms, and export
plus writing the checkpoint took another 47 ms. Median restart/open time rose
from 3 ms to 170 ms including reading, transfer and decoding. Restoring a
checkpoint saves semantic work after that cost; it does not replace retaining a
live compiler during editing.

Raw samples and summary are in `build/compiler-hills/qualified-checkpoint/`,
with driver `checkpoint-bench.ts`. The qualified binary and identity are frozen
in `build/compiler-hills/backend-checkpoints/`. The gate log is
`checkpoint-gate.log`. Lint checked 274 files with no errors; its additional
owning-optional warning was confirmed as a false positive at the existing
`AlreadyOpen` guard and is documented locally in the following change.

## Compiler performance program: resolved IR and live-patch experiments

The resolved scalar SSA and scalar live-patch experiments were deleted. SSA
admitted two gdev bodies (medians 1,420 ms existing path vs 1,397 ms with the
prototype), which established no whole-compiler win; live patching never reached
the production path and could not patch gdev's heap/effect state.

The final release build, native suite and 539 guest/client tests pass, with 120
existing linter warnings and no errors across 279 files. A combined task was
externally terminated during the native stage (exit 143, no test failure); its
release build completed, and the unchanged native and guest stages passed when
run separately. Final logs are `prototypes-native-final.log`,
`prototypes-guest-final.log` and `prototypes-final-analyzer.log`.

## List transfer batch

The first transfer batch from `../list-like` is implemented through general
compiler proofs. List cursors keep their own leaf position, so forks no longer
overwrite one shared traversal cache. Small scalar collections of up to eight
elements can remain in locals through literal-producing and traversal-only
helpers. Rectangular nested builders allocate their final List or Array once.
Compile-owned function facts memoize bounded cost, behavior, length and borrowing
analysis. None of these optimizations recognizes prelude declaration names.

The proofs preserve eager evaluation order, effects, traps and escaping values.
Unknown calls, aliases, branch/loop merges, pointer elements and unsupported
collection uses retain the ordinary representation. Exact builders accept up to
four independent finite loops and modern spread append; ragged loops, guards,
early exits and intermediate observations fall back. Checked cardinality
overflow runs the original loop rather than introducing an earlier trap.
Function facts are conservative local summaries, not a transitive purity solver.

Ten warmups precede 25 alternating pairs using identical source and prelude:

| Runtime probe | Before ms | After ms | Before guest bytes | After guest bytes |
| --- | ---: | ---: | ---: | ---: |
| Forked cursors, 100,000 elements | 4.990 | 1.825 | 10,551,296 | 10,551,296 |
| Small collection helpers, 100,000 calls | 3.743 | 0.044 | 12,910,592 | 65,536 |
| Rectangular builder, 500 × 500 elements | 10.572 | 0.110 | 3,211,264 | 1,114,112 |

These are fixture-specific runtime gains of about 2.7×, 85× and 96×. The helper
and builder driver checks that the intended optimization actually fired.
Cursor fields still fit the old allocation size class. Opaque cursor values
can still allocate; their private leaf caches account for the first result.

A separate packed-row prototype derives scalar field paths from ordinary type
layouts, with no production collection ABI change. In an executed Wasm fixture,
constructing and reducing 100,000 escaping three-word U32/F32/F32 rows takes
0.672 → 0.158 ms. Heap storage falls 3,724,288 → 2,097,152 bytes, about 44%.
Checks compare every field's raw bits, including F32 signed zero and NaN payloads.
The planner supports nested tuples/structural records; the measured fixture is
flat. Reference-bearing and nominal layouts are rejected. At that checkpoint,
production List and Array values did not use packed rows. Lists retain the
existing AVL tree.

The same frozen gdev workload contains 394,294 source bytes across 53 files.
Five alternating fresh-process pairs with warm filesystem caches and three
retained sessions per variant give these medians:

| Compilation measurement | Before | After |
| --- | ---: | ---: |
| Native process wall time | 1,337.6 ms | 1,323.5 ms |
| Native process CPU | 1,114.5 ms | 1,126.6 ms |
| Peak process RSS | 75,380 KiB | 74,700 KiB |
| First retained edit | 884.1 ms | 829.5 ms |
| Subsequent retained edit | 777.9 ms | 852.8 ms |
| No-op | 4.96 ms | 4.00 ms |
| Wasm size | 620,017 bytes | 629,240 bytes |

Native wall time includes launch, output writing and teardown, excluding the
Python monitor's own startup. Retained measurements include the API round trip.
Every module is validated and first edits are compared byte-for-byte with fresh
compilation. Peak requested compiler storage remains 58,404,972 bytes, with
zero live requested bytes after teardown. Gdev uses six small-collection and
twelve exact-builder optimizations; 9,350 of 9,912 function-fact requests reuse
one of 562 analyses. Checked builder fallback branches add some emitted code.
Mixed edit results and noisy wall times do not establish a compiler speedup.
The 500 ms cold / 100 ms edit targets remain unmet; earlier historical timings
are not paired comparisons with these runs.

The full native compiler suite and **534 guest/client tests** pass, including
effects, exhaustion, escaping snapshots, allocation failures and retained edits
that change helper behavior or introduce then repair errors. Zig-analyzer checks
258 files with 122 existing warnings and no errors. The packaged standalone
produces exactly the same valid gdev Wasm as the measured native compiler and is
installed at `~/.local/bin/blot` for new compiler sessions.

Baseline compiler:
`b0e50d8fd7d98bbb81580fe9be7676047a0d3348edb6490ade55727c6d874007`.
Qualified compiler:
`9b1d10be3fe4b0d7ab8974ed6839807fe8bcf69b36a7b5df583a26c278359164`.
Raw samples, source/binary pins and output hashes are in
`build/list-transfer-review/final-runtime/report.json`,
`build/list-transfer-review/final-compiler/report.json`,
`build/list-transfer-review/packed.json` and
`build/list-transfer-review/qualification.json`. Drivers are
`scripts/bench_list_transfers.ts`, `scripts/bench_iterators.ts` and
`scripts/bench_packed_storage.ts`.

## Compiler architecture cleanup

The seven approved cleanups after `42cb11f` are implemented. A compact typed
stack IR supplies shared opcode, call and allocation contracts to scalar
replacement, SIMD and lifetime analysis. One pipeline owns transformed bodies
and promptly releases superseded buffers. Specialization solves representation
and effect obligations through a semantic service before emitting named bodies.
Fixed guest heap layouts and compiler boundary handles are explicit. Execution
policies and stamping counters belong to sessions/callers; identical semantic
validation inputs share immutable storage through independently released leases.
Executable and value admission still require their own proofs.

Private provider frames, State cells and request frames/cells now have lexical
cleanup obligations. Return, break and cancellation discharge the scopes they
leave; cancelled demands reset to pending. Payload values remain independently
owned. The executed law deliberately uses a raw Wasm Array entry, bypassing both
the host wrapper and generated scalar-entry reset, with no source-loop collector.
After one warmup and **10,000 calls**, the old guest grows from **131,072 to
1,048,576 bytes**; the new guest remains at **131,072 bytes**. A second law keeps
escaping State closures alive across cleanup and later storage reuse.

`deno task test:compiler` passes **1,055 native tests and 528 guest/client tests**,
including cancellation, State/demand cycles, async behavior, allocation failures
and retained/fresh parity. Zig-analyzer checks 253 files with the same 122
existing warnings and no errors. The stack IR is not SSA; dynamic selection still
requests semantic work, and dense Core tables retain raw internal words. This
does not implement general shared RC or eliminate tracing for dynamic cycles.

Baseline compiler:
`67ed843a7e9b2ff4c39de32ae05d25f119172c82b7c0c4c3ad68be275a913e78`.
Qualified compiler:
`b0e50d8fd7d98bbb81580fe9be7676047a0d3348edb6490ade55727c6d874007`.
Both use identical source and retain the same million-element startup List.
Ten warmups precede 25 alternating pairs, timing the public guest call and reset.

| Runtime, 100,000 iterations | Before ms | After ms | Guest bytes, both |
| --- | ---: | ---: | ---: |
| Cursor / take / fold | 6.821 | 6.804 | 5,898,240 |
| Source range / fold | 5.995 | 5.994 | 5,767,168 |
| Straight-line 18-field records | 0.644 | 0.655 | 4,456,448 |
| Records crossing calls and branches | 1.560 | 1.284 | 4,456,448 |
| Two large records sharing a child | 2.414 | 2.426 | 4,456,448 |

On the frozen 394,294-byte gdev workload (53 loaded files), five alternating
fresh-process pairs with warm filesystem caches give these medians:

| Compilation measurement | Before | After |
| --- | ---: | ---: |
| Cold wall time | 807.9 ms | 813.1 ms |
| Process CPU | 784.5 ms | 789.0 ms |
| Peak process RSS | 75,696 KiB | 75,544 KiB |
| First retained edit | 528.1 ms | 518.9 ms |
| Subsequent retained edit | 503.2 ms | 513.3 ms |
| No-op | 2.97 ms | 2.82 ms |
| Wasm size | 619,633 bytes | 620,017 bytes |

Retained measurements use three independent sessions per variant and include
the API round trip. First edits are checked against independent fresh sessions;
every emitted module is validated. Peak requested compiler storage is unchanged
at 58,404,972 bytes, with zero live requested bytes after cold-build teardown.
The small timing differences do not establish a compilation speedup. The
500 ms cold / 100 ms edit targets remain unmet. Historical runs are not paired
comparisons with this experiment.

Raw samples, source manifests, compiler identities and output hashes are in
`build/architecture-cleanup-review/{lifetimes,compiler}/report.json` and
`build/architecture-cleanup-review/private-frames.json`. The runtime/compiler
drivers are `scripts/bench_lifetimes.ts` and `scripts/bench_iterators.ts`; the raw
handler measurement driver and source are saved beside its report.

## Closed shared and cyclic allocation groups

Ownership now follows known pointer fields between private allocations. Shared
children and cycles form one group whose lifetime includes every member's uses;
each exit releases every member exactly once. The generated code needs no
reference counts or graph walk for these groups. The proof uses allocation IDs,
flat arrays and field-offset lookup, with no recognition of source declarations.

Members must be constructed in one straight-line segment. Field loads must have
known dominating stores; escaped parents also escape their reachable children.
Unknown reads/copies, overlapping writes, unproved calls and cross-segment
construction retain the existing reclamation policy. Overlap checking stops
after 262,144 comparisons per analysis and conservatively declines remaining
proofs, bounding compiler work for very wide records. A fresh-result summary
cannot hide an embedded alias to its returned allocation: later shallow copies
must not outlive the object that alias reaches.

The new raw Wasm fixture repeatedly constructs two parents sharing a child,
with a child-to-parent back edge. **No collector runs on this path.** A pressure
allocation between reads catches premature child release. After 100,000 rounds,
the heap ends at 66,560 bytes: the 65,536-byte arena origin plus four reused
256-byte blocks. Additional rounds, a separate sweep and escaped graphs check
free-list integrity and surviving aliases. A source-level law uses three large
records above the scalar-replacement limit and stays within 192 KiB without a
large startup value. Native laws also cover hidden aliases, transitive escapes,
invalid field accesses, exhausted proof budgets and allocation-failure cleanup.

The full compiler gate passes, including **526 guest/client tests** and the
existing State/demand cycle, async and retained/fresh parity laws. Zig-analyzer
reports the same 122 existing warnings, no errors, across 246 files.

Baseline compiler:
`e2a8abda6794a9fd07d692045c09c634d7a57531fccc44297244608d265ef137`.
Qualified compiler:
`67ed843a7e9b2ff4c39de32ae05d25f119172c82b7c0c4c3ad68be275a913e78`.
Both use identical source and retain a million-element startup List. Ten
warmups precede 25 alternating pairs, timing the public guest call and reset.

| Runtime, 100,000 iterations | Before ms | After ms | Before guest bytes | After guest bytes |
| --- | ---: | ---: | ---: | ---: |
| Cursor / take / fold | 6.772 | 6.717 | 5,898,240 | 5,898,240 |
| Source range / fold | 4.240 | 4.228 | 5,767,168 | 5,767,168 |
| Straight-line 18-field records | 0.470 | 0.471 | 4,456,448 | 4,456,448 |
| Records crossing calls and branches | 0.996 | 0.974 | 4,456,448 | 4,456,448 |
| Two large records sharing a child | 1.494 | 1.378 | 17,301,504 | 4,456,448 |

The shared-record case uses about 74% less guest memory, including the unchanged
startup List. This does **not** implement general shared RC or remove tracing
from dynamic State/demand cycles and escaping graphs. Full effect cleanup and
dynamic cyclic ownership remain open.

On the frozen 394 KB gdev snapshot, five alternating fresh-process pairs give
804.6 → 803.4 ms median wall time, 782.5 → 781.8 ms process CPU, and
75,700 → 76,368 KiB median peak RSS. Wasm shrinks 621,971 → 619,633 bytes.
Three retained sessions per variant give first edits 505.5 → 500.5 ms,
subsequent edits 492.0 → 497.7 ms, and no-ops 2.71 → 2.71 ms. These small
differences do not establish a compiler speedup; the 500 ms cold / 100 ms edit
targets remain unmet. Timings from different historical runs are not paired
comparisons. Raw samples, source manifests, compiler identities and output
hashes are in `build/graph-ownership-review/final/{lifetimes,compiler}/report.json`;
the drivers are `scripts/bench_lifetimes.ts` and `scripts/bench_iterators.ts`.

## Control-flow ownership and list editing follow-up

The next ownership stage uses a flat control-flow graph and per-assembly call
summaries. Fixed-offset borrows can cross direct calls; a function returning a
fresh allocation with no other escaping alias transfers that storage to its
caller. Backward liveness inserts releases on branch/loop exits and early-return
paths. It preserves branch-result operands and label depths. Unknown addresses,
multiple assignments, recursive/opaque calls, shared results and arena-reset or
collection barriers remain conservative. Analysis does not mutate retained
instructions or cache source-specific assumptions.

Executed Wasm fixtures contain **no collector calls** on their measured paths.
Ten thousand rounds of both arms, early returns, result-carrying branches and
loop borrows use one 256-byte allocation block. Factories and readers each
forward ownership/borrows through two calls. Negative laws cover global escapes,
returned aliases, oversized accesses, conditional definitions, recursive calls
and invalidating callees; allocation-failure tests cover scratch/output cleanup.
The full compiler gate passes with 524 guest/client tests, including real
State/demand cycles, async host exchange and retained/fresh byte parity. The
analyzer reports the same 122 existing warnings and no errors across 246 files.

Compared with the preceding compiler
`1d4b45a32af29a836f2355d806a52b8bdf6e345aa7eb9daf684ee188398ba783`,
the qualified compiler is
`e2a8abda6794a9fd07d692045c09c634d7a57531fccc44297244608d265ef137`.
Both run identical source and retain the same million-element startup List.
Ten warmups precede 25 alternating pairs; the public guest call/reset is timed.

| Runtime, 100,000 iterations | Before ms | After ms | Before guest bytes | After guest bytes |
| --- | ---: | ---: | ---: | ---: |
| Cursor / take / fold | 12.835 | 11.632 | 6,160,384 | 5,898,240 |
| Source range / fold | 7.731 | 7.204 | 6,160,384 | 5,767,168 |
| Straight-line 18-field records | 1.106 | 1.104 | 4,456,448 | 4,456,448 |
| Records crossing calls and branches | 1.831 | 1.907 | 17,301,504 | 4,456,448 |

The last case trades about 4% runtime for bounded storage. Without the large
startup List, the corresponding source law stays within 192 KiB. Tracing is
**still present** for shared/unproved graphs. This does not implement shared RC,
general effect-frame cleanup or cycle reclamation without tracing.

On the frozen 394 KB gdev snapshot, fresh-process medians are 934.3 → 939.2 ms;
process CPU is 909.9 → 914.0 ms and peak RSS 75,552 → 75,704 KiB. Wasm grows
615,349 → 621,971 bytes. The first retained-session experiment experienced a
large timing shift in both variants, so its separate medians are not evidence
of an edit speedup. A confirming run interleaves nine edit/revert pairs between
two populated sessions: 575.3 → 577.4 ms median, with overlapping 567–590 and
570–591 ms ranges. The 500 ms cold / 100 ms edit targets remain unmet.
Raw samples are in `build/cfg-ownership-review/{lifetimes,compiler}/report.json`
and `build/cfg-ownership-review/paired-edits.json`; the latter has its executable
measurement driver beside it.

The updated untracked `../list-like/LIST.md` has SHA-256
`42ea4ca23c7fdd9d7270689cf5003c0c6b64dfc280ed4a4279f12440a391cf78`.
Its new `bench/ascents.md` distinguishes production packet chains from tiny
owners, paged spines and generation-cache experiments. Those prototypes are not
an adopted storage replacement. Its coordinator-owned workers and synchronous
borrow contracts remain relevant to later host/shared-memory work; they do not
solve Blot's higher-order reference cycles.

Adopted from that review: `list.splice` and `list.splice_many`, implemented as
ordinary source over structural slicing/concatenation. Batches validate ordered,
nonoverlapping original coordinates before construction, preserve same-position
insertion order and share unchanged subtrees. Tests cover staged and runtime
execution, snapshots, empty edits and invalid ranges. There is no compiler
recognition of these names and no new public List indexing API.

## Ownership and latest list-like review

The preceding pass compared the uncommitted `../list-like/LIST.md` and packet runtime on
2026-10-07. Its HEAD was `cbec09512aad063dd7ca3fbf7cdf2953a142ff98`; the document
itself was untracked, SHA-256
`5ceda3ca053c6bdadb0fb0d187cb651917498cdb947dbc9ca5ee709feec2b4ad`.
It describes reference-counted packet/span chains with dense buffers, not RRB
trees. Fresh materialization uses up to 4,096 integer values per span, growth up
to 1,024, and small edit buffers. Those limits concern their integer-only
representation; Blot lists can contain references and retain distinct Array APIs.

| Technique | Blot decision |
| --- | --- |
| Empty values without allocation | Implemented with immutable descriptors in reserved arena metadata. |
| No work for unchanged values/ranges | Identical-bit internal replacements, whole-list slices and empty concatenations allocate nothing. Shared descriptors freeze before reuse; subsequent consuming writes detach them. |
| Dense span traversal and bulk copying | Already implemented as whole-leaf traversal/copying. |
| Larger materialization buffers | Keep as a measured experiment: larger leaves would increase the cost of a shared point edit. Current million-element shared edits copy less than 4 KiB. |
| Constant-time range views | Keep current structural slicing: partial boundary leaves detach, so a tiny slice does not retain the source backing. |
| Sparse filter compaction | Current source filtering builds dense output leaves. Evaluate additional compaction only against measured fragmentation, rather than adding another unconditional pass. |
| Host span borrows / reference-counted backing | Useful follow-up after precise ownership covers borrowed views, shared children and suspension. |
| Adapter syntax and indexed lists | Keep ordinary source iterator adapters, separate List/Array types and no public list indexing. |

The compiler now owns an explicit temporary-lifetime plan between symbolic Wasm
optimization and encoding. Single-region, nonescaping allocations release their
storage after the final borrowed access, including records larger than SROA's
64-byte limit. Calls/control crossings, unknown addresses and escaping objects
remain outside that proof. Numeric collection element layouts also identify
pointer-free array payloads and list leaves, preventing integer bits from being
mistaken for references and avoiding payload scans. Both are general compiler
rules; neither recognizes standard-library declaration names.

Paired measurements use the immediately preceding compiler
`e8ac85b12de7e90fa1359ab489dff857b82535a1dfd75ab538270983d5bf4029`,
identical source, ten warmups and 25 alternating pairs. Each guest retains a
million-element startup List outside timing. Timing includes the public guest
round trip and arena reset. An array export makes memory observable in both
variants; zero reported memory is rejected by the harness.

| Runtime, 100,000 iterations | Before ms | After ms | Before guest bytes | After guest bytes |
| --- | ---: | ---: | ---: | ---: |
| Cursor / take / fold | 30.464 | 11.556 | 6,160,384 | 6,160,384 |
| Source range / fold | 22.296 | 7.579 | 6,160,384 | 6,160,384 |
| Temporary 18-field records | 0.941 | 0.882 | 17,301,504 | 4,456,448 |

A separate executed-Wasm loop, with no collection calls, performs 100,000
allocations using one 256-byte block. The source record regression, without the
large startup List, remains within 192 KiB across repeated calls. Pointer-valued
list tests distinguish actual references from identical scalar bits and repeat
collection after structural edits. Snapshots, early return and escaping storage
retain their behavior.

The same frozen 394 KB gdev snapshot measures 810.4 → 825.7 ms fresh-process
compilation, 511.3 → 532.0 ms first retained edit, 495.0 → 510.5 ms subsequent
edit and 2.70 → 2.83 ms no-op. Peak RSS is 75.1 → 75.6 MiB; output is
614,815 → 615,349 bytes. These are paired results from this run, separate from
the earlier table below. The new analysis adds compiler work; the cold/edit
targets remain unmet. Raw reports and source hashes are under
`build/ownership-review/{lifetimes,compiler}/report.json`; reproduce with
`scripts/bench_lifetimes.ts` and `scripts/bench_iterators.ts` respectively.

Tracing has **not** been removed. The cycle audit found a legal heap cycle:
forcing a demand reads a closure from State, and the memoized result points back
to that same demand. Clearing State does not clear the demand's cached result.
The executable law in `arena_gc_execution.test.ts` checks this behavior and
bounded memory across 20,000 discarded cycles. Plain reference counting cannot
be substituted for the collector. Full control-flow ownership, shared releases,
cyclic ownership groups and suspended-effect cleanup remain required gates.

Validation: the complete compiler gate passes (1,044 native tests and 521 guest/
client tests), followed by the strengthened source-memory check and the new
cycle-reclamation law. The analyzer reports zero errors and the same 122 existing
warnings. No language APIs or list-indexing rules changed in this pass.

## Iterator and structural-list follow-up

The following measurements describe the earlier iterator checkpoint, before the
ownership and list follow-up above.

The 2026-10-07 follow-up starts at checkpoint `5f09303`. It adds ordinary
`iter`/`next` dispatch, immutable collection cursors, source adapters in
`std/iter`, structural list concat/slice, whole-leaf traversal and copying, and
explicit and automatic four-lane SIMD. Optimizations inspect types, control flow
and ownership; they do not match prelude or adapter declarations by name.

Runtime reclamation already used a nonmoving tracing collector in Wasm linear
memory. Ownership analysis enables reuse and allocation elimination, but does
not prove all lifetimes. The loop collection policy now measures allocation
traffic, including free-list reuse, instead of collecting every four iterations.
Its budget includes retained startup data because that data is also traced.

The paired runtime probe uses 20 warmups and 21 alternating samples. Results
include guest ABI copying; List initialization is outside the repeated calls.

| Runtime probe | Checkpoint median ms | Current median ms |
| --- | ---: | ---: |
| Fold a million-element List | 1.828 | 0.964 |
| Generate a million-element numeric Array | 1.266 | 0.979 |

Current-only adapter probes, with eight warmups and 15 samples, take 20.750 ms
for a 100,000-element cursor/take/fold pipeline and 14.904 ms for a source
range/fold. Both modules retain a million-element startup List, which increases
collection work. These pipelines still allocate; the local scalar-replacement
path does not establish universal allocation-free iteration. A separate
executed-Wasm regression checks 8,193 advances through an ordinary user wrapper
and finite loop carry within 192 KiB of committed guest memory.

Structural operations share covered subtrees, rebuild boundary paths, and copy
partial leaves. Tiny slices retain their own small leaf instead of retaining the
source tree. Direct runtime allocation measurements exclude arena metadata
initialization and host conversion:

| Operation | New bytes |
| --- | ---: |
| Construct a million-element List | 4,387,392 |
| Slice 100,000 elements from it | 1,280 |
| Slice one element from it | 128 |
| Concatenate that List and a 1,000-element List | 640 |

The current 100,000-element slice plus array conversion/host copy takes 0.151 ms.
Concatenating 200,000 and 1,000 retained elements plus conversion/copy takes
0.074 ms. These are distinct from the tree-only allocation measurements above.
Leaves retain the existing 248-element capacity; adjacent tiny leaves coalesce
with a bounded copy. This follow-up does not replace the entire tree layout.

The compiler comparison freezes the same 51 game/package sources for both
variants, loading 53 modules including the standard library, about 394 KB total.
Five fresh-process builds alternate variants with warm filesystem caches.
Three retained sessions per variant each measure population, first edit, revert,
subsequent edit and no-op; the first edited output is checked against an
independently populated compilation. Timing separates output validation/hashing
from the public build round trip.

| Compilation boundary | Checkpoint median ms | Current median ms |
| --- | ---: | ---: |
| Fresh native process, including output and teardown | 900.7 | 915.7 |
| Retained session population, including opening | 1,009.5 | 1,026.1 |
| First retained edit | 564.7 | 576.9 |
| Subsequent retained edit | 559.0 | 572.3 |
| Retained no-op | 2.7 | 2.8 |

The fresh-process current samples range from 904.6 to 918.3 ms. Peak process RSS
is 73.8 MiB versus 72.4 MiB; compiler-requested peak storage is 55.7 MiB versus
55.5 MiB, and all requested storage is released. Emission dominates the current
fresh build at about 738 ms in the first sample. Wasm grows from 571,030 to
614,815 bytes as inlining and runtime helpers expand. **The 500 ms cold and
under-100 ms edit targets are not met on this larger snapshot.** Earlier tables
below describe different, smaller frozen game workloads.

Validation passed `deno task test:compiler`: the native suite and 515
guest/client tests, including effects, early exit, monadic iteration, cursor
snapshots, structural sharing, scalar/SIMD arithmetic parity, trapping tails,
bounded loop memory, and retained edits/error recovery. The analyzer reports
zero errors and 122 existing warnings. The gdev regression found during this
work is covered by native evidence and executed generic F32 traversal tests.

Reproduce using separate checkpoint/current builds and an immutable gdev source
snapshot containing `src/` and `packages/`:

```sh
deno run --allow-read --allow-write --allow-run scripts/bench_iterators.ts \
  zig-native/zig-out/bin/blotc std build/iterator-review \
  /path/to/checkpoint/blotc /path/to/checkpoint/std /path/to/gdev-snapshot
```

The [raw report](../build/iterator-review/report.json) records every sample,
source manifest, standard-library hashes, native work counters, output hashes,
CPU/RSS and memory measurements. It is an ignored local build artifact. The
baseline executable SHA-256 is
`6773dd73d2930de0edee5cc8555b4706a771a25cb8325a5cee9733c9e2eb33b5`;
the measured executable is
`e8ac85b12de7e90fa1359ab489dff857b82535a1dfd75ab538270983d5bf4029`.

## Earlier audits

The October 2026 audit covers `std/prelude`, `std/array`, `std/list`,
`std/vector`, their compiler lowering, and the Deno compiler/guest boundary.
The changes remove avoidable demand objects, repeated collection copying and
vector intermediates. They preserve immutable values, callback order, numeric
behavior and fresh-versus-retained compilation parity.

The first measurements compare `775d370` with `86a527b`. The
[runtime follow-up](#runtime-follow-up) compares `86a527b` with the next working
revision and adds staged-construction measurements.

## API behavior

Collection transformations keep their collection argument last for pipelines.
`List a` and `Array a` remain distinct. Lists support traversal and construction;
only arrays expose indexing, checked `get`/`set`, and trapping `at`/`replace`.
Conversions are explicit. Numeric arrays cross the guest ABI by copying, so
host mutation cannot alter retained guest values.

List `fold_left` now propagates reducer effects, matching the array fold.
The added list `any` and `all` propagate effects and stop at the first deciding
element. Empty inputs return false and true respectively without invoking the
callback. List `filter` retains effectful predicates and visits each element
once in order. Array construction and collection `map`/`generate` retain their
pure callback contracts.

`Result.unwrap_or_else` now matches the existing Maybe operation: its fallback
is deferred until failure. `unwrap_or` remains eager. `@demand` is the preferred
spelling for evaluating a deferred argument; `@force` remains an alias. A
successful demand is shared, whereas an ordinary callback runs each time it is
called. See the [demand design](../zig-native/DEMANDS.md) for the full contract
and remaining control-flow questions.

The public compiler API remains asynchronous. Keep a `createCompiler` instance
open across edits to retain work, and dispose it when finished. The reference
now documents `prelude: null`, directory aliases and source validation using the
Zig API. Guest lifetime, host exceptions and queued project requests remain
covered by their existing regression suites.

## Implementation changes

| Area | Change and cost boundary |
| --- | --- |
| `&&`, `||`, simple demand combinators | Known, fully applied bodies use branches and locals. Admission examines at most 96 expression/pattern nodes and never matches operator names. Repeated demands share a local result, reset per call. |
| `prefix_sums` | Recursive pair sums replace full-array doubling passes. Total work and intermediate array storage are linear, including constant evaluation. U32 wrapping behavior is unchanged. |
| `indices`, `filter`, `filter_map` | One runtime traversal collects into a private chunked list, followed by one array conversion. Predicates/transforms run once per input element. |
| Conditional list construction | Ownership flows through `if let` branches when no previous version remains live. Surviving aliases and closure captures still prevent mutation. |
| `list.append`, `list.prepend`, `array.replace` | Direct wrappers and their aliases preserve the intrinsic's ownership optimization. A fully applied wrapper must use each parameter exactly once as an intrinsic operand. Actual arguments still evaluate in written order. Exclusive replacement, including direct `@array.set`, updates the existing allocation. |
| Array `push`, `concat`, `flatten` | `push` uses the append primitive. `concat` avoids intermediate chunk arrays. `flatten` counts lengths without allocating prefix-sum arrays. Both check length overflow before filling the result. Runtime array append still copies. |
| Staged append/prepend | Session-owned buffers reserve slack at both ends. The latest span grows into unused slots; older spans remain immutable. Geometric growth replaces repeated prefix copies. Forks from older versions and indexed replacements still copy. |
| `Result.iterate` | Pattern branches update the state or return directly, removing the tuple/Maybe scaffolding from each iteration. State, result and error types may differ; callback effects and early termination are preserved. |
| Vector `lerp` | Vec2/Vec3 construct one result from scalar interpolation, preserving the existing F32 operation order. |
| `F32.tan` | Sine and cosine share one angle reduction. The documented finite domain and nonfinite behavior remain unchanged. |

Inlining now records each consumed declaration in the caller's code artifact.
Retained compilation checks its exact executable projection and transitive
source dependencies, including when a dependency seed is rebuilt. Changed
callee bodies invalidate emitted callers even when their types are unchanged.
Unrelated declaration edits may retain them; moved IDs and catalog changes
remain conservative.

## Reproducing library measurements

The baseline is commit
`775d3707d27c5c5d64504206c6b3824a458d8929`. The paired harness pins both native
executables and all four standard-library files, checks guest results, and saves
every sample and compilation record:

```sh
deno run --allow-read --allow-write --allow-run scripts/bench_stdlib.ts \
  zig-native/zig-out/bin/blotc std build/stdlib-bench \
  /path/to/baseline/blotc /path/to/baseline/std
```

Use a separately built baseline; changing only library files would miss the
ownership and demand improvements. The executable's build identity rejects
incompatible dependency bundles.

Runtime samples include guest ABI copies. Each variant receives 1,000 warmups,
then 31 alternating samples of 16 calls. Inputs contain 8,193 elements or loop
iterations, except list append, which uses 1,025. Reported memory is committed
guest pages after repeated calls, not total allocated bytes or compiler RSS.
The harness's individual compilation records use a warm filesystem and are not
a cold compilation distribution.

The first audit used Zig 0.17.0, Deno 2.9.7 and V8 15.0.245.2-rusty.
Its resulting compiler identity was
`c827798cae5e6276badeaf83bc8abd341634741c29f5047855e62ea688508377`;
the baseline identity was
`2d8050d273b5baa98107c2a38d4144b92885bbe16d0e510e5b2b41b23968c850`.

| Runtime probe | Before ms | After ms | Guest memory before KiB | After KiB |
| --- | ---: | ---: | ---: | ---: |
| Inclusive prefix sums | 0.259 | 0.064 | 1,088 | 384 |
| Selected indices, including the input flag map | 0.564 | 0.054 | 1,280 | 320 |
| Array filter | 0.367 | 0.040 | 1,280 | 256 |
| Array filter_map | 0.502 | 0.065 | 1,600 | 512 |
| Array concat | 0.026 | 0.026 | 320 | 256 |
| Array flatten | 0.025 | 0.024 | 320 | 320 |
| Array push | 0.017 | 0.003 | 256 | 192 |
| List append loop, 1,025 elements | 2.184 | 0.008 | 5,312 | 128 |
| Vec3 interpolation loop | 0.369 | 0.193 | 3,200 | 2,176 |
| Result iteration loop | 0.172 | 0.184 | 128 | 128 |
| Array of F32 tangents | 0.115 | 0.093 | 256 | 256 |

Filtering is about nine times faster in this probe, filter_map about eight,
prefix sums about four, and vector interpolation about two. The list builder
previously copied its growing contents on each library call; it now uses the
same exclusive chunk reuse as spread syntax. That particular cost change
accounts for its much larger gain. Concat and flatten have similar runtime.
Result iteration has byte-identical Wasm; its differing measured medians do
not indicate an implementation change.

The scalar Boolean probes shrink from 1,579 to 101 Wasm bytes, with two emitted
functions and no memory or function table. Explicit `if` remains 95 bytes.
Source and compiled-dependency builds produce identical output for all four
conjunction/disjunction probes. These module sizes include shared helper code;
they are not a per-operator byte cost in a larger application.

Raw samples, hashes, generated Wasm and full compilation records are retained
locally in `build/stdlib-review/paired/report.json` and
`build/stdlib-review/demands/`. Build artifacts are ignored by Git; the harness
above reproduces the comparison from the two source/compiler versions.

## Game compilation

Compilation uses one pinned gdev snapshot for both variants: 27 loaded source
files including the prelude, about 193 KB total. The source manifest is
`build/stdlib-review/gdev-snapshot/sources.json`, SHA-256
`57d4f3b36a270290472132339c59a9b29158fa04a35306f9b1e4d7ab88fc8a4c`.
Game sources continued changing during the audit; this comparison excludes the
later rock/grid additions exercised by the final integration tests.

| Compilation boundary | Before median ms | After median ms |
| --- | ---: | ---: |
| Fresh CLI, source dependencies | 350.8 | 348.6 |
| Fresh CLI, precompiled dependencies | 316.6 | 312.7 |
| First retained edit, source dependencies | 122.6 | 118.2 |
| Later retained edit, source dependencies | 117.7 | 122.6 |
| First retained edit, precompiled dependencies | 121.0 | 118.4 |
| Later retained edit, precompiled dependencies | 116.8 | 115.4 |

These results show similar compiler latency. Fresh source builds ranged from
345.0 to 354.2 ms after the changes; dependency builds ranged from 311.3 to
323.1 ms. Peak process RSS was about 44 MiB in both variants. Generated game
Wasm fell from 249,128 to 245,282 bytes.

Each cold lane has five alternating fresh process runs, including output writing
and teardown. Executable, Blot source and used bundle pages were evicted and
checked nonresident before launch; system libraries and filesystem metadata were
not controlled. Bundle creation is excluded and measured separately in its
compilation log. Full samples, CPU time and RSS are in
`build/stdlib-review/game-bench/report.json`.

Retained timings are public build-request round trips, measured in three
sessions per lane with warm filesystem caches. Every edited output is checked
against a fresh build. Process/session population is recorded separately, not
hidden in edit times. Adding Wasm validation, hashing and output writing gives
current edit medians of about 133–143 ms; no-op request medians are 1.3–1.7 ms
before those output costs. The 500 ms cold target is met on this snapshot;
**the under-100 ms incremental target is still unmet**. Full records are in
`build/stdlib-review/game-bench/incremental.json`.

## Runtime follow-up

The follow-up baseline is
`86a527b97c32331993c4a006da2c982a7336c365`, with compiler identity
`c827798cae5e6276badeaf83bc8abd341634741c29f5047855e62ea688508377`.
The resulting compiler identity is
`364e41839ea2575176f92ce897a7652f187e7f50dedac97570093d40e1162989`.
Tool versions and runtime sampling boundaries match the first audit. The added
replacement probe performs 1,025 updates to a 1,025-element array.

| Runtime probe | Before ms | After ms | Guest memory before KiB | After KiB |
| --- | ---: | ---: | ---: | ---: |
| Array replacement loop | 0.0831 | 0.00160 | 8,320 | 128 |
| Result iteration loop | 0.1809 | 0.1245 | 128 | 128 |
| Array of F32 tangents | 0.1031 | 0.0905 | 256 | 256 |
| Array flatten | 0.0266 | 0.0259 | 320 | 320 |

Replacement is about 52 times faster in this probe because it no longer copies
the whole array on every update. Result iteration takes about 31% less time;
the array-returning benchmark retains its guest memory footprint. A scalar-only
iteration probe emits no guest memory. Flatten removes temporary metadata, with
similar timing and committed pages on this input. The other paired probes have
similar time and memory to the baseline; no speedup is claimed for them.

The current harness also runs seven alternating fresh CLI processes for each
staged-builder size. Filesystem caches are warm. Wall time includes process
launch, compilation, output writing and teardown; it excludes executing the
result, which is checked separately. Default evaluator limits apply.

| Staged appends | Before wall ms | After wall ms | Before peak compiler bytes | After peak compiler bytes |
| --- | ---: | ---: | ---: | ---: |
| 256 | 3.89 | 3.84 | 951,978 | 940,186 |
| 1,024 | 5.04 | 4.25 | 2,769,868 | 940,188 |
| 4,096 | Failed: storage budget | 5.95 | 19,231,012 | 969,628 |
| 8,193 | Failed: storage budget | 8.58 | 19,231,012 | 1,601,956 |

These are requested compiler bytes, not process RSS or guest memory. The failed
baseline runs are not timings for equivalent completed work. Growth reserves
space geometrically in the existing child arena, and every reserved slot counts
against its storage limit. It never overwrites a published element, even when
an older version survives in a closure or cached value. Small builds retain the
fixed cost of loading and checking the prelude.

Reproduce this comparison with the harness above and the `86a527b` baseline.
Raw samples, source/binary hashes, compilation records and generated Wasm are
retained locally in `build/runtime-review/paired/`. The harness records cumulative
allocation bytes and counts as well as peak requested bytes.

Public examples now use demand parameters and `@demand`, array indexing and
updates, tuple patterns, and `if let` where appropriate. Boolean decisions in
the prelude use `if`; F32 comparison order, right-biased ties and NaN behavior
remain unchanged. Underlying intrinsic definitions and compatibility tests retain
their purpose-specific spellings.

## Earlier verification

`deno task test:compiler` passes: native production tests, packaged compiler,
and all 464 guest/client tests. The new execution tests cover wrapping sums,
empty/chunk-boundary collections, alias snapshots, effects, early exits,
repeated demands, loop memo reset, F32 behavior and retained-body edits. The
follow-up adds direct/wrapped replacements, iterator borrows, staged growth,
branched/captured values and allocation-failure cleanup. All modified public
examples compile and execute with their expected results.
Storage bounds detect growing-copy regressions without timing assertions.

The current gdev integration suite passes all 60 tests. Game sources continued
changing independently; no gdev source edits were made by this audit. Zig
Analyzer now reports zero errors and 121 existing warnings,
with none in the new optimization files. Formatting, type checking for the
benchmark harness and `git diff --check` pass.

## Remaining costs

- Partially applied, escaping, forwarded and callee-loop demands still use
  runtime cells. Bounded expression matches now qualify for local demand reuse.
- Unknown callbacks retain indirect calls. Small known typed functions and
  callbacks use ordinary source inlining/direct calls with bounded expansion.
- Scalar replacement covers small, fully initialized, nonescaping aggregates;
  values crossing calls/ABI/GC roots and mutation through aliases remain boxed.
- Contiguous array append copies; shared list edits now detach a logarithmic
  path and one leaf. Exclusive list edits reuse their tree path.
- Staged indexed regions admit finite nested loops with one collection and
  scalar carries. Observed intermediate versions, arbitrary control flow and
  multiple collection carries keep immutable evaluation. This is independent
  of runtime ownership.
- Code caching remains conservative for moved IDs, changed catalogs and
  unsupported capture/provider/generative domains. Incremental compile latency
  must be measured separately from guest runtime.

## The ten optimization targets

The table below preserves the starting measurements and acceptance goals for
this pass. All implementations are generic compiler/runtime mechanisms; this
pass makes no changes to prelude definitions and recognizes none of their spellings.

The following measurements use the follow-up compiler above, before the ten
changes. Results for the new implementation follow the table.

| Priority | Target | Evidence and acceptance goal |
| --- | --- | --- |
| 1 | Carry ownership through checked updates and nested fields | At 1,025 elements, `values.set(i)(x)` takes 0.0823 ms and 8,448 KiB; `world.values[i] := x` takes 0.0710 ms and 8,384 KiB. Direct replacement takes 0.00148 ms and 128 KiB. Propagate exclusive ownership through the successful Maybe branch and each uniquely owned field, while retaining old aliases and failure behavior. |
| 2 | Preserve ownership across early loop exits | Adding a possible `break` changes the same 1,025-element list builder from 0.00678 ms / 128 KiB to 1.898 ms / 5,312 KiB, even when the break is not taken. The proof currently marks all carries as escaped for a loop that can exit. Model exit values explicitly; executed and untaken exits must preserve snapshots. |
| 3 | Make staged indexed construction linear | A 1,024-element indexed builder peaks at 4,814,238 requested compiler bytes; 4,096 elements exceed the child-slot budget. Introduce unpublished builder storage or a bulk construction path, then freeze surviving values. Published evaluator spans must remain immutable. This should also remove the staged `concat`/`flatten` copying problem. |
| 4 | Keep small records and tuples in scalar locals | The 8,193-step Vec3 loop still commits 2,176 KiB and takes 0.192 ms. Lower unescaped Vec2/Vec3/product fields to locals and loop carries instead of repeatedly allocating record payloads and nominal wrappers. Preserve F32 operation order and existing public ABI behavior. |
| 5 | Specialize known collection callbacks | `array.map (fn x => x + 1)` takes 0.0211 ms / 256 KiB for 8,193 elements; an explicit update loop takes 0.0118 ms / 192 KiB. `arrayFill` emits `call_indirect` for every generated element. Inline or directly call proven callback targets, capturing their arguments once. Unknown callbacks retain the general path. |
| 6 | Eliminate demand cells through matches | The 8,193-step successful `Maybe.unwrap_or_else` loop takes 0.0793 ms / 896 KiB; the equivalent explicit match takes 0.0205 ms / 384 KiB. Extend bounded demand admission to constructor matches while preserving skipped effects, trap order and once-only evaluation. |
| 7 | Right-size small lists and full chunks | Retaining 1,025 singleton lists commits 2,240 KiB, versus 128 KiB for singleton arrays. Every nonempty list gets a 256-slot chunk. A full chunk requests 1,040 bytes; with the allocator header it enters a 2,048-byte size class. Evaluate inline/smaller first chunks and capacities aligned with allocator classes; measure both singleton-heavy and long-list workloads. |
| 8 | Share structure between list versions | Retaining all 1,025 list prefixes costs 1.924 ms and 5,312 KiB. A shared edit currently copies the entire chain. Use immutable shared chunks with copied paths, or another persistent representation, to make branching construction subquadratic while keeping exclusive builders fast. List indexing is not required. |
| 9 | Cache code containing static captures | `requireFreshCode` deliberately excludes code jobs whose static captures are missing from their keys. Give retained captures complete value/evidence identities so unrelated edits can reuse these jobs; changed staged values, providers and nominal identities must still invalidate them. This target comes from code inspection, not a measured speedup. |
| 10 | Track inlined bodies individually | `readInlineBody` records whole owning modules, and fragment admission blocks callers when any recorded module changes. Record the consumed body and its semantic dependencies, with early cutoff when those results are unchanged. An unrelated helper edit should retain caller code; a consumed body edit must rebuild it. Measure bookkeeping cost as well as reuse. |

The runtime probes are in
[runtime_costs.blot](../scripts/fixtures/runtime_costs.blot). Reproduce them with:

```sh
deno run --allow-read --allow-write --allow-run scripts/bench_runtime_costs.ts \
  zig-native/zig-out/bin/blotc std build/runtime-costs
```

Each probe has an independent guest instance of the same module, 1,000 warmups
and 31 alternating samples of 16 calls. Results are checked before timing. The
report includes all samples, compiler/source hashes and compilation counters.
Guest memory means committed Wasm pages, including temporary capacity; it is
not cumulative allocation or compiler RSS. The staged-builder figures above
are separate individual compiler runs, not a timing distribution. Local evidence
is retained in `build/reinstall/runtime-costs/` and
`build/reinstall/staged-updates-{1024,4096}.*`.

Relevant implementation boundaries are
[ownership analysis](../zig-native/src/owned_arrays.zig),
[Wasm emission](../zig-native/src/core_backend.zig),
[constant evaluation](../zig-native/src/core_eval.zig),
[demand admission](../zig-native/src/demand_inline.zig),
[list layout](../zig-native/src/list_runtime.zig),
[code keys](../zig-native/src/code_artifacts.zig) and
[fragment admission](../zig-native/src/artifact_fragment.zig).

## Results of the ten general optimizations

The baseline is the frozen working compiler with identity
`364e41839ea2575176f92ce897a7652f187e7f50dedac97570093d40e1162989`.
The resulting compiler identity is
`b3056fea5d681f7b05afc915104c1a1e4aebf577ddde994aa9408a823031e6b0`.
Every standard-library `.blot` file is byte-identical between these two inputs.
The improvements follow typed structure, intrinsic operations, ownership and
complete dependency evidence; no prelude names select an optimization.

| Target | Implemented behavior |
| --- | --- |
| 1–2: ownership | Checked wrappers with arbitrary success/failure constructors, nested uniquely owned paths, and explicit loop exit edges retain ownership. Extracted inner arrays, surviving aliases and closure captures prevent mutation of their snapshots. |
| 3: staged construction | A proven private indexed region copies its input once, updates scratch through finite nested loops and scalar carries, then freezes once. Observed intermediate versions use immutable evaluation. |
| 4: small aggregates | Fully initialized, nonescaping records, tuples and nominal wrappers use scalar locals, including separate loop versions. Calls, public ABI values, unknown offsets and GC roots stay boxed. |
| 5–6: calls and demands | Known callbacks use direct calls with captured arguments; bounded inlining exposes aggregate results inside loops. Constructor matches and guards qualify for local demand memoization, preserving skipped effects and once-only evaluation. |
| 7–8: lists | Persistent balanced trees use right-sized leaves of at most 248 words. Shared edits copy a path and one leaf; exclusive edits reuse their nodes. Both old and new versions can subsequently be consumed independently. |
| 9–10: retained code | Static captures require complete value/evidence graph equality. Inlined dependencies name consumed declarations. Unrelated body edits can retain code; changed executable bodies or capture values invalidate it. |

| Runtime probe | Before ms | After ms | Guest memory before KiB | After KiB |
| --- | ---: | ---: | ---: | ---: |
| Checked array updates | 0.08188 | 0.00171 | 8,448 | 128 |
| Nested field updates | 0.07097 | 0.00196 | 8,384 | 128 |
| List append with a possible break | 1.86551 | 0.00884 | 5,312 | 128 |
| Retaining every list prefix | 1.87403 | 0.04459 | 5,312 | 960 |
| Retaining singleton lists | 0.03133 | 0.01475 | 2,240 | 256 |
| Successful constructor demand match | 0.07811 | 0.00180 | 896 | 64 |
| Known callback array map | 0.02118 | 0.00749 | 256 | 256 |
| Vec3 interpolation loop | 0.19222 | 0.03437 | 2,176 | 128 |
| Exclusive list append | 0.00667 | 0.00882 | 128 | 128 |

These use the probe sizes and sampling boundary documented above. Probe order
alternates within each compiler run; compiler variants run separately. Ratios
are specific to these inputs. Checked updates are about 48 times faster,
shared-prefix construction 42, known callback map 2.8, and vector interpolation
5.6. Exclusive list append is about 32% slower: maintaining the persistent tree
adds work even when no snapshot survives. Its committed memory remains 128 KiB.
Direct replacement and explicit array loops have similar time and memory.

Staged indexed construction now completes at 4,096 elements under the default
limits. Five alternating fresh CLI runs per variant/size use warm filesystem
caches and include process startup, writing and teardown. Generated answers are
executed and checked separately from timing.

| Indexed elements | Before wall ms | After wall ms | Before peak compiler bytes | After peak compiler bytes |
| --- | ---: | ---: | ---: | ---: |
| 1,024 | 7.49 | 6.01 | 4,814,774 | 1,301,255 |
| 4,096 | Failed: storage budget | 10.37 | 17,883,062 | 1,301,255 |

Requested compiler bytes are distinct from process RSS and guest memory. A
failed baseline is not equivalent completed work. Executed regressions also
cover nested loops, staged concat/flatten, preserved input aliases and repeated
updates to the same index.

Ordinary source inlining uses a four-node budget, expanded to 64 for aggregate
results inside loops or known callback arguments. Expansion is limited to three
nested calls and stops beyond 4,096 emitted instructions. This keeps source
helpers general while limiting code growth and repeated refinement. Within one
compile, the code, principal and query paths share semantic validation only for
the exact same source owners and admission options. Executable body and captured
value validation remain additional requirements.

The final game comparison uses the same pinned snapshot and measurement
boundaries as the earlier game audit. Filesystem eviction, public request timing,
population costs and fresh/retained Wasm equality are recorded separately.

| Compilation boundary | Before median ms | After median ms |
| --- | ---: | ---: |
| Fresh CLI, source dependencies | 300.6 | 315.0 |
| Fresh CLI, precompiled dependencies | 267.8 | 283.3 |
| First retained edit, source dependencies | 96.2 | 106.0 |
| Later retained edit, source dependencies | 93.1 | 101.0 |
| First retained edit, precompiled dependencies | 95.6 | 106.7 |
| Later retained edit, precompiled dependencies | 93.8 | 102.2 |

Peak RSS stays about 44 MiB; Wasm grows from 244,033 to 280,907 bytes. No-op
requests take about 1.3 ms, excluding validation, hashing and writing the
returned bytes. Runtime optimization adds roughly 5–6% to fresh compilation and
8–12% to these edits. **The 500 ms cold target is met on this snapshot; the
under-100 ms edit target is not.** Static-capture and per-body cache tests prove
actual reuse and invalidation, but this game result does not establish a net
compiler speedup from the ten changes.

The frozen baseline and final raw reports are retained locally under
`build/general-optimizations/before/`, `runtime-before/`, `final-runtime/` and
`final-game-bench/` and `final-staged/`. Reports contain all samples, binary/source hashes, output
hashes and work counters. They exclude unrelated later changes to live gdev.

`deno task test:compiler` passes all 1,023 native tests and 471 guest/client
tests, including allocation-failure sweeps, alias/effect/exit laws and exact
fresh-versus-retained output checks. Zig Analyzer reports zero errors and the
same 121 warnings as the starting tree. All 73 live gdev tests are covered and
passing: the restricted run passed 64; nine renderer tests failed because its
graphics adapter lacked `VIEW_FORMATS`, then all 13 renderer tests passed with
normal GPU access. No gdev source changes were made in this pass.

The packaged native compiler matches the verified release binary. The standalone
CLI was rebuilt, checked by compiling and executing the 4,096-element staged
builder, and installed at `~/.local/bin/blot`. New gdev compiler sessions use
the updated workspace package. Logs are in `build/general-optimizations/`.
