# Shared and cyclic runtime ownership

Specification for tasks 030–035, based on qualified compiler `d9172ec`. This
specifies replacement behavior; it does not claim implemented RC or removal of
tracing. The [language guide](../compiler/guide.md),
[demand completion contract](DEMANDS.md#completion-and-cancellation) and
existing [cycle law](tests/arena_gc_execution.test.ts) remain authoritative.

## Invariants and representation

One strong reference owns one edge or root. A borrowed reference owns no count
and cannot outlive its named strong owner. Borrowing does not permit mutation of
an immutable value. Moving transfers one ownership obligation without changing
the count; copying an owning reference retains it. Zero is an absent reference.
Scalar bits, function-table indices, operation IDs, allocator links and List
uniqueness tokens never retain anything. Uniqueness tokens are separate from RC:
`count == 1` alone does not authorize a persistent collection edit.

Every managed payload has a checked, immutable layout ID describing its strong
edges. Resolve `runtime_layout.Role.value` using the concrete checked type,
variant tag and demand/request state. It is never a conservative pointer guess.
Arrays describe logical length, stride and element edges; Lists describe branch
edges and initialized leaf elements. Scan neither unused capacity nor scalar
leaves. Captured environments, partial applications, cursors and descriptor
caches have explicit edges. A duplicated pointer in two owning fields counts
twice. Interior addresses are temporary borrows of their allocation base.

Keep payload offsets and nonmoving addresses. Use eight Wasm32 header words, 32
bytes before the aligned payload:

| Word                               | Meaning                                                                                         |
| ---------------------------------- | ----------------------------------------------------------------------------------------------- |
| `block_size`, `requested`, `flags` | Allocator extent, initialized payload size and lifecycle bits.                                  |
| `next`                             | Phase-exclusive free-list, tracer-mark, cycle-work or destruction link.                         |
| `strong`, `layout`                 | Checked U32 count and immutable descriptor ID.                                                  |
| `candidate_prev`, `candidate_next` | Weak doubly linked candidate membership; during a cycle pass, trial count and member-list link. |

The allocator/tracer enumerates physical blocks by advancing `block_size` from
the recorded first block to the heap end, as `arena_runtime.zig` does now. Free
blocks retain their extent and have `requested == 0`. Update/invalidate the
allocation-start bitmap on allocation, reuse and retirement. Header links are
metadata, never counted payload edges; the tracer's mark stack may still use
`next` without making allocator links strong.

One runtime phase owns `next` at a time. Cycle discovery and live propagation
finish before destruction drains; tracer marking finishes before retirement.
Popping a candidate, or discovering one already queued, unlinks its two weak
links before reusing them as trial/member scratch. While that scratch is live,
nonzero releases set a deferred-candidate bit instead of overwriting the member
link. Mark the whole dead set, detach its edges and queue its storage; clear all
member scratch and install deferred candidates before draining destruction or
reusing blocks. This permits a 16-byte increase over the current header without
sharing simultaneously live links. No recursive or host work can interleave
these phases.

`flags` records live/retiring/free, candidate membership, fixed-storage/immortal
and cycle-pass state. A zero-child layout needs no edge walk but still has a
count when shared. Checked sizes include the new header and alignment before
allocation. Retain overflow traps before mutation; zero release, wrong layout
and retaining a retiring object are internal ownership faults. Check these in
qualification builds; valid emitted operations must never encounter them.

Closed immutable static graphs, including reserved empty descriptors, are
immortal and have no edges into mutable managed storage. Mutable startup
demands, globals and State are ordinary counted objects, even when their payload
address is in module data. They receive explicit module roots. Fixed-storage
headers participate in counting and retirement; their payload bytes remain
reserved module storage rather than entering a dynamic free list. Destruction
still releases every dynamic child. Do not classify a mutable memo, or an
immutable ancestor reaching it, as immortal because it was serialized at
startup.

## Operations and roots

Lower typed ownership operations from resolved layouts, independently of machine
`i32`/`f32`. The private operation contract is:

| Operation                         | Ownership effect                                                                   |
| --------------------------------- | ---------------------------------------------------------------------------------- |
| `new(layout, bytes)`              | Fully initialized object with one caller-owned reference.                          |
| `retain(value, layout)`           | Copy one strong reference; null and immortal values are no-ops.                    |
| `release(value, layout)`          | Consume one reference; destroy at zero, otherwise queue a cycle-capable candidate. |
| `load_borrow(owner, field)`       | Borrow a checked child while `owner` remains live.                                 |
| `load_retain(owner, field)`       | Return a new strong reference to that child.                                       |
| `store_move(owner, field, value)` | Publish transferred ownership, detach and release the old edge.                    |
| `store_copy(owner, field, value)` | Retain first, then perform `store_move`; safe for replacing a field with itself.   |
| `drop_slot(slot)`                 | Clear the owning root slot before releasing its former value.                      |
| `collect_cycles()`                | Stop the mutator, classify candidates, then retire only the unreachable set.       |

Construction starts with zeroed reference fields. Reserve all fallible storage
before a move or publication; failure releases only initialized edges. A field
store and its ownership transfer form one noncollecting transaction. Ordinary
`memory.copy` of references requires retains for each new owning occurrence;
consuming relocation moves edges and clears the old slots. Record reconstruction
and shared List/Array edits preserve every old snapshot.

Root owners are module globals, lexical owning slots, loop carries, caller-owned
arguments/results, active provider/State scopes, and invocation/suspension
frames. Their references count exactly like fields. An ordinary parameter is
borrowed from its caller; capturing, returning or storing it requires a retain.
A fresh returned value transfers its obligation before the callee's roots close.
An overwritten carry/root publishes its replacement before releasing its old
value. Keep outer live rows rooted while releasing each inner loop's
temporaries; allocation order or an activation floor is not an ownership proof.

Use a private typed root journal outside the managed object graph. Each active
slot names its allocation base, layout and frame. Reserve slot capacity before
creating an owned value. Register each potentially escaping/failing temporary;
move the journal obligation when ownership becomes a field or another root.
Frame marks and inactive slots make normal exit and later exceptional cleanup
idempotent. Root-journal addresses never appear as source values. Runtime root
storage growth may trap, but cannot lose an already recorded owner.

The internal call convention reserves a caller result slot before entering the
callee frame. Returning moves or retains into that slot before closing callee
roots. Direct, indirect, recursive, inlined and synthetic calls obey the same
contract. Proven nonescaping lifetimes may eliminate journal slots or reference
operations only when every failure/exit still closes the obligation. A closed
allocation group may bulk-retire its internal edges once; edges to surviving
objects still release exactly once. Never combine individual releases with a
second bulk recycle of the same member.

No new public guest value types, raw pointer handles or close methods are
implied. Ownership-aware adapters require an explicit `blot:abi` revision 3
alongside version 2 support during migration. The new private exports are
`blot:ownership_enter()` and `blot:ownership_leave(outcome)`; outcomes 0/1/2
mean normal completion, Wasm/host failure, and idle module teardown. They manage
the outer journal frame. Enter requires idle state; normal/failure leave
requires an active invocation, and teardown requires idle state. Existing
allocation/reset exports retain their v2 behavior for v2 modules. A v3 reset
recycles only proven dead storage after journal cleanup; it cannot erase a live
module root. Validate the complete export signatures, section version and
outcome before changing state. Bump compiler/artifact identity with this
representation change. The public `Guest` API remains the same; selecting v3 is
an explicit compiler/client compatibility change.

## Destruction and reentrancy

At count zero, unlink any candidate in constant time, mark the object retiring
and enqueue it. Drain a worklist, never recurse down children. Enumerate
initialized strong slots in descending payload offset, detach each slot before
releasing its child, then recycle the object's storage once. Scalar-only objects
skip the walk. Intrusive work links require no allocation, so destruction
remains usable after allocation failure. A long chain uses bounded native/Wasm
stack space.

Destructors are generated layout walks. They perform no user code, Foreign call,
allocation, collection or resurrection. There are no language finalizers here. A
draining flag makes nested releases append work rather than start another walk.
Cycle reclamation first marks its entire retiring set; edges within that set
detach without decrements, and edges outside it release normally. Address reuse
occurs only after candidate/work membership is cleared. This prevents stale weak
candidates, duplicate child release and reentrant destruction.

## Demand, requests and host lifetime

Demand environments remain strong until the demand dies. Ready memo fields are
strong too; changing State releases only State's edge, never the cached result.
Creating a demand does not capture a provider chain. First force borrows the
then-active provider scope, whose invocation owns it through every suspension.

| Event                                       | State and ownership                                                                                     |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| First force                                 | `pending → evaluating`; journal the active force and root its cell.                                     |
| Normal completion                           | Move/retain the actual result into `cached`, then publish `ready`; drop the force record.               |
| Later force                                 | Borrow or retain the ready result according to its use; never reevaluate.                               |
| Handler `yield`                             | Keep the evaluation, provider roots and captures; resume the same force.                                |
| Handler `return`/`break`                    | Unwind each abandoned active force once to `pending`; release provisional results and frame roots.      |
| Trap, host throw/rejection, recursive force | Exceptional invocation cleanup marks interrupted active forces terminal; no retry and no partial cache. |

Terminal is an explicit private state in the existing status word; it preserves
current behavior, which represents an interrupted force as evaluating. Terminal
cells keep their captures until their final owner releases them. Nested language
cancellation resets only the scopes it actually unwinds; it does not roll back
performed effects. Normal completion commits the memo before releasing its
provisional owner. A ready demand is never reset by cancellation elsewhere.

Provider frames own their callback/State/request targets and outer links.
Request cells, decisions, replies, carries and completion values use their
actual payload layouts. Frame borrows require a live scope root. Return/break
transfers the selected exit value before unwinding frames; cancellation consumes
each root journal obligation once. A reused captured computation retains its
source captures but receives fresh invocation/provider/request ownership each
time.

The guest driver copies numeric arrays across the host boundary, as it does now.
A retained JavaScript packet owns a copy, not guest memory. Keep the guest
argument/root alive until callback marshaling finishes; an imported array reply
gets a new guest owner before resumption. Copy an exported result out before
normal `ownership_leave`. The driver calls exceptional leave in `finally` after
Wasm traps, callback throws/rejections or failed marshaling; cleanup must not
throw for an already validated ownership graph. No Wasm stack destructor is
assumed to run after a trap.

JSPI suspension keeps the entire invocation journal and capability binding live.
Do not reset the arena, release provider roots or allow reentrant entry/read/
dispose while the invocation is active. A pending Promise is not a cancellation
request. Ignoring the returned Promise, or a host Promise that never settles,
does not make the Wasm continuation unreachable: its owners must remain live.
This specification adds no host abort API and promises no reclamation of a still
suspended invocation. On settlement the normal/exceptional path closes it once.
Idle disposal releases module roots, drains destruction/cycle work and drops
runtime journal storage; capabilities become stale. Unrelated entries remain
usable after an exceptional invocation.

## Complete cycle strategy

Use localized, nonmoving trial deletion. Queue a live nonzero object whenever a
strong edge/root is removed. Candidate membership is weak, deduplicated and
unlinked before zero-count destruction/reuse. No weak language edges or weak
memo fields are introduced.

A descriptor may carry an exact `no_cycle` proof: its complete reachable strong
structure is acyclic under every allowed mutation. Scalar-only allocations
qualify immediately. Scalar-element List trees qualify from their immutable
height-decreasing branches and downward descriptor/cache links. Closed immutable
products may qualify when every strong edge has a strictly decreasing structural
rank. Publication, updates and helpers must preserve the proof; otherwise the
whole descriptor remains cycle-capable. Immutable storage alone is insufficient:
reference-bearing List leaves, Array elements, recursive nominal values, State,
closures and demands remain candidates unless a complete proof covers all of
their edges. Never infer the proof from count 1, machine words or a uniqueness
token.

Skip candidate enqueue only for a proven `no_cycle` object; ordinary zero-count
destruction still releases its children. A cycle pass reached from another
candidate stops at that object: no cycle passes through it, and its unsubtracted
edges only keep children live. Every actual cycle therefore retains candidate
discovery.
The stop-the-mutator pass is:

1. Drain the candidate list and build the union of their outgoing strong
   closures. Record each member once using header flags and intrusive
   member/work lists. Ignore null and closed immortal graphs; set
   `trial = strong`.
2. Walk every member's strong slots. Subtract one from its target's trial count
   for each internal edge, including duplicate edges. Counts outside the closure
   are never modified. Real counts remain unchanged.
3. Members with positive trial counts have an outside owner, including journal,
   module or suspended roots. Mark them live and propagate liveness along strong
   edges within the closure. Do not treat a trial-zero descendant of a live
   member as garbage.
4. The unmarked set is unreachable. Mark the entire set retiring before
   detaching any edge, unlink all its candidates, and apply the shared
   retirement rule. Clear scratch state on surviving members, then drain
   ordinary zero-count work.

These phases allocate no heap scratch and do not suspend, call hosts or mutate
source values. Header traversal is iterative. If an ownership fault is detected,
qualification fails before phase 4; never resume with partially adjusted real
counts. A candidate deferred during retirement is installed after member scratch
is cleared and processed in a later pass.

Completeness follows from the last incoming owner removal: an unreachable finite
cycle either reaches zero through ordinary destruction or leaves a nonzero
candidate. Its closure includes all members; subtracting internal edges leaves
no outside owners, so phase 4 retires it. Outside roots, even through a
different cycle, leave a positive trial count or a live propagation path.
Incoming edges from unrelated objects need no reverse graph: their contributions
remain in the real counts. No whole-heap root scan or allocation-floor retention
is needed.

Run at existing loop/call safe points after either 64 KiB of allocation traffic
or 64 KiB of removed candidate-object payload, whichever occurs first, and drain
candidates at invocation completion and idle disposal. Do not use iteration
cadence or high-water memory as the sole trigger. A candidate-free point is a
constant-time check. Once triggered, finish the whole candidate closure before
resuming; do not silently abandon work at a node budget. The memory bound is
reachable storage plus one trigger interval, allocator size-class slack and the
largest construction/destruction batch. It excludes genuinely live suspensions.

The tradeoff is a 16-byte header increase over the current 16-byte header and
O(vertices + owning slots) work over each candidate closure. A small dropped
edge can inspect a large still-live graph. This design chooses a simple complete
pass over incremental colors/write barriers; measured pause or memory failures
keep tracing removal blocked and require a revised strategy.

## Graph traces and counterexamples

For the existing law, `S` is the active State cell, `N` the `#Next` value, `C`
the retained closure and `D` its demand. Ownership edges are `S → N → C → D → N`
after force. State supplies an incoming root; the smaller `N → C → D → N` cycle
remains after State is cleared. The provider chain is not captured by `D`.

| Step                                      | Observable result and ownership                                                 |
| ----------------------------------------- | ------------------------------------------------------------------------------- |
| Install `#Next delayed`                   | State owns `N`; `N` owns `C`; `C` owns `D`; local `delayed` roots `C`.          |
| First force; discard its temporary result | `D.cached` gains an owning `N` edge; memo stays ready.                          |
| Set State to `#End`                       | Drop `S → N`; local `C` still roots the cycle.                                  |
| Force again, invoke the cached closure    | Both return the same `#Next`; no reevaluation and no erased memo.               |
| Drop cached locals and `delayed`          | Each cycle node has count 1 from its predecessor; a release queues a candidate. |
| Trial deletion                            | Each trial count becomes 0; retire all three together.                          |

If a module root also owns `N`, its trial count remains 1 and liveness
propagation preserves all three. Plain RC leaks the discarded count 1 cycle. A
weak cached edge frees `N` after State is cleared and violates the unchanged
law.

Other required traces:

- Two returned closures own the same environment: drop either closure, call the
  other, then drop it; the environment dies only after both edges disappear.
- Two persistent collection versions share a child: discard one version and
  overwrite the other's field; retain the replacement before releasing the last
  old edge. Replacing a field with itself cannot destroy it mid-store.
- Two cycles share a child `X`: a root to `X` preserves only its reachable
  graph, not the cycles pointing into it. Retire both cycles and decrement their
  `X` edges twice; a separately rooted `X` survives.
- A suspended request roots a cycle and its reply buffer: collection preserves
  both. Handler cancellation or host rejection closes its journal once; only the
  still-rooted ready memo survives. Never manufacture a cached placeholder.
- A million-node acyclic chain destroys iteratively. A pointer-looking U32/F32
  payload never keeps an unrelated allocation alive or triggers its release.

## Transition and measurable gates

Keep tracing through 031–034 and until 035 qualification. Admit the ownership
mode only when every allocation, dynamic payload, root and exceptional boundary
of that module is covered. Otherwise compile the entire module with the existing
tracing path; do not mix uncounted aliases into counted storage. Report the
coverage/fallback reason. Qualification fixtures can admit closed subsets while
production keeps the fallback.

In admitted modules, the existing tracer may reclaim cycles until trial deletion
is qualified. It must use the same set-retirement operation: mark its complete
dead set, detach internal edges without double decrements, release outgoing
edges and recycle each member once. RC-zero retirement changes live-block/bitmap
status while preserving physical extents. The typed root journal supplies the
tracer's roots too; conservative activation floors may supplement them during
migration but cannot replace them. Never let tracing and RC independently free
the same storage. Retain current tracing behavior in fallback modules; replacing
its activation floors is not an excuse to loosen the nested-loop memory gate.

Instrument allocations/frees and requested/committed/peak/live bytes, retains,
releases, root/force slots, candidates, cycle passes/vertices/edges/reclaimed
bytes, maximum destruction depth and collection pauses. Report compiler overhead
separately. Pin a qualified tracing executable and workload/host hashes; compare
release builds on the same host, warm-up and repeated distributions.

| Gate             | Required evidence before completion                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 031: typed RC    | All runtime layouts have enumerators and zero-child cases. Prove or decline `no_cycle` descriptors; repeated aliases of a large scalar List/Array produce zero cycle candidates/edge scans. Alias, overwritten/self-store, persistent collection and million-node chain tests end with expected live counts; zero underflow/double-retirement, destruction stack depth independent of chain length. Sweep construction/publication OOM; immutable Core and compiler gates pass.                                                                                                                    |
| 032: roots       | Returned/captured/global/demand graphs survive repeated calls and roots dropped in every order. Invocation-owned live objects/slots return to zero after each completed call; module-owned counts return to zero at disposal. Preserve lexical snapshots, strong memos, startup data, ABI v2/v3 admission and fresh/retained/checkpoint behavior.                                                                                                                                                                                                                                                  |
| 033: suspension  | Sync and JSPI have equal values/effect traces for nested yield/return/break, retry, host throw/rejection, traps and recursive force. Stress 2048 settle/cancel cycles; active slots return to the persistent baseline after each. A deliberately pending host Promise stays valid and blocks reentry/dispose, without pretending it was canceled.                                                                                                                                                                                                                                                  |
| 034: cycles      | Run the existing 512→20000 cycle law unchanged, including committed memory ≤ warmed + 65536 bytes. Add self-cycles, shared-child cycles, module/suspended roots and reordered drops. After root removal plus an explicit safe point, reclaimed object/edge counts equal the unreachable graph; ready memo values remain identical. Candidate-free work is constant; long-running live bytes plateau. Measure repeated drops of still-live reference-bearing graphs with 1, 8192 and 1048576 strong slots, including candidate deduplication, edge work and worst pause; no hidden whole-heap scan. |
| 035: replacement | No allocation/root/layout falls back to tracing; audit generated code and runtime imports for absence of tracing helpers/metadata. Full compiler, native/guest/ABI/sync/JSPI, cycle, suspension, persistent-root and failure gates pass. Stress long-running collections, escaping closures, repeated guest calls, canceled requests and discarded cycles. Keep all cycle/ownership laws permanently.                                                                                                                                                                                              |

For 035, rerun the task 002 nested 90-row workload with 8, 40, 200 inner
discarded 8192-word arrays in one guest invocation. Earlier committed storage
grew from 43,515,904 to 942,211,072 bytes. Preserve every outer row's result
while live bytes plateau at equal live topology and committed memory at 200
iterations stays within one 64 KiB page of the warmed 8-iteration run; no dead
activation floor may accumulate. Apply the same one-page warmed bound to
existing forever-loop/Foreign-array laws. Wasm memory cannot shrink, so also
compare live/reclaimed bytes rather than inferring reclamation solely from
committed pages.

The removal budget is explicit: median runtime CPU geometric mean ≤ 1.10×
tracing, p95 per workload ≤ 1.20×; median fresh/retained-edit compiler CPU
geometric mean ≤ 1.05×. Report all individual regressions, peak memory,
RC/header allocation cost and worst cycle pause, with at least 20 measured runs
after warm-up. Behavioral and memory bounds are mandatory even if CPU improves.
A failed budget keeps 035 open; this document makes no measured performance or
current tracing-removal claim.

## Design qualification (11 October 2026)

Specification implementation `d021c57` settles task 030. Deno 2.9.7 formatting,
local paths/heading links and the graph/cancellation traces pass review. The
29-link integration check covers this specification, the builder specification
and CONTRACT. Only Markdown changed; no compiler batch was needed. Proposed
memory and CPU gates qualify future implementations, not this design.
