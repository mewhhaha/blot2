# Finish the owned-storage rewrite

Reviewed 29 October 2026 by three `gpt-6.1-sol` agents covering compiler,
runtime/host, and Ink/Gdev, then reconciled by the integration owner. This is a
source review and implementation decision record, **not completed implementation
or new qualification**. Start implementation from the
[task index](../tasks/STORAGE_REWRITE.md).

## Conclusion

Replace the counted backend and immutable-world architecture. Keep the current
Zig frontend, checked Core, Wasm emitter infrastructure and copied Pen/browser
boundary. Finish one bounded data-stack backend; migrate applications to its
ownership rules instead of rebuilding the old runtime's complete feature set.

The fastest useful target is named instance-owned pools, fixed-layout rows,
borrowed access, explicit copies, direct specialized calls and static system
composition. A movable world record containing many independent growing arrays
is not that target. The world is an instance lifetime and a bundle of access
handles to separately owned pools.

Goose provides the underlying ideas: scoped data stacks, references that survive
growth, destination construction, compile-time function parameters and isolated
workers. Its native address-space reservation strategy cannot simply be copied
into our Wasm32 memory budget. The bounded regions below are our adaptation,
not a claim of full Goose language or implementation parity. See the
[Goose overview](https://aardappel.github.io/goose/) and
[links explanation](https://aardappel.github.io/goose/#links-narrower-than-pointers).

## What the review found

| Finding | Source | Consequence / assigned task |
| --- | --- | --- |
| Any storage type/operation in a loaded module selects the new backend for the entire unit; ordinary arrays alone still use the old one. | `src/backend/scoped_backend.zig:16`, `core_backend.zig:2369` | An unused declaration can change admission. Explicit cutover and removal are required: 120. |
| Calls expand the callee body while emitting Wasm. Depth/work budgets stop expansion. | `src/backend/scoped_backend.zig:771` | Large call graphs and recursion cannot be solved by raising budgets. Emit reusable specializations: 110. |
| Lifetime tracking, branch joins and emission share mutable state; a returning branch supplies a scalar placeholder. | `src/backend/scoped_backend.zig:247,358,1323,1351` | Separate plan evidence and exit shapes; Never paths must not determine aggregate result layout: 110/112. |
| No general sum matching, list execution, array iteration or aggregate loop carries. | `src/backend/scoped_backend.zig:208,997,1018,1387` | Implement the bounded data/control profile applications need: 112. |
| Every simultaneous owner reserves 1 MiB; at most 255 slots. Owner openings consume a global 24-bit generation. | `src/runtime/data_stacks.zig:9,44,94` | Pack compatible extents, budget growers, and separate wide owner identity from regions: 111. |
| Globals must be literal arrays of plain inline elements. | `src/backend/scoped_backend.zig:457` | Computed pool initialization and stable instance lifetime: 113. |
| Foreign request and response coexist in a single 1 MiB scratch region. | `src/runtime/storage_packets.zig:14`, `src/backend/scoped_backend.zig:439` | Budget the combined crossing explicitly; independent 600 KiB input/output currently exceeds capacity: 113. |
| Ink ECS uses three-level COW columns; checkpoint creation keeps the same array value. | `../../ink/lib/ecs.blot:11,94` | Changing array types alone would turn snapshots into aliases. Replace storage and copy explicitly: 114. |
| Ink systems, state providers and policies retain function values. | `../../ink/lib/app.blot:14`, `../../ink/lib/ecs.blot:28,64` | Static composition and explicit pool parameters avoid general closures/handlers: 114–119. |
| The session keeps previous and candidate worlds until presentation is accepted. | `../../ink/lib/pen/program.blot:55` | Remove implicit simulation rollback with an explicit protocol change: 117. |

The generation limit is an availability defect, not evidence of a dangling
reference: the runtime traps rather than wrapping. It is reached after
16,777,215 owner openings: roughly 7.8 hours at 60 calls/second and ten openings
per call, or 3,355 calls at 5,000 openings per call. A fixture seeded near the
boundary can test the replacement without a soak run.

The consumer review found 63 Gdev source modules using ECS and 53 Ink library
modules mentioning pages/map/buffer. Storage migration therefore includes scene,
physics, UI, rendering and caches. It is not finished by changing `ecs.blot`.

## Working decisions for implementation

### Preserve the agreed syntax

All array literals remain `#[...]`; the destination chooses `Array T`,
`GrowArray T` or `ResizeArray T`. `[...]` remains a list. Keep `func`, explicit
`return`, curried `->`, `$` constructors, `#run` and `#do:`. This rewrite adds no
array literal variant. `#if`, custom operators and new staging facilities are
separate work, not prerequisites for the memory cutover.

`&T`/`&value` borrows one value; `&[T]`/`&items[start..end]` borrows a captured
range; `^T`/`^items[index]` links into an identified pool. None owns the target.
Growth preserves addresses; an existing view keeps its old length. Shrink,
owner reset and restore must respect or invalidate borrows under the checked
lifetime rules. A link retains pool identity and checked bounds; it is not an
unchecked integer. Narrow link encoding and raw memory-image loading can wait.

### One bounded Wasm storage model

- Pack fixed arrays and completed/frozen extents into planned regions without
  moving them. A grower may extend only at its region's top.
- Give independently growing persistent pools separate, explicitly budgeted
  lanes. Put temporary allocations in LIFO frames; return newly built owners
  into caller-provided destinations. Rewinding a frame does not walk payloads.
- Use full-width region/owner indexes and owner identity plus a wide epoch,
  distinct from region identity. Reusing one packed extent cannot revive a
  stale descriptor while its neighbors remain live. Metadata is bounded too.
- Plan total Wasm32 address space, initial memory, per-lane capacity, owner-table
  capacity and transport capacity together. Expose budget failures clearly;
  do not silently relocate or fall back to a heap. Initially committing the
  planned memory is acceptable. Sparse per-lane demand commitment is not a
  Wasm promise; optional prefix `memory.grow` is later work.
- Budget both live sides of copied host packets. Preserve U32/F32 wire bits,
  ordinary Foreign calls, JSPI settlement and reentry/disposal exclusion.

Capacity configuration and layout records are the first code handoff of tasks
110/111/113. Do not add a separate allocator framework or spend a phase designing
automatic region tuning. Size the first application plan for its actual pools
and representative workloads, report reserved and used bytes separately.

### Cut features that recreate the old runtime

| Keep for the first migrated applications | Remove or defer |
| --- | --- |
| Fixed inline records, fixed-width ADTs, checked links, flat pool payloads | Variable-tail aggregate elements and arbitrary non-LIFO payload reclamation; separate child pools instead |
| Direct calls and known, nonescaping callback specialization | Runtime callback arrays, escaping closures, function-pointer dispatch |
| Explicit pool/resource parameters; sequential control and Foreign suspension | General application state handlers, saved/multi-shot continuations |
| Local demands whose lifetime and result layout are admitted | Escaping memo cells; no counted fallback |
| Flat immutable List snapshots and copied collection operations | Persistent tree-sharing complexity guarantees; no accidental aliasing of immutable Lists |
| Bounded call-graph specialization and separately admitted scalar recursion if required | Recursive SCCs that retain growable scratch or allocate/return arbitrary owners |
| Pen worker jobs, warm worker sessions, data-only queues | Language tasks, task scopes, spawn/join/cancel and spark/receive machinery |

These are changes to the guest application profile. Keep useful compile-time
evaluation and generic checking; do not delete frontend facilities merely because
they must not survive as runtime objects. Reject unsupported runtime uses with
source diagnostics. Preserve behavior/data-driven state machines as ordinary
data plus explicit dispatch.

### Ink and Gdev own their mutable state

Begin with a handwritten concrete owner module and ordered stage calls in Gdev.
Ink already has a typed builder seam, but no world-schema generator exists;
creating a new generator is not a prerequisite. Keep library mechanisms generic
over explicit access bundles, with no game types or identifiers in Ink.

Use entity-indexed fixed-layout rows plus presence information. Keep monotonic
U32 entity IDs and deterministic iteration initially. Variable payloads live in
separate pools. Data-only resource metadata can reference these pools without
owning a collection of movable tails. No implicit duplication of owner handles
is an independent copy.

The shared API operations are `read`, `write`, `insert`, `remove`, `rows`,
`copy_into`, `checkpoint`, `reset_world` and `flush_commands`. These names are
implementation contracts, not new language intrinsics. Reads borrow; writes
record payload changes; insertion/removal record membership changes. Queries
capture membership or defer structural edits until iteration ends. Query
invalidation is distinct from the address validity of references during growth.

Copy only registered interpolation state immediately before a fixed step.
Define nested-payload copy policies explicitly. Use encoded scene copies for
editor undo/redo and saved checkpoints first. Reset/restore starts a fresh
world lineage and clears dependent caches. Remove general immutable
`app.preview`; a sandbox, if needed, starts from an explicit copied checkpoint.

**Presentation rejection no longer selects an old simulation world.** Finish
simulation mutation before publishing its copied output. Preserve Pen's
transactional renderer/cache behavior, but change/version the session protocol
and both native/browser hosts so rejection cannot imply world rollback or
silently repeat a simulation step. Explicit Snapshot/Restore, including netplay
restore/replay, remains. A trap may leave a partially mutated world; recover a
failed session from an explicit checkpoint/defaults rather than claiming an
automatic transaction. Initialization publishes only completed new owners.

### Instructions superseded by this decision

The user's greenfield replacement and chosen worker-only concurrency supersede
the old counted-runtime and language-task implementation direction in tasks
030–035 and 072–074 and the historical runtime sections of `FINISH_PLAN.md`.
Keep those evidence records; do not execute them to reconstruct removed features.
Unrelated compiler work remains separate.

[Ink's AGENTS.md](../../ink/AGENTS.md) now requires geometry reuse and explicit
copies for retained snapshots. Task 115 carries those ownership and scene API
requirements; automatic snapshot preservation is superseded by the greenfield
model. No extra approval requirement follows from the historical wording.

## Evidence and lean execution

The ignored local development report, if retained at
`build/bench/storage-application/results.json`, records 32 guest/frontend checks, 16 selected exhaustive native laws, a compiled
inventory of 2,627 laws, zero Zig findings, a Pen fixture and copied worker
batches with one/four workers. It explicitly says `release_qualified: false`.
It does not qualify the complete inventory, a packed runtime or migrated games.

Implement complete batches before compiling. Share one integration owner for
hot files and gates. Use three development checkpoints: compiler plus one pool
fixture; all Ink; Gdev plus browser/Pen behavior. Run final full qualification
once after retirement, before any requested compiler commit. Do not create a
build loop per agent, per edit or per acceptance bullet.

The [task index](../tasks/STORAGE_REWRITE.md) owns scheduling and file boundaries.
No builds, runtime tests or new performance measurements were run for this
review. No compile-time, frame-time or memory improvement is yet established.
