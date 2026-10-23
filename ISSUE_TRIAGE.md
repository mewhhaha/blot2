# Triage of issues 26 and 27

23 October 2026. Read-only triage against Blot main `93bc8d4`, Ink main
`1a291a1`, and gdev main `809b0c5`. No new runtime benchmark was performed, and
no GitHub issue, label, or state was changed.

| Issue                                                                                | Verdict                                                                                                                                           | Recommended priority | First deliverable                                                                                                   |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------- |
| [26: nested numeric layouts](https://github.com/mewhhaha/blot2/issues/26)            | Keep open; a representation/performance enhancement with a demonstrated implementation boundary, but no current end-to-end regression established | P2                   | A small executed comparison of nested/flat, structural/nominal values across the relevant call and array boundaries |
| [27: compilation memory and edit costs](https://github.com/mewhhaha/blot2/issues/27) | Keep open; prioritize attribution, with implementation ownership determined by the measured phase                                                 | P1 investigation     | Separate Blot compilation from uncached/cached Wasmtime module compilation and host loading                         |

## Issue 26

The problem makes sense and is not a duplicate of completed issue 17.
[The existing allocation qualification](zig-native/ALLOCATION_COST_QUALIFICATION.md)
covers small structural records and proved callbacks; it explicitly retains
allocation for the nominal constructor fixture and for unknown callbacks.
[The current guide](compiler/guide.md) documents flat packed collection rows and
boxed nested/reference-bearing rows.

The source agrees: `packed_layout.zig::rowWords` admits complete flat scalar
rows of at most sixteen fields. Its recursive `analyze` plan is a separate
experiment, not the production collection rule, and does not admit arbitrary
nominal representations. Removing this boundary requires checking storage, value
materialization, calls, and ownership together.

The motivating flattened `Mat4` and `matrix_storage.blot` experiment is not in
the attached Ink main or gdev main. Ink main still defines `Mat4` using four
`Vec4` fields. That does not disprove the reported local experiment; it means
the historical capacity/CPU figures cannot qualify current upstream. Start with
a self-contained fixture and preserve the historical figures as context.

Recommended scope:

1. Compare flat and nested scalar data in structural and nominal forms. Cover
   direct/imported calls, known/unknown callbacks, array storage and updates,
   and an observed old snapshot. Use a small representative matrix rather than
   every possible cross-product up front.
2. Measure actual allocator traffic, copy/ownership traffic, capacity, runtime,
   code size, and compile cost separately in both codegen tiers. Compare exact
   mathematical/wire results where operation order is unchanged.
3. Improve only demonstrated costly boundaries, preserving public host ABI,
   nominal identity, immutable snapshots, and floating-point order. Unknown
   callees need an explicit compatible calling convention or conservative
   handling; an inlining result is not a universal no-allocation guarantee.
4. Keep allocation-free contract research a separately gated investigation. Do
   not make a new annotation or a universal allocation-free guarantee part of
   the initial nested-layout fix. Record feasibility and remaining proof
   requirements before deciding whether it merits its own implementation.

**Closure:** current executable evidence either shows no remaining gap or
qualifies a measured repair and documents the supported boundaries. Neither
fewer emitted allocation sites nor lower committed capacity alone proves a
runtime speedup.

## Issue 27

The problem makes sense and overlaps the existing 086/093/100–104 measurement
and optimization work. Reuse that campaign and its exact cache admission rules.
A second cache implementation is not warranted by this issue.

The newest gdev report strengthens the case for isolating the host compiler: it
records a warm process-group peak near 0.48 GiB and an uncached native startup
peak of 5.00 GiB, with module readiness taking 1,617 ms versus 3 ms cached.
Pen's `load_module` reports readiness after its Wasmtime module load;
`GuestModule` can compile through `Module::new` or deserialize a cached native
module. The observation is therefore compatible with a Wasmtime compilation
peak. It does not yet establish that owner or rule out overlapping processes.

Recommended scope:

1. **Compiler-only:** build the frozen application to Wasm with Blot, without
   launching Pen. Attribute compiler time, cumulative/peak/live requested
   memory, and process RSS.
2. **Host compilation-only:** load those identical Wasm bytes through Pen's
   uncached Wasmtime path, then through its cached/precompiled path. Measure the
   process tree and mark module compilation/deserialization/instantiation
   separately.
3. **Application loading:** measure assets and normal startup separately,
   recording any overlap. Preserve all three cache states in the report; warming
   a cache must not hide the original cold-start cost.
4. **Retained edits:** run the issue's edit/recovery matrix and long sessions
   using existing counters. Measure cache growth, eviction, and fallback after
   stale/corrupt entries. Separate Blot retained compilation from host module
   recompilation after the Wasm changes.
5. Implement improvements in the phase that owns the dominant cost. If that
   phase is Pen/Wasmtime, route the implementation there while retaining Blot
   code size or generated helper complexity as testable contributing causes. A
   cross-repository measurement issue should not become an unsupported claim
   that the Blot compiler alone uses 5 GiB.

**Closure:** reproducible phase ownership, qualified fixes against agreed
budgets, bounded retained memory, and correct fresh/retained/eviction/recovery
behavior. An inconclusive experiment does not close an unresolved problem. If
the peak belongs entirely to another component, record that evidence and track
its resolution there before calling the application problem resolved. After the
baseline, choose explicit latency and memory budgets. The issue currently has no
quantitative improvement target; it should not become an undefined promise of
making all compilation faster.

## Effect on the completion plan

Preserve and reconcile the existing candidate before making overlapping compiler
changes. Then investigate #27's cold-start attribution first and run #26's small
representation matrix alongside the common baseline. Use those results to order
implementations. Neither issue requires completing #25's new task/channel
language features first.

Do not close either issue from this triage. Both have useful, distinct work;
their first steps are evidence gathering rather than a predetermined rewrite.
