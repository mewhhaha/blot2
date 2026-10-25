# CT114 frontend checking

The user requested a sub-second fresh frontend, including higher-level changes
to checking. The earlier Baba review is in
[compile measurements](COMPILE_MEASUREMENTS.md#fresh-frontend-and-baba-review-25-october-2026).

There is already only one compiler: Zig. The public API starts its native
project server; CLI compilation invokes `blotc`; semantic editor queries use the
native client. TypeScript hosts the CLI, packages, assets, formatter, derive
source generator and Wasm guests. Baba supplies tooling syntax, not a second
type checker or code generator. The READMEs now state that explicitly.

## Measured starting point

The CT113 release profile spends 1.678 s before the backend: checking 1.277 s,
lex/parse 36 ms, lowering/freezing 220 ms and validation 112 ms. The
ordinary-edit frontend is already 124/118 ms. These exclusive clocks come from
an instrumented build, separate from the 7.078 s unprofiled fresh median.

New whole-project counters cover all 189 completed module checks. The unchanged
algorithm constructs 9,281 generic schemes, scans 3,421,572 pending positions,
selects 641,867 candidates, and queries 1,929,526 type components. It imports
90,541 schemes; 7,089 imported bindings are directly read. That comparison does
not prove the remainder removable: shared callees, associated dispatch,
coherence, exported aliases and immutable publication also consume imports.

## Implemented changes

- One generalization owns a flat candidate table and two variable buffers.
  Candidates contain spans, not separately allocated slices. Type-component
  scratch is reused between candidates. Discovery and predicate order stay the
  same, and failure releases the complete unpublished workspace.
- Schemes with no predicates skip public-slot sharing analysis. Their complete
  type/effect quantifiers still support ordinary independent instantiation. A
  private execution control preserves the old analysis for differential laws.
- `phaseProfile.checking` aggregates completed frontend invocations and their
  normalization work across modules. Backend checker invocations are excluded by
  phase. Counters do not influence semantic choices or artifact identities.

The first two changes alone remove 2,063,300 checker allocation requests (27.0%)
and 189,682,248 requested bytes (17.6%) from the diagnostic build. This does not
establish an equivalent latency reduction. The diagnostic Safe/noLLVM run
overlapped development checks, and its clocks are not release measurements.
Strict fresh-game Wasm bytes agree.

## Rejected query-sharing trial

A bounded 64-slot query table shared free-variable answers during a single
generalization, guarded by exact type/effect/physical epochs, cursor and depth.
Its selected native and guest checks passed, and all five release-profile
fresh/edit/revert outputs matched strict Wasm pins. It recorded 161,744 hits,
but saved only six type-graph visits and six row-graph visits beyond the compact
storage changes. Most hits answered already-cheap requests. It removed another
29,102 allocation requests, under 0.4% of the original total, while checking
state on millions of requests. That does not justify the additional machinery.

The table, its private switch, counter and tests are removed from the final
candidate. Trial sources and measurements remain under
`build/bench/ct114/query-trial-source` and `profile-release-under-test`. Its
full gate was cancelled during native execution; that run is not a pass. The
final candidate retains no new query cache.

## Verification and remaining work

The profiled fresh frontend median is 1.872 → 1.784 s; checking is 1.421 → 1.344
s. Checker allocation requests fall 27.0% and requested bytes 17.6%. Unprofiled
whole-build measurements do not establish a latency improvement. See
[the final report](zig-native/CT114_QUALIFICATION.md) for the unprofiled
three-pair screen and its limits. Allocation reductions and profiled latency are
different measurements; the sub-second frontend target remains open.

The compact-storage development cycle passes in 29.72 s with all 2,589 native
laws compiled, 36 selected laws executed with sampled allocation failures, three
executed guest tests, formatting, types and zero Zig analyzer findings. The
final checked span conversions pass the full gate: 2,589 exhaustive native laws,
1,660 release guest tests, 48 smoke tests and 57 tooling checks. Final Zig lint
has zero findings. Strict fresh/edit/revert outputs, independent fresh controls,
input pins and the CPU guard pass.

The source is frozen under `build/bench/ct114/qualification-work/blot2`, based
on qualified CT113. Concurrent array changes are excluded exactly as in CT113;
this does not qualify the combined working tree. Source pins, the final audit,
raw profiles and cancelled trial evidence are under `build/bench/ct114`. CT110
remains installed. No commit or push is included.

The [frontend architecture review](COMPILER_FRONTEND_REVIEW.md) sets out direct
instantiation from immutable producer interfaces, requirement dependency
tracking, and fewer checked/Core/frozen copies. These changes remain
unimplemented. A future change must preserve exact identity, private quantified
variables, diagnostics and coherence; moving the same work to freezing or
backend preparation does not count as a frontend improvement.
