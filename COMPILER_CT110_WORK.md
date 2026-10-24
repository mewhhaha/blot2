# CT110: residual edit costs

Baseline: CT109 (`6a46576`), installed release SHA-256
`6b9ed919a48f4d98b7faaedee3ac25cd87e931601189eb1d1d4239fbd3842b1c`. The 25
October diagnostic pair is in `build/bench/ct109/current-profile-20261025`. It
is attribution, not a latency distribution. Its profiled literal/body edits
spend 1.29/3.37 seconds of thread CPU in inference, and about 1.63/1.66 seconds
of wall time outside inference.

The complete compiler gate, seven final release pairs, held-out execution and
local installation checks pass; see the
[qualification record](zig-native/CT110_QUALIFICATION.md).

Implementation scope:

1. Observe checked requirement headers transitively when inference consumes
   those headers. Preserve full body observations wherever bodies are read.
   Admission must compare public binders, flags, requirements and diagnostic
   locations, including transitive producers. No blanket obligation exemption.
2. Investigate residual refinement and specialization solves, with their exact
   input and dynamic observation boundaries.
3. Reduce temporary solver/scratch construction and measure allocation requests
   separately from retained/live memory.
4. Reduce repeated executable admission work. Fragment lookup already uses a
   coarse fingerprint bucket; another general index is not the first target.

Keep exact Wasm pins and fresh controls on the frozen 554-file workload. Build
native development/tests without LLVM; use the release compiler for performance.
Run the complete compiler gate and zero-finding Zig lint before committing.
Record rejected experiments and remaining work explicitly.

## First diagnostic candidate

`candidate-1-blotc` (`e65dfce7183a…`) passes frozen fresh/edit/revert output
pins. The same-profile comparison shows no reduction in inference regions or
operation visits. The three body principal misses still observe full bodies
(`walk_material`, `haul_all_observed`); checked-header observation alone does
not address them. The closed-prefix row experiment skips no entries and is
replaced by a certificate for rows with exactly one unresolved operation.
Candidate 1 is not an accepted performance improvement.

Development runs pass in 23.60 and 26.90 seconds (sampled allocation faults,
complete native inventory compilation, selected laws/guests and zero lint). Full
qualification was still pending at this diagnostic stage. The expanded
executed-Wasm interface law also passes written requirements, changed bodies,
errors and recovery in both tiers.

The second candidate adds temporary graph-copy buffers and bounded source-only
capture plans. Profiling work also found that capture matching prepares the
entire multi-root graph separately for every root; batching that preparation is
the next change. Current values and cross-root aliases must still be checked.

## Rejected partial-row caches and corrected attribution

Candidate 2 (`125682b37dda…`) also passes exact output pins but neither the
closed-prefix nor the one-unresolved-operation experiment reduces operation
visits. Both are removed. The temporary graph-copy buffers save 415 allocation
calls on the literal edit and 1,255 on the body edit, a small fraction of the
1.46/3.94 million totals. They do not explain a large memory improvement.

Successful structural request memoization avoids 56,133 of 100,750 checks on the
literal edit and 51,917 of 95,073 on the body edit. The capture-plan path has
zero calls on this gdev workload, so its general improvement is not a measured
gdev speedup. Scratch reporting now includes the separate fragment matcher;
previous zero scratch figures omitted that owner.

The remaining principal misses have inferred requirements: `walk_material` has
one inferred and one callee requirement; `haul_all_observed` has four inferred
and three callee requirements. Their full-body dependencies remain necessary
under the current proof. The new checked-header path does not remove these
misses and does not waive inferred obligations.

## Shared immutable effect lists

Candidate 3 (`df329075614d…`) replaces both unsuccessful experiments with an
exact shared-label-span lookup in the existing four certificate fallback slots.
Resolved rows can have different headers but the same immutable operations. The
deterministic Safe/no-LLVM screen preserves all frozen output pins while
reducing operation visits from 76,384,805 to 22,444,048 on fresh builds,
36,420,954 to 5,316,031 on literal edits, and 58,470,836 to 19,752,292 on body
edits. This screen establishes work reduction, not release latency.

The final candidate additionally shares a store-owned effect-label slice when
rebuilding a row, with independent headers and cursors. Its law checks subspans,
buffer growth, rollback, ID recycling and every allocation failure. Batched
capture matching retains each root's original depth walk and rolls back all new
anchors if any root declines. Full qualification and release comparisons were
still pending at this stage; their final results are recorded below.

Candidate 3's single profiled release pair passes strict outputs. CPU changes
are fresh 12.17 → 11.91 s, literal 5.23 → 4.91 s and body 8.24 → 8.19 s. Host
load rises from 8.8 to 24.5 on 16 hardware threads; these instrumented figures
do not establish a latency distribution. Corrected scratch reporting finds 1,742
fragment match calls visiting 3,978,261 plan positions on the literal edit. The
source-plan cache's separate path is still unused by gdev.

The final development check passes in 25.54 s: Safe/no-LLVM compilation of 2,576
native laws, 99 selected laws with sampled allocation faults, 56 guest tests and
zero Zig lint findings (`run-ad94019cbd6f406c`). The isolated full gate uses
frozen sibling fixtures and exact pins for 1,003 source/test/client/ tool files.
It retains the existing deterministic allocation budgets.

## Full-gate cleanup failure

The first full gate (`run-328542291c0a89f1`) passes all 2,576 native laws with
exhaustive allocation failures in 1,228.48 s across two shards. Its guest phase
then fails after 1,085 passes while removing a temporary resource-test cache:
`Directory not empty`. The remaining `.blotout` and `.blotseed` files identify a
detached restart writer. The native cache deliberately lets that writer outlive
`dispose()`; the test had not joined its cache-key lock before deletion.

The resource fixture now waits for those locks during teardown, matching the
existing restart-cache suite. Assertions and compiler behavior are unchanged;
the focused executed-Wasm test passes. Client documentation now makes the
temporary-directory lifetime explicit. The failed run is retained. The full gate
resumes only the exact verified native evidence and reruns guest/local checks.
The resumed gate (`run-82aeec91e04fc306`) passes in 51.06 s, including 1,656
guests, 48 smoke tests and 57 tooling tests. That interval excludes the already
completed 1,228.48 s native execution. Final Zig lint also passes with zero
findings across 522 files. The final release comparisons and installation
subsequently pass.

## Final outcome

Candidate 4 is qualified and installed. Seven unprofiled pairs against CT109
reduce paired CPU 2.9% fresh, 4.4% literal and 3.0% body, with wall medians
7.335 / 3.034 / 5.035 s. Reverts improve 4.6% / 3.8%; devtools changes -1.3%.
All strict outputs, fresh controls and CPU guards pass. Three held-out pairs and
44 independent Wasm executions also pass.

The final profile confirms the 71.5% / 86.3% / 66.9% fresh/literal/body
operation-visit reduction. It also shows why latency improves much less: most
eliminated visits were already-certified operation checks. Region counts, three
body principal misses and roughly four million fragment-match positions remain.
Allocation traffic and peak RSS are essentially unchanged; fresh logical
requested bytes rise slightly. Do not describe this batch as a broad memory
reduction or completion of the sub-second goal.

Native SHA-256 is
`b0ebc5ecf07f962665fcc3cf879f5e955eb07f1341a0f2b5b8d783b963228dd2`. The
installed CLI/native pass external format/check/build, exact output, runtime
answer 29 and bundled-guide checks. The installation record preserves CT109
rollback copies. Detailed clocks, ranges, caveats and evidence are in the
qualification report.
