# Open issue triage

## Repair status

The first repair batch fixes #29, #30, #31 and #34, with permanent native/Wasm
regression laws and a public alternating benchmark. The complete release gate,
zero-finding Zig lint and application compile-cost screen pass; these four
issues are ready for closure after the fixes reach main. See
[qualification and measurements](zig-native/RUNTIME_BOUNDARIES_QUALIFICATION.md).

#28, #32, #33, #35 and #36 remain separate open design, representation and
measurement work. The existing #25/#27 programs also remain open. The original
triage below records the baseline before these repairs.

## Initial assessment, 25 October 2026

At initial triage, eleven issues were open: existing #25 and #27, plus nine
runtime performance, measurement and memory-contract reports (#28–#36). The
initial recommendation was to keep all eleven open pending implemented fixes.
The new reports describe distinct boundaries; none of this investigation
establishes a correctness failure or requires a language syntax change. The
first repair should be **#31**, followed by the construction and call boundaries
in **#30 and #29**. A small first slice of **#36** should support the ownership
and cycle investigations without blocking those concrete fixes.

This assessment includes source review and 28 executed cases on the qualified
[CT116 release compiler](zig-native/CT116_QUALIFICATION.md), SHA-256
`ea9d15eaac5479c0697c1dc40834475f4a713801b085ecd43692892609c4fe82`. The reports
use a different local compiler pin, `af349b1e…`; these are reconstructed public
examples, not exact reporter-source replays. The current unqualified
`owned_arrays` changes are preserved and excluded. No GitHub issue, comment,
label or state was changed.

P1 below means the next performance work batch; P2 means planned work or a
design decision. These are proposed priorities, not repository labels.

| Issue                                                                               | Assessment                                                                                                                                           | Priority and next deliverable                                                                                                          |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| [25: tasks, channels and scoped exits](https://github.com/mewhhaha/blot2/issues/25) | Existing language/runtime roadmap; partially implemented, still broader than one repair.                                                             | P2 roadmap. Use the existing completion plan to separate remaining scoped exits, channels/select, purity and worker transport.         |
| [27: compilation memory and edits](https://github.com/mewhhaha/blot2/issues/27)     | Keep open. CT116 improves fresh checking, but ordinary edits and attribution of the historical application-start peak remain unresolved.             | P1 investigation. Continue the existing compiler/host measurement track; do not introduce another cache system.                        |
| [28: collector-free memory contract](https://github.com/mewhhaha/blot2/issues/28)   | Design and documentation work. Production tracing removal does not imply absence of trial-deletion cycle collection.                                 | P2 design. Define the property and its boundary across calls, closures and demands before promising enforcement.                       |
| [29: runtime-selected numeric calls](https://github.com/mewhhaha/blot2/issues/29)   | Reproduced: 400,000 extra object retirements for 200,000 selected-reader calls.                                                                      | P1 repair. Prove an unboxed internal call path or a borrowed row lifetime; retain owned materialization on escape.                     |
| [30: destination construction](https://github.com/mewhhaha/blot2/issues/30)         | Partially reproduced: nine-field construction retires 4,001 objects, but the two-field Pair example retires only one on CT116.                       | P1 repair with narrower scope. Pin the wide-row producer boundary and retain the already-good Pair cases as controls.                  |
| [31: indexed projections and scopes](https://github.com/mewhhaha/blot2/issues/31)   | Reproduced in counters and final optimized Wasm: unused field loads and per-item ownership scopes survive.                                           | P1, first fix. Lower the checked scalar projection directly and extend the existing empty-scope proof.                                 |
| [32: inline bounded variants](https://github.com/mewhhaha/blot2/issues/32)          | Reproduced: all-present optional Pair arrays retire 6,001 objects versus one for the flat control. Source explicitly declines multiple constructors. | P2 representation work. Start with bounded reference-free sums and mixed-constructor cases.                                            |
| [33: fuse record pipelines](https://github.com/mewhhaha/blot2/issues/33)            | Reproduced: the record/map/flatten pipeline retires 6,005 objects versus one for direct generation.                                                  | P2 optimization. Extend existing exact-builder and row-fusion proofs through the record boundary.                                      |
| [34: reference-array scratch](https://github.com/mewhhaha/blot2/issues/34)          | Reproduced: roughly two million retains and two million releases; zero cycle scans. This is separate from #35.                                       | P1 ownership optimization. Eliminate the single-use scratch or prove borrowing from a surviving owner.                                 |
| [35: remaining cycle scans](https://github.com/mewhhaha/blot2/issues/35)            | Credible application report, not independently replayed here. Zero reclaimed bytes alone does not prove collection unnecessary.                      | P1 investigation. Identify candidate layouts/admission reasons and obtain a standalone reduction before changing proofs or scheduling. |
| [36: executed cost attribution](https://github.com/mewhhaha/blot2/issues/36)        | Confirmed tooling gap: current allocation remarks describe emitted candidates, omit helper allocations and do not measure executed traffic.          | P1 enabling work. Add opt-in attribution that reconciles with runtime totals and preserves source identity through optimization.       |

### Executed evidence

All 28 cases passed independent checksum expectations and returned to zero
ownership roots and leases. Production runtime counters were read directly;
generated bodies were not patched. Each counter measurement follows three warm
calls. Nine additional sequential samples provide a diagnostic screen only, not
alternating performance qualification. The engine was Deno 2.9.7 / V8
15.0.245.2-rusty. Compiler, source, client and standard-library hashes were
checked before and after execution.

| Case                                                         | Object retirements per invocation | Interpretation                                                                                         |
| ------------------------------------------------------------ | --------------------------------: | ------------------------------------------------------------------------------------------------------ |
| Nine-field rows, direct iteration, 2,000 rows × 100 passes   |                             4,001 | Construction cost remains; scanning adds no retirements.                                               |
| Same rows, runtime-selected reader                           |                           404,001 | Exactly 400,000 extra retirements at the callback boundary. The 101-pass alternate branch also passes. |
| Same rows, indexed scalar reads                              |                             4,001 | The indexed penalty is not extra allocation.                                                           |
| Two-field nominal Pair generation, 2,000 rows                |                                 1 | Both a fixed count and a runtime count pass; the structural control also retires one.                  |
| Nine-field nominal generation, 2,000 rows                    |                             4,001 | The wide producer still has linear temporary-object work. At 32 rows it retires 65 objects.            |
| Optional Pair generation, 2,000 present rows                 |                             6,001 | Flat presence/value control: one. This reconstruction differs by one from the reported 6,002.          |
| Nominal command → lanes → flatten, 2,000 × 24 values         |                             6,005 | Direct flat generation: one.                                                                           |
| Closure-array scratch, 512 saved closures × 2,000 iterations |                             6,513 | 2,052,512 retains and 2,059,025 releases; numeric control: 2,000 retains and 6,001 releases.           |

Every case records zero cycle passes, visited vertices and cycle-reclaimed
bytes. That separates the reproduced costs from cycle traversal; it does not
reproduce or disprove #35's application-level observation. Retirements count
destroyed objects, not bytes, peak live memory, or emitted allocation sites.

Disassembly of the exact optimized output confirms #31 independently. The
`indexed` entry reaches function 41, whose inner loop loads all nine row words,
discards eight, and calls the root-open/root-close helpers (functions 19/20).
The `direct` entry reaches function 0, whose scan loads only the selected field
and has no per-item root frame. Both still share the expensive construction
path. Diagnostic medians were 2.247 ms indexed and 0.265 ms direct; these are
local screening figures, not the issue's 31-sample benchmark or a qualified
speedup forecast.

The
[portable evidence archive](zig-native/measurements/issue-triage-2026-10-25.tar.gz)
contains the issue snapshots, complete runner/source, checksums, counter deltas,
raw timing samples, exact Wasm and disassembly, and reproduction instructions.
Its ten files occupy 56,325 compressed bytes; archive SHA-256 is
`bd390c96e9f1db29daa654f1cdf557569c59ecab54b152e264fa2f62d4e8c0a4`. All nine
payload hashes in its manifest were verified.

### Implementation boundaries and order

1. **Repair #31 first.** It has a small, visible target in the final executable.
   Reuse `backend_emission.zig`'s row projection path and
   `empty_root_scopes.zig`; retain bounds traps and evaluation order. Check
   empty-scope elimination after allocation-removing transformations. Do not
   simply suppress all root frames.
2. **Treat #30 and #29 as related but independently measurable boundaries.**
   Construction needs a producer that writes an admitted row directly into
   storage, or returns an unboxed value. Selected calls need compatible argument
   and result conventions or a proved borrow. Raising blanket inlining limits
   would not establish either contract. Include imported producers, escaped
   values, saved snapshots and F32 bit identity. The two-field #30 claim needs
   the reporter's exact source/compiler combination before calling it current.
3. **Implement a bounded #36 attribution slice, then address #34 and reduce
   #35.** Start with stable source/layout identity for surviving allocations,
   helper traffic and cycle admission reasons. Reconcile totals with existing
   counters, measure instrumentation overhead separately, and keep instrumented
   runs out of scored runtime comparisons. Reference-array scratch needs a
   lifetime proof across aliases, captures and suspension. Current unqualified
   `owned_arrays` edits concern exclusive branch consumers and fresh
   slice/concat buffers; they do not establish a fix for the scratch fixture.
4. **Extend representation and fusion proofs for #32/#33.** `numeric_rows.zig`
   deliberately admits one closed constructor; bounded sums need explicit
   tag/payload rules, including unequal payloads and inactive fields. Reuse the
   existing exact/ragged builders and row fusion for pipelines. Preserve
   observed intermediates, effects and trap order. Measure runtime, generated
   size and compiler cost together.
5. **Resolve #28's contract independently of safe local optimizations.**
   [The current production audit](zig-native/TRACING_REPLACEMENT.md) says
   incomplete ownership diagnoses rather than choosing a tracer, while counted
   edges, leases and trial deletion remain. Dated lower sections still describe
   earlier tracing states and should be clearly marked historical. Existing
   State/demand/closure tests require real strong cycles and memo identity.
   Define whether collector-free is a checked property, an explicit mode, or a
   restriction before changing those semantics. Keep it distinct from
   allocation-free. Any syntax change still needs the user's consultation.

The existing semantic suites already cover packed rows, numeric bit identity,
empty scopes, exact/ragged builders, row fusion, cyclic ownership and
suspension. Add the demonstrated boundaries to those families when implementing
repairs, then run the required compiler gate. This triage changes no compiler
code and does not qualify the combined dirty working tree.

### Existing tracks and duplicate decisions

**#26 remains closed.** Its
[closing record](https://github.com/mewhhaha/blot2/issues/26) explicitly leaves
unknown callbacks and escaped values on the boxed ABI. The new construction,
call, indexing, variant and pipeline reports are legitimate follow-ups, not
grounds to reopen or duplicate that issue. #35 likewise explicitly builds on the
completed plain-data proof from #16. #36 extends the existing
[allocation-cost report](zig-native/ALLOCATION_COST_QUALIFICATION.md) from #17;
it does not need a competing diagnostics framework.

**#27 remains an active compiler/host track.** CT116's unprofiled screen gives
7.050 s fresh compilation, 3.234 s literal edits and 5.556 s body edits, with
491.8 MiB fresh compiler peak RSS. Profiled checking is down to 0.649 s, while
backend work is about 5.68 s. These measurements do not attribute the historical
5 GiB application-start peak to Blot, and do not establish bounded memory for
every long retained session. Preserve separate compiler, Wasmtime loading and
application-start measurements; retain the full edit/recovery matrix.

**#25 remains a roadmap.** Partial task/region support is not completion of the
channel, scoped-exit, purity and worker-transport program. Use
[FINISH_PLAN.md](FINISH_PLAN.md) for its existing dependencies; the new runtime
repairs need not wait for that entire language program.

## Historical triage: issues 26 and 27, 23 October 2026

The dated assessment below is preserved as history. In particular, its advice to
keep #26 open and its description of supported layouts are superseded by #26's
closure and the current assessment above.

23 October 2026. Read-only triage against Blot main `93bc8d4`, Ink main
`1a291a1`, and gdev main `809b0c5`. No new runtime benchmark was performed, and
no GitHub issue, label, or state was changed.

| Issue                                                                                | Verdict                                                                                                                                           | Recommended priority | First deliverable                                                                                                   |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------- |
| [26: nested numeric layouts](https://github.com/mewhhaha/blot2/issues/26)            | Keep open; a representation/performance enhancement with a demonstrated implementation boundary, but no current end-to-end regression established | P2                   | A small executed comparison of nested/flat, structural/nominal values across the relevant call and array boundaries |
| [27: compilation memory and edit costs](https://github.com/mewhhaha/blot2/issues/27) | Keep open; prioritize attribution, with implementation ownership determined by the measured phase                                                 | P1 investigation     | Separate Blot compilation from uncached/cached Wasmtime module compilation and host loading                         |

### Issue 26

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

### Issue 27

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

### Effect on the completion plan

Preserve and reconcile the existing candidate before making overlapping compiler
changes. Then investigate #27's cold-start attribution first and run #26's small
representation matrix alongside the common baseline. Use those results to order
implementations. Neither issue requires completing #25's new task/channel
language features first.

Do not close either issue from this triage. Both have useful, distinct work;
their first steps are evidence gathering rather than a predetermined rewrite.
