# Reducing the largest compiler costs

This is the original experiment record. See
[the implementation follow-up](HIGH_COST_IMPLEMENTATION.md) for integrated
results and subsequent native tests.

2026-09-24; baseline commit `0c3ba51`. Three `gpt-6-sol` agents at `xhigh`
investigated specialization, final planning/checking, and ownership traffic in
parallel. The coordinator reviewed the changes, tested a second string kernel,
and serialized native timing windows. Experiments are isolated under
`build/high-cost-study/`; the installed compiler and gdev source are unchanged.

The [current native profile](../build/current-profile/native/REPORT.md)
attributes 42.6% of phase CPU to specialization and 32.1% to final
checking/planning/exports. Runtime ownership routines account for 42.0% of self
samples across those phases; these percentages overlap and must not be added.

## Combined native result

The shared-catalog planner plus both borrowed string operations gives the
following five alternating fresh-process pairs per worker count:

| Median metric                       | 1 worker baseline → candidate | 4 workers baseline → candidate |
| ----------------------------------- | ----------------------------: | -----------------------------: |
| Compile call                        |              1,610 → 1,193 ms |             **1,004 → 742 ms** |
| Native CPU                          |              1,520 → 1,110 ms |               1,370 → 1,080 ms |
| Peak RSS                            |           49,920 → 44,664 KiB |            69,036 → 63,568 KiB |
| Startup + project loading + compile |              1,824 → 1,341 ms |                 1,109 → 842 ms |

Every pair improves wall time and CPU and preserves exact Wasm. Median compile
reductions are **25.8% and 26.1%**, with native CPU reductions **27.0% and
21.2%**. The one-worker and four-worker rows are different measurement windows;
external load changed markedly. They cannot establish the effect of adding
workers.

A separate matched comparison of the **same combined binary** does establish
that effect: one → four workers improves median compile time **1,213 → 1,011 ms
(16.6%)**, while CPU rises **1,130 → 1,430 ms (26.5%)** and peak RSS rises
**44,632 → 63,824 KiB**. All five four-worker samples are faster than their
paired one-worker controls. Work reduction and concurrency both help, with a
clear CPU/memory cost to additional workers.

The combined native candidate passes 176 API differential operations at one and
four workers and all 17 native session tests, including the new operation-only
nominal catalog revision/recovery test. The maintained production transformer /
proof / build gates remain integration work; these are measured prototypes, not
an installed compiler.

Raw paired results and summary JSON are under
[`build/high-cost-study/root/`](../build/high-cost-study/root/), named
`pairs-all-1`, `pairs-all-4`, and `pairs-all-workers`. The executable is
`build/high-cost-study/root/blotc-planning-map-cmp`; `make_planning_combined.py`
records the exact reviewed generated-C contracts.

## 1. Borrow strings instead of reconstructing their prefixes

The native census records 34.88 million reference-wrapper allocations per gdev
compile, including 18.87 million String nodes. `Map.bit` and `String.cmp` both
return their original input strings in value, but generated C reconstructs the
prefixes it traverses. Their experimental replacements retain the original
owning roots, borrow immutable fields, and return the same roots. Both retain
runtime cancellation polling and exact character/ordering behavior.

The Map.bit-only census confirms **11.65 million fewer wrapper allocations**,
all String nodes: 34.88m → 23.23m total. It also removes 1.85m drop entries and
1.85m shared releases. Its polled candidate reduced four-worker median native
CPU by 13.3% and compile-call wall time by 12.7% in five alternating pairs.

Combining borrowed Map.bit and String.cmp gives these separate five-pair
windows:

| Metric              | 1 worker baseline → candidate | 4 workers baseline → candidate |
| ------------------- | ----------------------------: | -----------------------------: |
| Median compile call |              1,886 → 1,455 ms |               1,971 → 1,283 ms |
| Median native CPU   |              1,770 → 1,360 ms |               2,070 → 1,640 ms |
| Median peak RSS     |           49,912 → 44,556 KiB |            62,200 → 57,196 KiB |

Every pair is faster and uses less CPU. The CPU reductions are **23.2% and
20.8%**; wall reductions are 22.9% and 34.9%. External CPU-heavy work continued
throughout the measurements, so absolute times vary substantially between
windows. Our own builds were paused. Compare adjacent controls, do not add
separate experiment percentages, and do not use these separate worker windows as
a controlled one-versus-four-worker speedup measurement.

Validation includes direct shared-root and character edge probes with ASan and
UBSan at one/four workers, 176 native API differential operations, independent
ownership review, and byte-identical 192,168-byte gdev Wasm in every timed run.
The compiled type-system rules are unchanged.

Details:
[ownership census and Map.bit](../build/high-cost-study/ownership/REPORT.md),
[combined string experiment](../build/high-cost-study/root/STRING_TRAVERSAL_REPORT.md).

## 2. Compute the common nominal catalog once

The final planner produces 844 singleton jobs for 821 functions and 23
constants. Only 37 distinct required nominal sets occur; **664 jobs require the
same 17-type set**. Those 17 types are common to every job. The old planner
inserts operation signature requirements into every declaration seed, then
repeatedly combines, closes and sorts them.

The private Bend candidate retains operation requirements separately, computes
their transitive nominal closure once, excludes that closure from local seeds,
and shares its sorted list for jobs with no extra requirements. It leaves the
same final required catalog available to each checker. The new Planning field is
included in the incremental planning cache key. A counter on the exact final
gdev module confirms **664 shared-list reuses and only 180 union/sort
operations**. Per-declaration nominal seed entries fall **10,570 → 707**; the 12
direct shared operation requirements expand to the common 17-type transitive
closure once.

Two source reviews found the set factoring and cache-key changes sound,
including recursive nominal components, imported leaves and unused operation
signatures. The generated-JS candidate passes all 25 planning tests and retains
the full 3,360,009-byte gdev analysis exactly. Three alternating direct planner
pairs also produce structurally identical 844-job results. In that JS probe,
median preparation falls 297 → 188 ms and finishing falls 1,289 → 453 ms; these
are scoped JS measurements under load, not native compiler speedups.

The native planner-only candidate improves one-worker median compile time
**1,149 → 994 ms (13.5%)** and CPU **1,100 → 950 ms (13.6%)**. All five
alternating pairs are faster and emit exact Wasm. Its 17 native session tests
pass, including operation-only nominal signature changes, cache reuse,
failure/rollback, queued revisions and budget invalidation.

The final job DAG has 13 levels, with 438 initially independent jobs followed by
levels of 173, 98 and 57 jobs. Planning is a serial prerequisite for all those
jobs; factoring shared work shortens that prerequisite without changing checker
semantics or job order.

Details: [planning experiment](../build/high-cost-study/final_check/REPORT.md).

## 3. Decide known schema queries before making helper clones

A private generated-JS prototype recognizes exact checked schema helper bodies
and catalog evidence, then decides a closed `Entry→End` type-membership query
before ordinary recursive specialization. It preserves evaluation of the
receiver and argument and emits a small curried Bool helper through the normal
checking path. Unknown types, changed bodies/catalogs and unsupported cases use
ordinary specialization.

For full gdev, eight successful decisions remove 28 `Entry.contains` clones, 28
`Type.eq` clones and 28 generated type-comparison helpers, replacing them with
eight helpers: **821 → 745 checked functions**. The emitted Wasm is
byte-identical. The evaluated builder retains its 18 ordered world cells, 22
scope closures, nine checkpoints and ten ordered system stages.

An optimized duplicate-registration case takes the true branch and produces the
same panic. Changing the helper source causes zero optimization hits and the
same ordinary result. An unused invalid declaration retains the same diagnostic.

This is a source-snapshot feasibility experiment, not a production recognizer.
Native performance is unmeasured. Its constant-evaluation work decreases by
1,872 steps, so raw analysis/fuel counters change; budget-boundary behavior
needs an explicit production design. The useful architecture is a small typed
partial evaluator carrying independently checked source bodies and dependency
evidence. It should next cover builder, snapshot and system construction while
retaining lexical provider identities and captured values.

Details:
[specialization experiment](../build/high-cost-study/specialization/REPORT.md).

## Rejected: a general closed-equality solver shortcut

A bounded success-only certificate skips 11,107 solver equation steps (17%) with
the exact gdev analysis preserved and 3,760 focused solver comparisons passing.
Its native implementation nevertheless regresses median compile time **1,407 →
1,560 ms**, with CPU **1,340 → 1,500 ms**. It should not be integrated as a
performance improvement. This is a useful counterexample to treating fewer
logical solver steps as proof of lower runtime cost.

Details: [closed-equality experiment](../build/high-cost-study/root/REPORT.md).

## Measurement boundary and target

Native timing uses a fresh compiler process and fresh project load for each
sample, with a warm filesystem. The compile-call figure includes preparation,
encoding, IPC, native compilation and decoding; startup and source loading /
parsing are measured separately. All native candidates retain the original gdev
Wasm hash `3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`.

These results do **not** establish a 100–200 ms compile. They show substantial
avoidable representation and planning work without removing type-system
features. Early typed evaluation supplies a concrete route to eliminating whole
groups of generated functions and their downstream work.

## Recommended implementation order

1. Integrate the two borrowed string loops with maintained source/runtime
   guards, ownership probes and normal compiler build gates.
2. Integrate common nominal-catalog planning and its cache-key/test updates.
   Measure the combination; the gains overlap and are not additive.
3. Implement checked-source typed partial evaluation for the demonstrated schema
   query, then extend it to builder/snapshot/system construction. This
   eliminates specialization and downstream checking work while retaining the
   abstraction.

Keep the closed-equality shortcut out. No weakening of polymorphism, nominal
identity, effects or provider semantics is needed for the measured native gains.
