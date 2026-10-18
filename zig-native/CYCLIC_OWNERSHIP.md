# Local cycle reclamation

Task 034 adds nonmoving trial deletion to admitted typed ownership. Tracing
remains during the transition. This is not a task 035 tracing-removal record;
root owns the mandatory combined compiler gate before completion.

## Links and boundaries

The header remains 32 bytes and List capacity remains 244 words. `next` is
phase-exclusive destruction, free-list or traversal work. `candidate_prev` and
`candidate_next` hold weak queue links, then trial counts and the member chain.
They never retain an object or appear in its payload reference mask.

An original counted journal lease uses `candidate_prev` for its owner slot.
Lease-bearing objects are outside boundaries: discovery excludes them and never
subtracts their outgoing contributions. Their descendants therefore keep the
outside counts that protect reachable cycles. Removing the last lease clears its
owner slot before decrementing and enqueueing. Root pop, return movement and the
AVL borrow hold test the lease bit before interpreting this shared field. Alias
roots contribute ordinary strong counts independently of that link.

## One atomic pass

1. Nonzero releases deduplicate a weak candidate queue. Zero releases unlink
   membership before ordinary iterative destruction. Scalar zero-child masks and
   proven scalar List trees skip enqueue; reference and unknown graphs do not
   receive a count-based acyclicity guess.
2. Discovery drains the candidate union and visits each unleased vertex once. It
   saves actual strong counts in trial fields. Subtraction removes every
   internal strong edge once, including duplicate fields.
3. Positive trial counts seed liveness, which propagates through strong edges.
   Real strong counts and memo contents remain unchanged during these phases.
4. The entire unreachable set receives the dead bit before any edge retires.
   Live member scratch clears first. Dead objects retire through the existing
   destructor: internal dead edges disappear together; outgoing live edges drop
   normally. Deferred membership installs only after its scratch clears; newly
   queued survivors wait until the phase finishes.
5. Ordinary zero-count work drains after classification and retirement finish.
   Free headers clear lifecycle flags; reuse initializes all ownership links.

There is no recursive graph traversal, scratch allocation, user destructor or
host call. Typed payload masks are the sole edge description. Reference leaves
walk every physically retained initialized slot, including unused capacity or
logically removed values whose writer has not cleared their edge. Owner tokens,
scalar values, status fields, function ordinals and allocator links are
excluded. Finite masks cap scans at their highest owning bit; bit 31 keeps the
repeating reference tail through physical allocation capacity. The same bound
drives ordinary destruction, so scalar tails do not hide linear work.

The collector runs at existing closed-root loop/call points once allocation
traffic or removed candidate payload reaches the pass threshold, and drains at
invocation completion and idle disposal. The threshold is 64 KiB plus 64 bytes
per vertex the previous pass discovered and kept (capped at 2^18 vertices), so
rescanning live temporaries costs at most one vertex per 64 bytes of traffic.
Reclaimed vertices don't raise it, so uncollected cyclic garbage stays bounded.
Only a candidate's first enqueue charges removal traffic; releases of an already
queued candidate add none. Removal traffic saturates, while weak membership
stays deduplicated. Candidate-free points check a global in constant
time. A triggered pass finishes its closure without a work-budget escape. Active
JSPI and force journals remain strong boundaries. Cancellation, terminal force
handling and host capability identity retain task 033 semantics.

## Checked helper demand

Cycle helper IDs are assigned with the arena. Completed source bodies, direct
calls and checked table references determine whether their bodies are needed.
The proof follows compiler helpers, treats public/host/initializer allocation
routes conservatively, and stops at the checked zero-child scalar allocator.
Raw, reference and unknown allocators require the full collector. Guarded hooks
cannot enqueue, unlink or collect when the proven graph has no strong edges.
This preserves function-index timing and artifact replay while omitting unused
helper bodies. Native laws compare fresh, retained, portable checkpoint and
replayed Wasm for both zero-child and strong-cycle sources, including OOM.

Full collection calls are explicit invalidation barriers in call summaries and
IR ownership contracts. A regression assertion checks this independently of
executed laws, so optimizers cannot infer an ordinary non-invalidating helper
from the header-only mutation phases.

Scalar List acyclicity comes from immutable scalar element metadata plus private
downward tree/cache edges. New, edit/copy, concat, slice, branch and node-copy
constructors preserve the proof, including copies from static data. Leaves and
scalar Arrays already have zero-child masks. Reference collections, State,
nominal objects, closures and demands remain cycle-capable. Ready demand caches
stay strong; State writes never weaken or clear their memoized result.

## Qualification

The implementation is isolated over qualified incoming `f184dde`, tree
`1431522db1bd9b93b1e0b3f3f69949e2122aa5e6` (compiler source is unchanged from
`310d60ce85a8ebe26f3c9f4d48fc35811fd98a94`). Historical qualification over
incoming `ae7e3492609b6c8b5b95fc1d43983e69f8802d35` is preserved separately; its
candidate SHA is
`0ce3a6747715cb9ae49111f4e6163aa1dd96052e88e8cd88b7588f4cc379bb65`. The
historical pin predates the explicit collection-summary barrier fix. Final
source/binary pins and paired costs are recorded in
[CYCLIC_OWNERSHIP_QUALIFICATION.md](CYCLIC_OWNERSHIP_QUALIFICATION.md).

Focused evidence includes the existing 512 → 20000 State/closure/strong-demand
law unchanged, self and shared cycles, duplicate physical capacity edges,
module/force roots, live JSPI cycles under reclamation pressure, settlement and
host rejection, and 2048 canceled request cycles. Source laws require admitted
ownership `[2, 2, 0]` and increasing local reclamation counters, so tracing
alone cannot satisfy them. Allocator exhaustion and reuse laws call trial
deletion without tracing. An unrelated 8192-object heap does not enter a
one-node candidate closure. Existing alias, copy, million-node destruction,
provider, request and suspension laws remain exercised.

The optional `blot:cycles` section version 1 declares admission and four scalar
counters: passes, vertices, dynamic strong edges and reclaimed payload bytes.
The guest rejects duplicate, malformed or inconsistent sections. Existing
ownership versions and public call signatures remain unchanged.

An initial Safe/noLLVM fanout budget screen failed at 16,542,015 requested
bytes. A matched incoming Safe/noLLVM control produced exactly the same value
and counters: this was a build-mode comparison error, not a task 034 allocation
regression. The initial Fast candidate passed all eight unchanged budgets. No
budget was widened.

Matched scalar controls demonstrate the helper subtraction: a scalar Array
reader requests 3,620,857 bytes incoming, 3,829,824 with eager helpers and
3,635,679 with the checked zero-child boundary; Wasm is 4603, 6138 and 4858
bytes. Scalar fill/read follows the same pattern. These are allocation/code-size
measurements, not comparisons of Safe and Fast runtime speed.

## Limits and next hills

The header and 244-word geometry add no task 034 cost. Candidate membership and
three edge walks add work to cycle-capable graphs. The collector is synchronous
and nonincremental: pause length scales with the candidate closure's vertices
and physically retained owning slots, not with the whole heap. Large still-live
reference graphs can be rescanned, at a rate bounded by the threshold above.
Discovery stops at `no_cycle` objects: their exact proof covers their whole
reachable structure, so no cycle passes through them, and leaving them outside
subtraction only keeps their children live. Scalar proofs avoid candidacy
itself; other exact descriptor proofs are future hills.

The counted-lease boundary preserves live or conservatively retained journal
objects. It cannot reclaim a graph while an owner still holds it. Physical
tracing, uncovered whole-module fallback and task 031–033 costs remain; an
unbounded source shape does not acquire a universal memory guarantee here. The
prior ownership runtime costs and the nested 90-row counterexample remain
limitations for task 035, as recorded in [SHARED_RC.md](SHARED_RC.md) and
[PERSISTENT_ROOTS.md](PERSISTENT_ROOTS.md).

Large List/Array graphs and long suspensions need no header layout change. A
future descriptor directory must remain a typed scalar Array of borrowed leaf
bases, with its descriptor/root retaining the leaves; borrowed directory entries
must not become strong trial edges.

## Exact immutable source layouts at `4013b10`

Fresh checked record/product/algebraic allocations may receive the existing
no-cycle flag after a bounded exact immutable-layout proof. Nominal traversal
checks all constructors in the emitting source unit, including unused variants;
foreign definitions, functions, demands, providers, mutable containers and
unknown fields decline. This flag suppresses candidate enqueue only. Counts,
typed edges and iterative destruction remain, and genuine trial closures still
follow those edges. Source changes revoke retained and portable claims.

The joint LLVM release passes full native/OOM and 961 guest/client tests,
including original strong cycles, suspension/cancellation and all eight budgets;
351 analyzer files have zero findings. The scalar summary build no longer
rescans alive immutable trees: its isolated 16384-leaf control drops 4309740
trial vertices to zero. Real cyclic windows still pay candidate-closure cost; 31
warmed release samples charge those visits explicitly and retain bounded
committed memory. See
[rolling qualification](ROLLING_SUMMARIES_QUALIFICATION.md) and
[tracing replacement](TRACING_REPLACEMENT.md) for exact pins and remaining
scope.
