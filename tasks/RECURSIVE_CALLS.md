# Recursive calls in the owned-storage backend

Status: First slice implemented and measured; full compiler qualification
remains pending on reproduced baseline failures. Reviewed with Astra (xhigh)
against clean `8ff1e17696ee19fa54ee71e15ea5454f666971b2` on 2026-11-04, followed
by two implementation reviews. This advances
[task 110](110-plan-owned-storage-and-specialized-calls.md); it does not
complete that task or the owned-storage rewrite.

## Outcome and first boundary

Compile and execute the unchanged Goose comparison ports
[`sort_merge.blot`](../scripts/bench/goose/ports/sort_merge.blot) and
[`sort_quick.blot`](../scripts/bench/goose/ports/sort_quick.blot), then replace
their unsupported chart cells with checked measurements.

First admit direct self-recursion in closed, fully applied named functions: U32
scalar bounds, existing fixed `Array U32` inputs and Unit results. Permit scalar
operations, branches, loops, indexed reads/writes and compatible nonrecursive
helpers. Both original sorting algorithms fit this boundary; benchmark
entrypoints may allocate their arrays outside the recursive component.

Require live input owners and proof that their existing rows are initialized.
Keep semantic owner alias correlation and the same formal-owner correspondence
on every self-edge. Unknown initialization receives no new authority; explicitly
prove any vacuous empty-owner case. Empty ranges over valid owners remain
covered.

Recursive components and their reached helpers initially exclude owner
allocation/transfer, resize/reserve/shrink/freeze, borrowed or aggregate
results, implicit global owners, host suspension, demands, indirect/closure
backedges, changing specialization and mutual recursion. Preserve their
diagnostics. These are admission boundaries, not claims that general recursion
is implemented.

## 1. Define the component and freeze its interface

Use a bounded selected-call discovery/admission walk over checked Core. Classify
a singleton self-recursive component before committed machine emission. Reuse
existing source validation and call identity; frontend recursive inference is
already implemented under task 007. No new whole-program IR or general summary
solver is needed for this slice.

Reserve an ordinary Wasm header with complete i32 parameters: ten words for
`merge_sort_helper`, six for `quick_sort`, plus the existing Unit return word.
Disable addressed/packed transport, physical input-word sharing and post-body
parameter narrowing for these headers. Recursive calls must keep a fixed ABI.

Recursive identity retains source, selected type/effect context and normalized
semantic owner roles/alias partition. Omit the ordinary physical input-word
alias partition as well: initially equal bounds or descriptor words can become
independent locals inside a callee. Runtime bounds, lengths, tokens, addresses
and local IDs never become specialization keys. Optional literal/empty-value
hints must not manufacture new recursive specializations. Erase any omitted
caller-specific literal, empty or span facts from the provisional formals too; a
shared body may use only facts guaranteed by its recursive contract.

**Gate:** a compact admitted/rejected source matrix proves this boundary and
stable identity before broadening emission. Track discovery work, header count,
backedges and explicit decline reasons; runtime input size must not cause a
compile-time unrolling or specialization tree.

## 2. Prove a finite owner-access contract

Distinguish ordinary ordered access events from a checked invariant plain-owner
contract in `CheckedFunctionPlan`. The latter retains immutable U32 row facts
and a finite read/write footprint per canonical input owner.

Collect the footprint from actual body operations and completed compatible
nonrecursive callees. Under unchanged formal-owner correspondence, self-edges
introduce no new roles or row shapes. Complete this finite footprint before
emitting any recursive backedge or publishing the plan. Preserve unused-argument
behavior; do not invent reads/writes or recursively expand an infinite ordered
event sequence.

Every reached operation must preserve owner identity, row shape, lifetime,
capacity and cleanup obligations. Replay real reads into enclosing loop checks.
Possible writes may invalidate optional value facts; they never prove definite
initialization or nonempty storage. When an ordinary caller has a `WriterTrace`,
feed it the checked finite invariant replay; never expose an unfinished summary.
Keep existing Core/type checks, `storedShape`, frozen-owner checks and alias
evidence.

**Gate:** native laws cover unused inputs, aliased/distinct arrays, loop read
facts, unknown initialization and every excluded shape/lifetime operation. An
in-progress contract is a private induction hypothesis until its complete body
satisfies it.

## 3. Connect backedges and publish transactionally

Reuse the existing building-entry cache with an explicit provisional recursive
header. The audited backedge path precedes `invokeBody`'s general active-call
rejection, and may resolve only the matching header in its owning construction
transaction. `getOrBuildFunctionPlan` must retain rejection for arbitrary
unfinished entries and unsupported cycles.

Generate one ordinary Wasm function and runtime self-calls. Input owners stay
outside cleanup. Prove that the recursive component's transitive guest scratch
requirements are empty; remove empty mark/rewind work. Unit results avoid a new
result-storage or global return-bank proof in this slice.

Extend `FunctionMark` and cache rollback to remove provisional headers,
functions, summaries, aliases, committed counters and dependent unpublished
helpers. Reserve publication capacity first. Publish completion/context-free
aliases only after every prerequisite succeeds; OOM or failed admission leaves
nothing executable behind.

`wasm_scope_outline.finalize` now proves bank safety over machine-call strongly
connected components. Ordinary recursive components may be reached below a
banked caller when disjoint from its root and extracted helpers. A cyclic
component containing any bank member, or any reachable indirect call, still
rejects publication. This implements the stronger disjoint-component option from
the review, avoiding the proposed initial caller extraction fallback. The
forced-outline execution witness keeps live caller values across ordinary
recursive calls; separate machine laws reject bank reentry and unknown dispatch.

**Gate:** executed self-recursion works in both codegen tiers; forced outlining
thresholds preserve caller locals or produce the intended bounded rejection. No
bank reentry or unknown-indirect path receives provisional authority.

## 4. Run compact semantic and scaling witnesses

Keep the family in native laws and executed Wasm, registered in
`scripts/dev_check_areas.ts`. Cover:

- Both recursive branches; caller scalars and array descriptors survive nested
  calls. Test sorted, reverse, duplicate and randomized arrays, quicksort empty
  and singleton ranges, and merge singleton/nonempty ranges.
- Equal scalar arguments becoming unequal, owner aliases versus independent
  owners, unused frozen-ABI parameters, multiple calls and repeated exports.
- Runtime depth beyond 128 without compile-time depth expansion; fixed helper
  count across runtime input sizes. Keep compiler work bounds separate from
  Wasm/host runtime-stack limits.
- Invalid mutual/closure cycles, owner allocation/escape, changing role mapping,
  resize/freeze, uninitialized reads and hidden storage effects in callees.
- Failure/OOM during reservation, nested checking and publication; same-session
  correction and retry. Trap followed by another invocation; no owner/scratch
  growth across successful repeated calls.
- A recursive helper below a forced outline-bank caller, plus actual bank
  reentry and unknown-indirect negative controls.

**Gate:** compile the complete native inventory without LLVM; pass the affected
family, meaningful allocation-failure sweeps, executed guests and zero Zig lint
findings. Provisional headers never survive failed builds or retained edits.

## 5. Qualify the unchanged benchmarks and checkpoint

Use Zig 0.17.0, native `-Dllvm=false` development builds and installed-test
runtime selection. Start with `deno task check:dev --area scoped-storage`; add
the new laws. Keep the normal development cycle below five minutes. Tiny
witnesses come before game builds; retain the 30-second cap on individual
diagnostics.

Once the first four gates pass, build one meaningful LLVM release candidate. Run
the existing Goose harness for both sorts with official 100,000/400,000 input
sizes, independent checksums and recorded bounded iteration/warmup counts. Use
at least five fresh compile samples and five warmed runtime samples for a
performance ranking. Keep the original recursive algorithms, preparation,
per-run copies and RNG/checksum semantics. Timeouts remain incomplete results.

Record source/compiler/toolchain hashes, Wasm bytes, compiler phase/work counts,
function count, runtime distributions and memory. Update the README charts only
after both ports qualify. Keep original F64 coverage explicit. Compare the
existing numeric kernels and a freshly paired Gdev control; avoid extrapolating
sort results to Main. Recheck affected integration and inspect the real frame.

Run `deno task test:compiler` and `deno task lint:zig` before compiler
checkpoints; full-suite budget exhaustion is not a pass. Commit/push checked
batches and verify remote main. No LLVM build is needed for this planning
checkpoint.

## Implemented checkpoint — 2026-11-04

The unchanged merge-sort and quicksort ports pass checksum/revision
qualification at official 100,000/400,000 sizes. Five fresh cold compilations
take 51.00/52.74ms including startup; output is 6,741/6,244B. Each has exactly
one recursive definition and two runtime self-call sites. Their full direct
headers retain ten/six inputs. Five bounded runtime pairs show 2.54x/1.51x gaps
against Goose; these are reduced repetition counts, not official production
scores.

All 2,983 native laws compile without LLVM; 419 affected laws pass sampled
faults. Seven new laws pass full-fault mode, including three exhaustive sweeps.
The registered development family passes in 53.1s, with 252 native laws, 242
guest tests, formatting, types and zero Zig lint findings. All 24 recursive
guests pass both codegen tiers. The frame is freshly executed and inspected.
Main remains byte-identical; paired compilation moves 5.615 → 5.732s, so this is
no Main speed or size improvement.

Full qualification remains pending: two release guest failures reproduce on the
frozen compiler, and the full gate stops after 200 native passes on a frontend
primitive-arity diagnostic failure also reproduced on the frozen source
snapshot. The unchanged broader suite has not passed. Exact
compiler/source/toolchain, work, phase, memory, sample, OOM and failure records
are in the
[checkpoint evidence](../scripts/bench/goose/results/2026-11-04-recursive-calls.md).

## Later extensions, with separate acceptance gates

1. Scalar results with the same invariant-owner contract.
2. Mutual SCCs: reserve every header, solve the finite footprint and publish the
   group atomically. The singleton slice must not claim mutual support.
3. Aggregate/input-borrow results, with result provenance and eager-drain laws.
4. Bounded polymorphic/static-callback specializations.

Shape-changing ownership needs a finite summary domain and bounded fixed-point
proof. Arbitrary ordered-event unrolling cannot provide it. Recursive owning
results and growable scratch remain outside task 110's initial contract.

Main's control-boundary copy-coalescing hill remains a separate performance
experiment. Supporting these sorts does not establish the subsecond or 1–2MB
Gdev targets.
