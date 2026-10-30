# 120 — Make owned storage unconditional and retire the old runtime

- **Status:** In progress: explicit data-stack ABI 8 and host admission are
  implemented; unconditional dispatch and legacy retirement remain pending.
- **Dependencies:** Inventory can start early. Semantic cutover and deletion
  follow executable compiler/Ink/Gdev integration in 110–119.
- **Contract:** [Review](../zig-native/STORAGE_REWRITE_REVIEW.md),
  [schedule and gates](STORAGE_REWRITE.md).

## Outcome and ownership

Every runtime program uses the data-stack model. Unsupported features produce
source diagnostics. No source marker selects a different memory model, and no
counted backend, task scheduler or second guest allocator remains reachable.

This is the integration-owner task. It takes ownership of shared compiler/host
files only after previous owners hand them off. Inventory candidates include
`backend/core_backend.zig`, counted portions of `backend/backend_*.zig`,
`runtime/{shared_rc,cycles_runtime,root_runtime,session_heap,public_owners,
runtime_cleanup,region_runtime,cohort_runtime,list_runtime}.zig`,
task ABI/context/ safepoint modules, guest task wiring, and Pen
`crates/blot-host/src/tasks.rs`. These are candidates for dependency review, not
an instruction to delete whole shared modules blindly. Preserve reusable IR,
typechecking and host-compiler allocation machinery.

## Implementation

- [ ] Map legacy runtime emitters, public imports/exports, task syntax/std APIs,
      guest bridges and test groups to removal or retained shared
      infrastructure. Separate guest ownership from Zig compiler
      scratch/revision ownership.
- [ ] Make data-stack planning unconditional. Remove `scoped_backend.required`
      dispatch and test that adding an unused declaration cannot change the
      memory model. Check ordinary `#[...]` programs as well as capability
      arrays.
- [ ] Delete counted allocation/retirement/cycle/task paths and their feature
      switches. Replace old object ownership evidence in retained compilation
      with new plan evidence only where actually supported; unchanged
      whole-module reuse is sufficient initially. Changed source must not replay
      stale artifacts.
- [ ] Remove `@task` scopes/spawn/join/cancel, spark/receive and structured task
      host support. Diagnose old task module versions/imports clearly. Keep Pen
      workers, worker sessions, copied buffers, `Ink.task_queue` and
      Foreign/JSPI.
- [ ] Remove obsolete task/refcount fixture wiring; map each still-relevant
      semantic law to its new expected behavior. Preserve meaningful
      alias/lifetime, packet, exception, numerical and gameplay laws. Do not
      delete unrelated failures to obtain a passing inventory.
- [ ] Update grammar/formatter/stdlib/guide and contract documents to the final
      admitted profile. Replace active old memory/concurrency claims across
      Blot, Pen, Ink and Gdev. Keep clearly labeled historical evidence and
      source hashes.
- [ ] Ensure compiler/cache/host ABI versions cannot accept artifacts built for
      the removed runtime. Update schemas/templates, then regenerate bindings.

## Acceptance and lean gate

Retirement follows checkpoint 3; validate the resulting candidate in task 121's
single final qualification batch rather than requalifying before and after each
deletion. A few structural assertions may inspect emitted modules for absence of
counted/task imports/exports and verify unchanged/edited project reuse.

Ordinary application modules, worker jobs and Foreign suspension all run on the
new path. Old task use fails with an intentional diagnostic. No counted fallback
is reachable, and runtime resets contain no per-payload reference walk.

## Evidence

Pending: removal map, changed inventory, ABI/cache version decisions, final
candidate identities and task 121 evidence. No local commit or push is implied.

Read-only integration review, 30 October: use an explicit Wasm module memory
model, including scalar-only programs, and a new ABI 8 data-stack profile.
Copied packet allocation/reset remains; counted roots, public owner adapters,
resources and task extensions do not belong to that profile. The TypeScript
guest must stop treating every version above 2 as counted-root ownership. Pen's
shared reader is `crates/pen-runtime/src/abi.rs`, reexported by `blot-host`;
update it for native and browser hosts together. Native packaged metadata also
needs a version bump so old binaries require repackaging. Preserve workers,
worker sessions, copied queues and Foreign/JSPI. Preserve compiler session
allocation and interface caches while removing guest counted emitters and task
bridges.

The initial implementation gives Wasm modules an explicit memory model and emits
ABI 8 for data-stack modules even without public arrays. TypeScript and Pen
readers admit that profile without counted roots, reject mixed ownership
sections, and preserve copied packets and Foreign callbacks. Pen native metadata
advances to version 2. The development compiler builds; five executed host laws
pass, as do Pen's three ABI reader tests. The rebuilt Pen runs all 23
entrypoints in nine ready Ink modules (8.9 seconds). This does not retire
ordinary legacy dispatch or claim task completion.
