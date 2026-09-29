# Bend issues observed while building Blot

Keep suspected Bend defects and missed optimizations here until they have a
small reproducer and current-version evidence. **Do not file or comment on an
upstream issue without the user's explicit approval.** Record the Bend version,
the observed behavior, the expected behavior, and a way to reproduce it before
proposing a report.

## Runtime limitation: JavaScript list helpers exhaust the stack (2.0.32)

The published Bend 2.0.32 JavaScript loader emits recursive calls for
`Base.List.append` and `Base.List.length`. Processing 20,000 elements throws
`RangeError: Maximum call stack size exceeded` on Deno's default stack. This is
a size limit in the JavaScript backend; no incorrect result was observed.

The standalone [reproducer](compiler/repros/bend_js_wide_lists.bend) exports
`append()` and `length()`. Generate it with the release's unmodified `main.ts`
loader, then call either function from Deno. `append()` appends `[20000n]` to
`List.range(20000n)`; the expected result has 20,001 elements. `length()` should
return `20000n`. This also occurred while collecting and counting gdev's pending
specialization constraints. Blot now joins that module-wide list through its
existing tail-recursive `inference_batch.join` helper and counts it in a loop.
The [wide-module regression](compiler/member_row_wide_scans.test.ts) verifies
the order of all 20,001 constraints. No generated output was modified and no
upstream report was filed.

## Candidate: unnecessary work when traversing strings

**Status:** Local investigation; no upstream issue filed for this specific
behavior. This is a performance concern, not a known correctness bug.

In Bend 2.0.31's generated C, `String.cmp` and `Map.bit` consume string nodes
while traversing them and rebuild prefixes to return the original strings.
Blot's `name_equal` also performs consuming matches and ownership cleanup while
walking the strings. Borrowing immutable characters while retaining the owning
roots avoided some of this work in an older native experiment. See
[the source function](compiler/model.bend),
[the regression inputs](compiler/native_string_compare_regression.bend), and
[the experiment record](compiler/HIGH_COST_EXPERIMENTS.md).

The recorded performance measurements used older Bend output and several Blot
changes. They do not measure the cost on 2.0.31 in isolation. Before seeking
approval to file this upstream, reduce the case to a standalone Bend program,
inspect its current generated C, and measure the ownership and allocation costs
on 2.0.31. Compare source-level alternatives if available, keeping Bend's
emitted output unchanged.

**2.0.32 evidence:** In the full native compiler, `M.name_equal_tail` still
emits a consuming traversal with `ctr_take` and per-character ownership cleanup.
The same comparator in a standalone program already emits borrowed reads, so the
full-program difference is not yet reduced to a small reproducer. A Bend source
alternative retains the owning roots while separate cursors traverse the
strings, then releases the roots after obtaining the Boolean result. Its
unchanged generated C uses `term_peek` without per-character allocation or
release in that loop. This is an observed optimization limitation, not evidence
of incorrect results. See the
[full control C](build/gdev-regression-20260927/candidate.c),
[alternative C](build/gdev-regression-20260927/borrow/compiler.c),
[standalone comparison](build/gdev-regression-20260927/borrow/compare.bend), and
[game measurements](compiler/COMPILE_SPEED_RESULTS.md). No upstream report has
been filed.

**Numeric-list follow-up, 2.0.32:** Retaining a `List<Nat>` root alongside the
membership cursor did not produce the same improvement. In the full compiler,
the unchanged generated loop still calls `ctr_take` per list cell and adds a
root keep/release around the scan. This source experiment was discarded before
acceptance; no speedup is claimed. It shows a limit of this borrowing pattern,
not incorrect membership results. The full
[experimental source](build/gdev-traversal-20260927/candidate/compiler/types.bend),
[generated traversal](build/gdev-traversal-20260927/list-borrow-evidence.txt),
and [full generated C](build/gdev-traversal-20260927/compiler.c) preserve the
reproducer. Blot keeps its original list-membership routine.

## Performance limitation: nested forks keep their worker partitions (2.0.32)

An outer fork can assign a large task one worker while other workers finish
small siblings. Inner forks in that large task cannot reclaim the idle workers.
This limits parallelism in Blot's nested checking regions; no incorrect result
or deadlock was observed.

The [control reproducer](build/gdev-traversal-20260927/nested-control.bend)
places one large region beside eight small ones. The
[source alternative](build/gdev-traversal-20260927/nested-batch.bend) keeps the
outer sequence serial so the large region's independent inner tasks can use all
workers. Both produce checksum `401375088`. One diagnostic run during other
build work took 0.52 seconds with either one or four workers for the control,
and 0.19 seconds with four workers for the alternative; these are illustrative
samples, not stable game measurements. See the
[raw samples](build/gdev-traversal-20260927/nested-micro.json) and
[game experiment](compiler/COMPILE_SPEED_RESULTS.md). All generated output was
used unchanged. No upstream issue has been filed.

The full gdev screen regressed from 63.6 to 70.3 seconds against the
traversal-only candidate, with native CPU time increasing from 65.16 to 76.75
seconds. The scheduler alternative remains experimental. Its small reproducer
demonstrates available parallel work, not a general workload speedup.

## Resolved or tracked upstream

- **List boxing leak:** A singleton `Scalar` list rebuilt and fully consumed
  leaked 16 bytes per call on Bend 2.0.21 and 2.0.24. The local
  [reproducer](compiler/repros/bend_boxing_leak/README.md) explains the
  allocation accounting. Bend
  [issue #970](https://github.com/bendlang/bend/issues/970) was closed by merged
  [PR #987](https://github.com/bendlang/bend/pull/987); the fix was released in
  2.0.28. Generated C from 2.0.31 reuses the consumed list cell in both
  branches. The old runtime allocation probe needs updating for the 2.0.31
  allocator interface before it can measure bytes again.
- **Old constructor ownership regression:** The
  [regression](compiler/native_backend_regression.bend) records a Bend 2.0.5
  failure. It passes on current Bend and is not a pending report.

Generated C interface changes that break Blot's former native patch scripts are
an integration concern in this repository, not evidence of a Bend bug.

## Candidate: checker stack exhaustion on a long diagnostic pattern (2.0.32)

**Status:** Local investigation; no upstream report. The reproducer currently
needs the full regression import graph, so this is not yet a minimal Bend bug.

The frozen `build/perf-overhaul/m3-r23-collector-dev-bend32/PROOF.bend` fails
after 28.15 seconds with a checker stack overflow. Its individual changed
modules and new law pass when checked separately. A diagnostic using the
unchanged upstream `book_load` and `book_valid` APIs traced the failure to
`specialization_local_tree_computed_regression.conflicting_answer`, at
`bend.ts:3627`, while checking a nested match against two long diagnostic
strings. See
[the checker trace](build/perf-overhaul/logs/M3-r24-bend-check-diagnostic.log).
The diagnostic records declaration reads through an array proxy; it does not
patch the checker or its generated output.

The source workaround replaces those literal string patterns with explicit
`M.name_equal` checks. The expected error code and full subject remain required.
The r25 full proof passes in 48.85 seconds, unchanged regression JS emission in
107.60 seconds, and all 475 collector/source/development tests pass. Exact
inputs and logs are in `build/perf-overhaul/logs/M3-r25-collector-dev32-proof/`,
`M3-r25-regression-js/`, and `M3-r25-collector-and-source-tests.log`. The
attempted proof/test-entry split was abandoned; the combined proof entry is
restored.
