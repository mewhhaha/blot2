# Structured tasks and host scheduling

Normative design for 072–074. The compiler and guest adapter implement the
cooperative task surface below; the current release evidence is recorded in
[compiler status](STATUS.md). [Usage](USAGE_CONTRACTS.md),
[scoped effects](SCOPED_EFFECTS.md),
[demands](DEMANDS.md#completion-and-cancellation) and
[suspension ownership](SUSPENDED_OWNERSHIP.md) keep their existing laws. Task
scheduling is explicit; an effect label does not imply concurrency.

## Scope and task surface

`@task.scope callback` creates a fresh task-group region and invokes its
callback once with a group capability. `@task.spawn group thunk` consumes a once
unit thunk and returns `task [r, T]`, an affine handle bounded by that group
region. `@task.join handle` consumes the handle and returns its owned result or
propagates its failure. `@task.cancel handle` consumes the handle, requests
cancellation and waits for its terminal cleanup. Nested groups finish before
their parent scope can complete. Ordinary scope completion joins all remaining
children in spawn order, discards unused results and closes the group; returning
a handle, loan or closure containing the group is rejected. No detached tasks or
implicit spawn.

Spark syntax `*(function argument)` selects the exact enclosing group during
checking, including when its source name is shadowed. It evaluates the callable
and arguments in the parent and invokes them in the child. Nested ordinary
helpers do not yet infer their caller's group.

`const scope = fn body => @task.scope body` accepts a once callback universally
quantified over a fresh region; its result cannot contain that region. Ordinary
relays, currying, identity forwarding and renamed imports preserve that scope
contract. `const spawn = fn group => fn action => @task.spawn group action` also
works through direct aliases, imports and stored partial calls. Its exact body
is validated, and each completed call checks the actual action's captures
against the selected group's lifetime. Arbitrary higher-order transport of spawn
helpers requires further transfer evidence and remains rejected.

`const await = fn source => |source|` is an ordinary helper for either one task
receiver or a tuple of task receivers. Its checked contract passes through
global aliases and imports. `|(left, right)|`, a stored tuple and `await pair`
have the same collect-all behavior: admit all dependencies together, retain
partial results until completion, and transfer results in written order. On
failure, drain affected children and release partial results exactly once.
Collections contain one to sixteen handles. A single task with a tuple payload
returns that payload without recursively receiving its fields. Generic receive
helpers currently require a direct receive body or an alias of one.

```blot
// Pure sibling tasks.
const scope = fn body => @task.scope body
const spawn = fn group => fn action => @task.spawn group action
const await = fn source => |source|
entry const sum = fn () => scope (fn group => do:
  let here = spawn group
  let left = here (fn () => 20)
  let right = here (fn () => 22)
  let (first, second) = await (left, right)
  return @u32.add first second)
```

The task state machine is new/runnable/running/suspended followed by exactly one
of succeeded/failed/cancelled. Result publication happens only after normal
completion; join moves the result, never a placeholder. Repeated join/cancel of
a consumed handle rejects. A task-group cancellation request is idempotent;
terminal results do not change state. A child failure requests sibling
cancellation; parents cannot resume normal completion until every child has
terminated and cleaned up. Among independently observed failures, choose the
lowest spawn ordinal as the reported primary failure, retaining later failures
as diagnostic supplements. A cancelled unstarted thunk drops its transferred
captures once.

## Transfer, access and demands

Spawn transfers owning unique captures and their cleanup obligations into the
child. A parent cannot use them afterward. Immutable shared values may be
retained by siblings. Read loans require an owner region enclosing the entire
group; exclusive loans require a checked disjoint partition and cannot be forged
from numeric bounds or refcounts. Parent writes are forbidden while child loans
live. Capabilities transfer only with their owner or an explicit imported
concurrent-use contract. An effect row or ordinary Foreign callback is not that
contract. Provider selection preserves exact instance keys, not matching
signature or source spelling.

State/provider instances are task-local by default. Reusing a writable instance
across siblings is rejected. A future synchronization abstraction must publish
its explicit concurrent contract; arbitrary shared mutation is outside this
design. `@task.split owner ranges callback` creates exclusive views only after
071/074 prove a common owner/version and nonoverlapping in-bounds ranges. Views
retain the owner until all children join; then ownership rejoins. Unknown or
overlapping ranges reject. Immutable reads need no disjointness proof.

A demand cell belongs to one task. Moving an unforced affine demand to one child
is legal when its captures transfer; a shared pending/evaluating demand cannot
be forced from another task. A closed immutable ready result can be shared as an
ordinary value. Concurrent forcing, waiting on another task's active demand and
cyclic demand waits reject rather than introducing implicit locks. Local request
cancellation still resets interrupted demands to pending; task cancellation
drops that task's owned demands/roots after cleanup. Host exceptions/traps leave
active demands terminal, as in the current contract. Effects already performed
remain observable; cancellation is not rollback.

## Host and cancellation boundary

The initial execution contract is cooperative task scheduling within one guest
instance, with yielding at explicit task/host suspension points. It does not
grant simultaneous Wasm reentry or promise CPU parallelism. 074 may use host
workers only for a separately checked sendable envelope with copied/serialized
owned inputs; workers never share raw guest addresses, mutable heaps, scoped
callback handles or unverified ownership. This keeps host exceptions and routing
tied to one owner.

The task-enabled ABI publishes descriptor/layout IDs, group/task generations,
start/join/collect/cancel/poll/drop operations and owned success/failure/cancel
envelopes. The host validates instance+generation before touching a handle;
counters may not wrap into live identity. Each outstanding child roots its
captures, suspended frames and result. Cleanup uses the same typed journals as
resources, in reverse registration order within each task. Task scopes close
children before releasing parent resources. A cleanup failure does not skip
remaining children/resources.

Cancellation is cooperative. Check it before source calls/host submission and at
loop back edges. During an unabortable JSPI Promise, keep the frame, callbacks
and owners until settlement; ignore its successful result after cancellation and
then clean up. Never retire or reuse a live descriptor because cancellation was
requested. Host rejection becomes task failure after its cleanup journal drains.
Instance teardown requests cancellation and waits for settlement; raw teardown
while suspended is rejected. Pure computations without safepoints cannot promise
immediate cancellation; boundedness/timeouts do not justify unsafe retirement.

Scheduling/interleaving and timing of independent host effects may vary. Written
order within each task, each operation's routing, one terminal result,
ownership, cleanup ordering within a task and the primary-failure selection rule
are invariant. Which independent failures occur before cancellation may vary by
schedule. Cross- sibling cleanup order may vary, but parent cleanup always
follows child cleanup.

## Portable evidence and acceptance

Interfaces and immutable Core carry group-region binders, task result/effect
rows, once/capture transfer, parameter/storage footprints, sendability and
disjoint owner/version/range evidence. Opaque/package calls preserve them.
Portable artifacts store binder-relative identities and schema/ABI feature
markers, never live handles or scheduler addresses. Changed task bodies,
captures, adapters, evidence or host scheduling ABI invalidate executable users.
Missing contracts reject. Runtime task publication completes ownership
allocations before exposing a handle; failed compilation/start/OOM leaves
previous revisions and group owners intact. Legacy programs retain their current
ABI and synchronous execution.

Diagnostics include `task_escape`, `task_handle_consumed`,
`task_capture_transfer`, `task_capability_shared`, `task_demand_shared`,
`task_regions_overlap`, `task_host_contract` and `task_budget`, showing the
relevant owner and scope.

| Acceptance trace                                           | Expected result                                                         |
| ---------------------------------------------------------- | ----------------------------------------------------------------------- |
| Nested group exits normally with two unjoined children     | Join children before closing group and releasing parent resource.       |
| Sibling 1 fails while sibling 2 is suspended               | Request cancellation, await settlement, drop both, then report failure. |
| Cancel before child starts                                 | Do not invoke thunk; drop transferred owners once.                      |
| Move unique capture to child, then parent uses old binding | Reject use after move.                                                  |
| Two sibling writes through aliases/overlapping views       | Reject before scheduling.                                               |
| Two siblings force one pending demand                      | Reject; independent cells remain legal.                                 |
| Child returns scoped callback/package/task handle          | Reject escaped group/capability/loan.                                   |
| Host completes a stale generation                          | Reject without touching a recycled task.                                |

073 qualifies lifecycle, joining/cancellation and resource/suspension traces;
074 qualifies disjoint access, sendable host integration and
schedule-independent invariants. These implementations remain dependent on
ownership/capability gates; the design itself may be completed ahead of them. No
runtime performance or full concurrency completion is claimed here.

Caller-region inference and generic capture-transfer evidence, general
higher-order spawn forwarding, stream channels, select-one, scoped nonlocal
exits, purity certification and CPU worker transport remain open in
[the completion plan](../FINISH_PLAN.md). Task collect-all is implemented;
comma-separated select-one syntax is not.
