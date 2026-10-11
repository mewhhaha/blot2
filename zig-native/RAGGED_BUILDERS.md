# Ragged builders: counting without observable replay

This is the design for [task 043](../tasks/043-implement-ragged-builders.md),
specified by [task 042](../tasks/042-specify-ragged-builders.md). It does not
claim an implemented ragged fast path. The baseline is `d9172ec`.

The [guide](../compiler/guide.md) defines source behavior. The
[ownership contract](CONTRACT.md), [runtime layouts](src/runtime_layout.zig),
[packed rows](src/packed_layout.zig) and [list runtime](src/list_runtime.zig)
remain authoritative. There is no new collection representation, public API,
diagnostic, iteration order or source-level mutability.

## Decision

Count selected elements, allocate their final storage, then fill in source
order. Duplicate only control expressions proved pure, total, deterministic and
allocation-free. The initial implementation also requires a pure, total,
allocation-free payload. Unsupported totality is a decline, including a pure
function with unknown termination or traps. Effect operations, demand
forcing/creation, callable creation/invocation, provider/control boundaries and
intermediate builder observations keep ordinary construction.

This deliberately gives task 043 a smaller admission than a general two-pass
builder. It extends [exact_builder](src/exact_builder.zig) to dependent bounds
and filters; it does not widen the existing rectangular path's payload rules.
The [indexed evaluator proof](src/eval_indexed_builder.zig) supplies the private
buffer ownership model, not permission to mutate published constant values.

Typechecking and dispatch resolution still inspect the complete body, including
zero-iteration and always-false branches. Counting is an optional implementation
proof after checking, never a way to erase an invalid source expression.

## Admission

Recognize checked Core operations, not source names or bracket spelling. Both
handwritten loops and lowered comprehensions must satisfy the same proof:

- One empty private List, one append site, and a final return of its successor,
  optionally converted to Array. Each selected leaf appends exactly one element;
  each rejected leaf leaves the builder unchanged.
- A finite nest of at most four U32 ranges or immutable Array/List traversals.
  Earlier loop binders and qualifier locals may feed later bounds and guards.
  Sources are existing immutable collection references, not newly constructed
  collections. Irrefutable element patterns may bind existing values.
- Only the builder crosses backedges. Qualifier locals are immutable and scoped
  as in the guide. No mutable scalar recurrence, `break`, early `return`,
  request loop, arbitrary iterator protocol, extra append site or recursive
  traversal.
- Every builder alias is accounted for through binds, loop carries and branch
  merges. It is used only as the append receiver, unchanged guard successor or
  final result. No length read, projection, capture, comparison, callback
  argument or intermediate publication is allowed, even if later discarded.
- Bounds, guard/qualifier expressions and payload use the expression subset
  below. All captures are immutable checked values established before region
  entry; no capture or source can reach the private builder.

The initial expression subset consists of constants, immutable value references,
known primitive scalar operations, short-circuit Bool operations, scalar
conditionals, qualifier binds, checked immutable field projections and intrinsic
collection length. Operands must themselves qualify. Only checked primitive
dispatch qualifies: overloaded source methods, named calls and indirect calls
decline. U32 addition, subtraction and multiplication retain wrapping source
arithmetic. Integer division/remainder, potentially trapping numeric
conversions, indexing, cursor value/advance, allocation and unknown operations
decline. Task 043 need not introduce a theorem prover for a nonzero divisor or
an in-bounds index.

A payload can copy an existing scalar or reference value, including a previously
constructed row. Constructing a tuple, record, closure or collection in the body
declines when it requires allocation. Layout evidence permits copying a packed
row; the machine type `i32` never proves that a word is pointer-free.

An inert copy of an existing owning reference remains eligible when its checked
layout and ownership proof are complete, even if reachable values include
closures, strong memo cells, shared children or cycles. Copying does not
traverse that graph or execute its latent behavior. Reading a demanded parameter
through an operation that forces it is not an inert copy and declines. Existing
provider frames retain the contract's restriction against entering source
values.

| Scenario                                                   | Initial decision                  | Reason                                          |
| ---------------------------------------------------------- | --------------------------------- | ----------------------------------------------- |
| Inner range `0..x`, with earlier U32 binder `x`            | Admit                             | Finite, total dependent control                 |
| Guard `x > 1`, then a scalar `let` qualifier               | Admit                             | Deterministic total filter                      |
| Traverse a captured immutable List or Array twice          | Admit                             | Snapshot and element order remain stable        |
| New inner collection, generic iterable, callback predicate | Ordinary                          | Allocation or unknown behavior                  |
| Pure predicate `10 / x > 1`                                | Ordinary                          | Purity does not exclude a trap                  |
| Pure recursive bound or payload                            | Ordinary                          | Termination is unproved                         |
| Effectful, trapping or allocating payload                  | Ordinary                          | Initial proof deliberately excludes it          |
| Read/capture an intermediate builder version               | Ordinary                          | Final storage cannot implement that observation |
| Source expression overflows U32 by wrapping                | Admit if otherwise eligible       | Source arithmetic is unchanged                  |
| Mathematical element count or storage size exceeds a limit | Ordinary                          | Sizing cannot introduce an early failure        |
| Empty outer range or all guards false                      | Admit if whole body checks/proves | No later runtime expressions execute            |

Proof storage is bounded: four generator slots, sixteen guards/qualifier binds,
sixteen builder aliases and 256 examined Core nodes per region. Exceeding any
limit declines. These are optimization limits, not additional language limits.
They may be reduced for testing and belong in counters/benchmark manifests.

## Counting and filling

Use one qualifier traversal definition with two modes, rather than separate
interpretations of source order. In count mode an accepted leaf increments a
mathematical counter; in fill mode it evaluates the payload once and writes the
next row. Both modes enter generators left to right, traverse elements in
ordinary order, evaluate bounds once per dynamic loop entry and honor guard
short circuit. Never hoist an inner bound across an empty outer loop or a false
earlier guard.

Counting does not evaluate the payload, append, convert the result, invoke a
callback or publish evaluator values. Qualifier bindings needed by later control
are recomputed in fill. A binding used only by the payload stays in fill.
Replaying eligible controls cannot change a value, trap, diverge or produce an
effect. Captured collections remain live through both passes; copying a
reference never changes its snapshot. No O(element-count) bitmap, offsets table,
saved payloads or materialized iterator is needed. Traversal scratch is
O(nesting depth), plus the fixed proof slots; a List cursor is private traversal
state, not a new source value.

Counting has a separate optional work budget: initially 1,048,576 control-node
visits per region invocation. Charge expression nodes and generator transitions,
including filtered and empty entries. Stop before executing work beyond this
budget. A terminal unfiltered range may count its cardinality with one checked
addition; it must still honor enclosing guards and bounds. Exhaustion returns
`declined`, releases count scratch and starts the ordinary builder from the
original entry bindings. No payload has run, so no observable body work is
duplicated. Fill and the ordinary fallback retain their ordinary language
execution limits; the extra pass cannot spend source fuel or change a source
diagnostic.

Use checked host-width or Wasm i64 arithmetic for counts and bytes; never use
the source's wrapping U32 operations for sizing. Validate the logical length,
row-word product, header addition, arena limits and list helper limits before
allocation. Use the same eligibility ceilings as the existing collection
implementation; today the exact runtime path caps Array counts at
`min(0x10000000, (maxU32 - 4) / stride)` and List counts at
`0x10000000 / max(1, row_words)`. Checked layouts determine `row_words` and
`stride`. Do not silently treat a wrapped count as zero or truncate a row.

Oversize, unsupported layout, insufficient staged budget or excessive count work
means ordinary construction, not an overflow diagnostic. The ordinary path can
then complete, reach its own resource limit, or fail at its original source
point. A zero count uses the normal empty representation; allocate no payload
buffer and execute no payload. Empty/all-filtered cases still count reached
controls, never unreachable subsequent qualifiers.

## Internal operations and owners

These are internal operation contracts, not required Zig names or a new public
builder object. Reuse existing traversal, storage and cleanup operations.

| Operation                                          | Result and obligation                                                                                                           |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `analyze(module, root, checked_layout)`            | Optional bounded `Plan`: Core IDs, aliases, ordered qualifiers, payload, result conversion and layout evidence                  |
| `count(plan, entry, probe_budget, storage_limits)` | `eligible { length, words, bytes }` or `declined`; no source failure or publication; existing scratch-allocation OOM propagates |
| `begin_private(layout, size)`                      | One private final-storage owner or the existing allocation failure; all reference slots are safe before any write               |
| `fill(plan, entry, private)`                       | Ordinary source-order traversal, payload evaluated once per selected leaf; monotonically advancing row index                    |
| `finish(private)`                                  | Verify written count equals counted length, freeze and transfer a complete immutable result                                     |
| `discard(private)`                                 | Allocation-free cleanup of only owned private storage; never release borrowed captured children                                 |

The plan borrows immutable Core only inside its compile owner. It stores no
solver IDs, source/frame pointers or scratch pointers in durable artifacts. Task
043 needs no new retained summary cache. If plans are retained later, complete
body, capture, dispatch/layout and transitive dependency validation must
authorize reuse just as for executable fragments. Changed bounds, filters and
payloads must rebuild even when the public function type stays unchanged.

Runtime count uses scalar locals and borrowed traversal bases. Array storage
uses the existing four-byte length header followed by checked-stride rows. A
reference Array must be cleared before filling; a scalar allocation is
authorized only by complete checked layout evidence. The length header can
contain the exact count while storage is private, but no external reference can
observe it before finish. Reference-bearing rows retain existing boxed elements;
flat scalar rows retain the production packed-row layout.

List output uses the existing six-word descriptor and balanced tree of
right-sized leaves/branches, sized once for the final word count. It is not a
single Array allocation disguised as a List. Leaf capacity is currently 248
words; row counts and word counts remain distinct, including rows crossing
leaves. Owner tokens stay scalar, every GC pointer stays an allocation base, and
unused/reference words stay zero. Use existing helpers; do not expose an
interior write cursor as a GC root or change the ABI. Empty Lists use the
existing immutable descriptor.

Attach allocation/borrow/transfer roles from checked layouts to resolved IR.
Private traversal scratch and final storage have separate owners and valid
cleanup edges. Partial tree allocation and failed fill must be discardable
without allocating. No alias may retain a partially filled descriptor. Finish
transfers the result once; discard releases each private allocation once.
Unsupported ownership proof declines before allocation. Allocation failure after
begin is a failure, never a retry through ordinary construction with a different
failure frontier. Physical OOM scheduling is not a stable source guarantee; task
043 must test failure cleanup and must not add a new early source-level trap.

Existing List traversal may own a bounded subtree stack and, for multi-word
rows, one two-row scalar buffer per nonempty loop activation. Reuse that
machinery and its cleanup, rather than requiring a new allocation-free List
traversal. Include these fixed buffers in count/fill allocation measurements.
They scale with active depth and checked row width, never with visited or
selected elements. Count scratch allocation failure follows the existing OOM
policy; it is not a sizing decline.

The staged evaluator needs a distinct adapter, not guest heap pointers. Count
uses raw scalar scratch and borrowed immutable `ValueId`s without publishing new
`ValueInfo`s, closures or child spans. It must not run the ordinary evaluator
and then roll back its diagnostics, frame mutations or retained caches.
Unsupported control execution in this scratch adapter declines.

Before staged fill, reserve one exact private buffer of `length` child handles
and account every reserved slot against `Options.max_children`, including other
live private reservations. Source payload evaluation keeps its ordinary frame,
steps, depth and scalar-value accounting. Suppressed append/conversion nodes
retain ordinary logical source-step charges; the prepass charges only the probe
budget. If this accounting cannot be preserved for a shape, decline. Copying
fewer collection children can improve storage-budget feasibility, as with
existing private collection optimizations; no previously successful source may
acquire a new count-pass `constant_fuel` failure.

The private carry is frame-qualified and cannot enter a snapshot, capture,
import template or semantic cache. At finish reserve publication capacity before
changing published metadata, copy/transfer the completed handles into one
immutable child span and publish the result once. A single final publication
copy is acceptable with current evaluator storage. On OOM, source failure or
ordinary fuel exhaustion, discard scratch and preserve the last successful
revision and all prior values. Never mutate a published span or use runtime
uniqueness as evaluator permission.

## Examples and traces

These source snippets are acceptance inputs for task 043, not executable
fixtures added by this documentation task. Values below follow current guide
semantics. For traces, `B` is bound evaluation, `G` a guard, `P` a payload, and
`A` an append. Those letters are explanatory events; eligibility ensures
repeated `B/G` events are unobservable. Effect and failure events are observable
and must stay exact.

```blot
entry const triangle = fn count => do:
  let result: List U32 = []
  for x in 0..count:
    for y in 0..x:
      result := [...self, x * 10 + y]
  return @array.from_list result

const selected = fn (values: Array U32) =>
  #[square | x <- values, x > 1, let square = x * x, square < 10]
const selected_at_compile_time = selected #[0, 1, 2, 3, 4]
```

`triangle 4` produces `#[10, 20, 21, 30, 31, 32]`; counts 0 and 1 produce an
empty Array. Ordinary traversal is outer `B`, inner `B(0)`, `B(1), P10,A`,
`B(2), P20,A,P21,A`, `B(3), P30,A,P31,A,P32,A`. Count walks the same entries
without `P/A` and obtains six. Fill repeats the bounds, evaluates the six
payloads in that order and writes six rows. The outer-empty case never enters an
inner bound. Size decline repeats only total bounds before ordinary execution.

`selected #[0,1,2,3,4]` produces `#[4,9]` both at runtime and compile time. Each
pass visits `x` in written order. For 0 and 1, the first guard prevents
evaluation of `square` and the later guard. For 2, 3 and 4 the later guard sees
4, 9 and 16. Count obtains two; fill evaluates the result expression only for 2
and 3. A replacement first guard `x > 9` yields empty output and evaluates
neither later qualifiers nor the payload. Returning a List instead preserves the
same order and values with the existing List representation.

These counterexamples must remain ordinary:

```blot
entry const trapping_guard = fn (values: Array U32) =>
  #[10 / x | x <- values, 1 / (x - 1) == 0]

entry const trapping_bound = fn () => do:
  let result: List U32 = []
  for x in 0..2:
    for y in 0..(1 / (1 - x)):
      result := [...self, 10 / x]
  return @array.from_list result

entry const effectful = fn (send: U32 -> U32 ! {Foreign}) => do:
  let result: List U32 = []
  for x in 0..3:
    use value <- send x
    result := [...self, value]
  return @array.from_list result

entry const observed = fn count => do:
  let result: List U32 = []
  for x in 0..count:
    result := [...self, result.length]
  return @array.from_list result
```

For `trapping_guard #[0,1]`, ordinary execution passes the first guard and traps
in payload `10 / 0`; it never evaluates the second guard. A speculative count
would instead trap in `1 / (1 - 1)`, changing the source failure. Both
expressions are pure. Requiring total controls and, initially, total payloads
rejects this case before either pass. In `trapping_bound ()`, the first inner
range has length one and payload `10 / 0` traps; counting ahead would instead
reach the second inner bound `1 / (1 - 1)`. Both examples decline before
counting.

`effectful` calls `send 0, send 1, send 2` once each before their appends. If
the second callback throws, no third call occurs; while it is suspended, no
third call occurs before resumption. Source allocation and handler/cancellation
behavior remain ordinary. Neither duplicating the body nor running later control
ahead of it is authorized. A payload that captures the current `result` also
declines, even when the closure appears unused. `observed 4` returns
`#[0,1,2,3]`; substituting final length would be incorrect.

A huge dependent range, all-false filter or mathematical count above the storage
ceiling may exhaust counting. There is no new error: restart the ordinary
builder before its first payload. An empty outer range suppresses even an
enormous inner range. U32 `x + 1` at `maxU32` wraps to zero in both passes; the
separate checked count never wraps. Native sizing tests must exercise exact
ceilings and one above without allocating enormous output; guest tests can lower
only private admission limits to exercise the same fallback branch.

## Task 043 acceptance and measurements

Record baseline/candidate revisions, Zig/Deno versions, probe/proof limits,
checked element layouts and raw trial data. Use a private test-only switch to
force the ordinary path; do not add a public optimization flag. Compare decoded
values and observable failure/effect traces, not Wasm byte equality. Approval
requires:

1. Native proof/count laws and executed-Wasm/runtime plus staged tests for
   dependent ranges, immutable Array/List generators, guards
   before/between/after generators, dependent qualifier locals, depths one
   through four, reversed ranges, empty inner/outer ranges, all-filtered results
   and U32 wrapping bounds. Include existing reference payloads, shared/cyclic
   children and previously constructed packed rows crossing List leaves. Compare
   List-to-Array conversion and direct Array results against forced ordinary
   output.
2. Rejection laws for every ordinary row in the admission table, including the
   trapping-guard failure location above, effect callbacks that throw/suspend,
   intermediate reads/captures, early exits, custom iterables, unknown dispatch,
   excessive proof size and exhausted probe work. Invalid payload typing under
   an empty range/false guard must retain its checker diagnostic.
   Pure-but-trapping and effectful examples must show zero direct ragged
   admissions.
3. Checked sizing tests for zero, ceiling, ceiling plus one, header/stride/word
   overflow and packed row-width limits. Failed/exhausted counts allocate no
   output and publish nothing; ordinary effects execute once after fallback.
   Staged low-step/depth/value/child-budget tests must add no prepass
   diagnostic.
4. Exhaustive native allocation-failure injection through proof preparation,
   traversal setup, staged reservation/publication and partial output ownership.
   Test guest allocator failure separately. No leaks, double release, unsafe
   reference slot or partial publication; prior aliases/snapshots survive. A
   failed retained edit followed by recovery matches fresh compilation. Change a
   bound, filter, capture and payload without changing the function type; each
   change must invalidate its executable construction.
5. Full compiler gate and zero Zig lint findings before the implementation
   milestone. Documentation checks alone qualify this design, not task 043.

Use triangular sizes `0, 1, 8, 32, 128, 256` and filtered Cartesian products
with 0%, roughly 50% and 100% selection. Record candidate visits `C`, selected
elements `K`, depth and row width separately: an all-filtered workload has `K=0`
but still costs O(C). Include cheap scalar payloads, existing reference copies,
two-/four-word rows, List and Array output, and a beyond-probe-budget fallback
case. Test the staged sizes within ordinary evaluation fuel rather than raising
language limits only for the candidate.

Measure construction CPU in warmed guest invocations separately from compile
CPU; consume results outside the timed construction region. Alternate
baseline/candidate for at least 15 pairs and report median and p90, counts,
requested bytes and peak live storage. Measure fresh compilation, first retained
edit, subsequent edit, no-op and failed-edit recovery separately; an unchanged
revision's frontend fast path is not evidence of builder reuse. Use at least
seven alternating compilation pairs. Report real allocation traffic, including
final publication copies and List metadata; do not call all removed appends
removed allocations.

The structural gates are zero intermediate growing-list allocations/copies for
an admitted Array, one output payload allocation, no per-element count-pass
allocation and O(depth) traversal scratch. Range/Array control needs no runtime
count heap; List control may use only the fixed traversal buffers described
above. List output allocates only its final descriptor, leaves/branches and
fixed traversal scratch; there is no temporary complete Array. For staged
output, selected-child writes plus at most one final publication copy are O(K),
with one exact private reservation and no append-version child copies. Peak
extra storage excludes borrowed inputs and includes scratch, unfinished output,
metadata and publication overlap. It must remain O(K * stride + depth) at
runtime and O(K + depth) child handles staged, with no hidden O(C) decision
tape.

CPU is O(C + K), with controls traversed at most twice on success, once in the
probe prefix plus once ordinarily on fallback. Require no median construction
regression above 10% on each large admitted case (`K >= 1,000`) and an
improvement of at least 10% in either construction CPU or peak live storage on a
declared large ragged workload; publish cases that trade CPU for fewer
allocations. Require fresh and retained-edit compiler medians within 5% or 2 ms
of baseline, whichever allows more time. Small/empty cases need the structural
gates and their measured fixed cost reported, not an invented speedup. If these
gates fail, reduce admission or rethink the extra pass before claiming task 043
complete.

## Design qualification

Only Markdown changes are made for task 042. Review uses the current guide,
collection layout/ownership rules, rectangular runtime builder and staged
indexed builder at `d9172ec`. The examples are derived from those rules;
executing them and measuring the proposed path remain task 043 work. No
performance benefit or implementation completion is claimed. Broader totality
proofs, allocating or effectful payload admission, generic iterators and deeper
regions are outside the initial design.

Validation on 2026-10-11 used Deno 2.9.7:
`deno fmt --no-config --check zig-native/RAGGED_BUILDERS.md zig-native/CONTRACT.md`
passed for both files. A local Markdown path/heading check validated 26 links
and anchors across those files. Independent arithmetic assertions checked the
triangle, filtered-square values and the U32 wrapping/division counterexample;
they are trace review evidence, not compiler execution. No compiler source or
executable fixture changed, so no build or compiler test batch was run for this
documentation task.
