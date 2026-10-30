# 113 — Initialize instance pools and copy host packets

Status: in progress for independent packet-region budgeting (root integration).
Computed global initialization and complete host qualification remain pending.

Complete persistent pool construction and ordinary copied host transport from
the [rewrite review](../zig-native/STORAGE_REWRITE_REVIEW.md) and
[task index](STORAGE_REWRITE.md). Preserve isolated host workers and Foreign
suspension while the separate deletion task removes language tasks.

## Dependencies and early contract

Task 110 supplies checked initialization/call layouts and emitter integration.
Task 111 supplies nonmoving persistent lanes, owner identity, frame recovery and
an independently configured transport region. Agree budgets and initialization
states early: uninitialized, initializing and published, with an explicit failed
attempt recovery rule. Root integrates shared Wasm ABI/export changes.

## Exclusive file ownership

- `zig-native/src/backend/storage_globals.zig`.
- `zig-native/src/runtime/storage_packets.zig`.
- `compiler/guest.ts` ordinary host/packet/invocation portions.
- Pen `crates/blot-host/src/lib.rs` and `src/native.rs`, ordinary host portions
  in `/home/mewhhaha/src/pen`.
- `zig-native/tests/storage_host_execution.test.ts`; new
  `zig-native/tests/storage_globals_execution.test.ts` and
  `zig-native/src/backend/storage_initialization_tests.zig` for initialization
  admission, publication and allocation-failure laws.

Task 110 owns `scoped_backend.zig`; supply helper APIs and required emission
changes to that owner. Root owns shared Wasm ABI files and test registration.
Coordinate edits in guest/Pen files with the language-task deletion owner;
do not rewrite task sections concurrently. Preserve unrelated sibling edits.

## Required implementation

1. Discover computed flat instance pools and their initialization dependencies,
   beyond literal-only global arrays. Validate supported fixed inline layouts
   and diagnose initialization cycles before publishing executable output.
2. Initialize dependencies in a defined order. Publish each pool only after
   its construction completes. A failed attempt must leave that pool retryable
   and preserve already-published unrelated pools.
3. Represent world globals as records/descriptors referring to separately owned
   pools. Do not introduce several owning resizable tails inside a movable world
   record. Keep temporary-to-persistent borrow rejection and exact pool identity.
4. Define trap behavior for initialized worlds. Invocation scratch recovers;
   previously performed ordinary pool writes may remain. Do not promise atomic
   rollback of the complete world or replay arbitrary effects automatically.
5. Retain the numeric Array U32/F32 length-plus-words packet format. Every
   crossing creates an independent copy; host values never borrow pool bytes.
   Make transport capacity independent from application pool lane capacity.
6. Budget simultaneous Foreign input and output, including both packet headers.
   Input remains occupied while the host allocates output. Reject overflow
   before publication; reset scratch only after the result has been copied out.
7. Preserve raw F32 payload bits and typed-array subranges. Validate pointers,
   lengths, alignment and arithmetic at both host boundaries. Reacquire memory
   views after operations that may grow memory.
8. Keep invocation stacks alive through JSPI settlement. Reject reentry and
   disposal while pending, clear the active boundary after rejection/exception,
   and allow a subsequent invocation to recover.
9. Keep Pen's copied worker jobs and prepared worker sessions. A worker recreated
   after failure reconstructs its context; it does not preserve the old instance
   world. Do not couple this work to task context save/restore or retain/release.

Arbitrary record packet schemas, borrowed host pointers, variable-tail pool
elements and whole-world transactional updates are outside this task.

## Narrow acceptance witnesses

- Computed dependent pools initialize once, survive two exports and retain
  links to their exact pool; temporary borrows cannot enter persistent storage.
- A failed initializer retries without corrupting another published pool;
  initialization cycles diagnose, and ordinary mutation/trap behavior is explicit.
- A Foreign identity crossing with input and output each approximately 600 KiB
  succeeds under a sufficient combined transport budget; a smaller budget traps
  without corrupting application pools, then permits a valid next call.
- JS and Pen round trips preserve U32/F32 bits, copy independence and subranges.
- Suspended Foreign calls reject reentry/disposal, then settle or reject cleanly;
  the next invocation works after host exception or guest trap.
- Warm isolated workers retain private state and recover by context reconstruction
  after replacement, without exposing application pointers across queues.

## Integration and completion

Write related code in batches and compile later. Join the single shared
integration gate in the task index; do not add a build/soak gate per host edit.
Use the native compiler backend without LLVM and retain required final shared
compiler/lint qualification. Record packet budget and per-worker planned bytes;
fixture success does not establish release or application performance claims.
