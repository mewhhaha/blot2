# Retained native memory diagnosis (2026-09-21)

The large incremental-session memory growth is primarily a native
code-generation leak in pinned Bend 2.0.21, not an expanding compiler cache or a
parallel race. This investigation changes no production compiler, runtime, or
toolchain code. Instrumentation and causal controls remain in ignored `build/`.

The [standalone list-identity reproducer](repros/bend_boxing_leak/README.md)
reduces this to a 12-line pure core. One singleton Scalar loses exactly 16 bytes
per call after its result is consumed; the Pair control loses none. It includes
an identity law/proof and allocator-accounting verifier, confirmed on 2.0.21 and
2.0.24 without importing any Blot compiler code.

## Upstream release and issue check (2026-09-21)

**The leak is not fixed in Bend 2.0.24.** The latest published
[release](https://github.com/bendlang/bend/releases/tag/v2.0.24) was tested
using its official Linux x64 binary, extracted under
`build/bend-2.0.24-6n19s2/`. The archive matches the published SHA-256
`a05c1b5ecab1393f3dd5d67fedbeb83d5dd244c4187c7b36378b6a67a719ac2a`. The
installed toolchain and repository pin remain at 2.0.21.

The unchanged compiler sources build with 2.0.24. Applying only the same
allocation-accounting instrumentation, the eight-core 200-edit test produces
**identical in-use byte counts at all 207 request boundaries** to 2.0.21,
including **106.47 MiB left allocated after replacing the session**. Both
complete revision artifacts match the 2.0.21 baseline exactly. Native RSS at
edit 200 is 191.61 MiB in this diagnostic run; RSS includes other runtime
storage and should not be confused with the identical leaked-byte count.
[2.0.24 measurements](../build/memory-bend-2.0.24-8-200.json).

The branch-unsafe `val_box` implementation remains in the
[2.0.24 emitter](https://github.com/bendlang/bend/blob/v2.0.24/bend2/comp.ts)
and in inspected upstream `main` at
[`e52cda47`](https://github.com/bendlang/bend/blob/e52cda47a58967aa65d1eb26efe8f42a0b0407df/bend2/comp.ts).
The release notes describe checker literal-memory improvements and a GPU
continuation fix, not this generated-program allocation leak.

GitHub searches across open and closed issues/PRs for `val_box`, `spares`,
`boxing`, `leak`, `memory leak`, and allocation reuse found no matching report.
The complete open issue/PR listing was also inspected. Related-looking
[PR #955](https://github.com/bendlang/bend/pull/955) changes conditional-block
formatting, not spare ownership; older boxing fixes in PRs #854/#855 concern
different defects. This is a search result, not proof that no report exists
under other terminology. No issue or PR was posted.

## Reproduction and allocation accounting

The public native incremental API alternated the two Balanced 64 source
revisions for 200 edits, on one and eight pinned CPU cores. Each revision's
complete artifact was checked against its first result. After edit 200, five
`open` requests replaced the session with an empty one, in the same native
process.

A diagnostic binary compiled from the current worktree records accounting at
`NativeIO.receive`, after the previous response and drained-queue reset, while
the CPU worker pool is joined. It counts:

- Heap extent from Bend's `H_BUMP`.
- Free words in every size-class bank and every host lane's hot/cold free lists.
- In-use words as heap extent minus those free words. This includes live objects
  and leaked allocations, not just reachable state; the initial reserved page
  and small IO continuation also remain in this total.
- Native process RSS from `/proc/self/statm`.

The exact in-use totals are identical at one and eight cores:

| Boundary         | In-use heap |
| :--------------- | ----------: |
| Empty session    | 1,296 bytes |
| Edit 1           |   20.68 MiB |
| Edit 50          |   46.78 MiB |
| Edit 100         |   73.40 MiB |
| Edit 200         |  126.64 MiB |
| Session replaced |  106.47 MiB |

Replacing the session releases **20.17 MiB** of actual session state, but leaves
**106.47 MiB** allocated. Further empty opens do not release it. Once warmed,
each edit adds approximately **558,208 bytes (545.125 KiB)**; the two
alternating revisions differ by a few bytes. All accumulated leakage is in the
16-byte allocation class. This is not just freed memory waiting in allocator
lists.

At eight cores, edit 200 has approximately 152.63 MiB of heap extent: 126.64 MiB
in use and 25.99 MiB already free. Total native RSS is 176.71 MiB. One-core RSS
is 156.38 MiB, with less allocator retention, but the exact same leaked-byte
count. Parallel allocation increases the footprint; it does not cause this
deterministic leak.

[One-core accounting](../build/memory-diagnosis-1-200.json),
[eight-core accounting](../build/memory-diagnosis-8-200.json).

## Root cause: branch-unsafe reuse of consumed node storage

Allocation-site tracking narrowed the dominant leak to temporary worklist cells
used by `native_cache_keys.flatten`, particularly serialization of runtime
bodies for codegen cache keys. These cells are not retained cache entries. Even
cache hits need key construction, so unchanged functions contribute on every
edit.

The generated C does the following when consuming `Field{value} <> tail`:

1. `ctr_take` consumes the list cell and returns its storage as `sp_0`.
2. The flattened `R.Work` value is boxed through a conditional chain.
3. Only the `CheckedLength` branch reuses `sp_0` for its two-field constructor.
4. Other branches, including common `Word` and `Text` cases, neither reuse nor
   free `sp_0`. The output list allocates another cell, and the consumed cell is
   lost.

The matching pinned emitter source explains why. `ctr_build` removes a reusable
allocation from `fl.spares`; `val_box` emits multiple mutually exclusive
branches using the same mutable spare list. Emitting one branch consumes a spare
in the compiler's bookkeeping even though that branch may not run. Unlike the
ordinary match emitter, boxing does not isolate the spare state by branch and
reconcile unused allocations. Relevant cached upstream source is
`generated/compiler/bend-2.0.21/comp.ts`, functions `ctr_build`, `val_box`, and
`emit_match`'s branch handling.

The resulting orphan cells even contain stale references to payloads already
freed correctly. This is lost container storage, not a growing history of
reachable revisions. Allocation-site attribution after dropping a 20-edit
session is saved in [the site report](../build/memory-sites-117146-22.txt).

## Causal control, not a production fix

A second diagnostic binary changes only this generated-C branch: free the
consumed list cell before boxing, and disable its conditional reuse in the
`CheckedLength` arm. It does not clear caches, reset the heap, restart the
process, or trim allocator pages. Accounting instrumentation is otherwise the
same.

| Eight-core measurement                |   Original | Local control |
| :------------------------------------ | ---------: | ------------: |
| Native RSS, edit 200                  | 176.71 MiB |     70.68 MiB |
| In-use heap, edit 200                 | 126.64 MiB |     20.36 MiB |
| In-use heap after session replacement | 106.47 MiB |     0.197 MiB |
| Steady leaked bytes per edit          |   ~545 KiB |         1 KiB |

This removes **over 99.8%** of leaked bytes. The full artifacts for both
revisions match the unmodified binary exactly, and every repeated revision
matches within each run. The remaining roughly 1 KiB/edit is still real growth;
the control does not establish a leak-free long-term plateau. RSS remaining
above live state also includes freed allocator storage and non-heap runtime
mappings.

[Control accounting](../build/memory-control-8-200.json),
[unmodified artifact-parity control](../build/memory-baseline-parity-8-20.json).

### The remaining 1 KiB/edit

Repeating allocation-site tracking on the first control leaves exactly 1,280
orphaned 16-byte cells after 20 edits: **64 cells per edit**. Their allocation
site is `Map.values_go`, whose temporary list enumerates the 64 globals for
scope-key serialization. The cells are consumed by `flatten`'s `Globals` arm.
There, a second boxing chain reserves `sp_22` only for the `OperationGlobal`
branch. The ordinary function-name branch constructs a `Field` instead and loses
that spare. This is the same branch-bookkeeping defect, not a separate
cache-retention mechanism.

[Residual allocation sites](../build/memory-sites-118201-22.txt).

A final generated-C control corrects both sites. Across another 200 eight-core
edits, warmed in-use heap stays constant for each alternating revision, at
approximately **20.17 MiB**. Replacing the session returns in-use accounting to
exactly **1,296 bytes**, identical to the initial empty session. Both complete
revision artifacts again match the unmodified binary. Thus these two sites
account for **all observed leaked allocations in this workload**.

Final native RSS is **70.64 MiB**, versus 176.71 MiB originally. RSS still rises
from 68.64 to 70.64 MiB between edits 100 and 200 despite constant live state:
that residual growth is allocator retention, not continuing object leakage in
this test. The result does not prove a global memory bound for other programs or
exclude other instances of this emitter defect.

[Two-site control accounting](../build/memory-scope-control-8-200.json).

## Reproduction files and verification

Diagnostic scripts:

- `build/memory_diagnosis_instrument.ts`: heap/free-list accounting.
- `build/memory_diagnosis_sites.ts`: outstanding 16-byte allocation sites.
- `build/memory_diagnosis_control.ts`: isolated generated-C causal intervention.
- `build/memory_diagnosis_scope_control.ts`: second boxing-site intervention.
- `build/memory_diagnosis.ts`: repeated public edits, artifact checks, and
  resets.

The diagnostic scripts pass `deno check`. Diagnostic native binaries compile.
The one/eight-core original runs and both eight-core causal controls each
complete 200 edits; allocation-site controls use 20 edits. Site instrumentation
adds its own memory overhead and is not used for the headline RSS comparison.
These are diagnostic measurements, not performance benchmarks: the desktop
remained active, and instrumentation/compilation flags differ from production.

The appropriate durable repair is branch-correct storage reuse in Bend's C
emitter, with a minimal ownership/allocation regression and retained-session
checks. A Blot-level workaround is also possible, but allocator trimming or
cache eviction alone cannot recover these orphaned allocations. No production
repair or upstream change has been applied by this investigation.
