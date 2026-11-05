# Wasm lifetime writing record

The complete production first writing pass is present in
backend/wasm_lifetimes.goose. Test-only native helpers remain oracle evidence.
No builds, tests, formatter checks, compiler invocations, or verification ran.

The port preserves demand-driven conservative call summaries, active-recursion
and depth cutoffs, provider read facts, checked parameter roles, provenance and
fixed-offset borrows, reference overlap limits, transitive escape, private
ownership groups, backwards CFG liveness and edge releases, typed allocation
mask admission, raw publication checks, and both output transformations.
Output artifacts are actual owned IR DetachedBody typed runs. SharedScan retains
one concrete Analysis and invalidate releases its pools before a changed body.
Summaries and Analysis use real typed pool runs with explicit cleanup.

Summaries construction: initSummaries(module) or init(module), then
setProviders(summaries,modes) to copy the modes. prepare completes deterministic
function-order facts. Plan contains releases; RcPlan separately contains admitted,
allocations and writes. Both deinit without allocator parameters. Native 4096-byte
BufferFirst scratch affects allocation routing, not proof authority; the port's
typed temporary pools retain no proof storage in summaries or transformed bodies.

Copied-packet workers execute separate ordinary Goose process programs. No
thread_fn reaches the canonical metadata pools; the section 11.2 non-flat-global
restriction therefore does not require sharing or weakening this analysis.
The root owns the concrete process transport and packet dispatcher.
