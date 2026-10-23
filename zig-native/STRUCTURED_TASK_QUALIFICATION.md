# Structured task implementation qualification

For the 23 October scope/spawn wrappers and tuple collection continuation, see
[task surface qualification](TASK_SURFACE_QUALIFICATION.md). This document
records the earlier cooperative lifecycle and ownership milestone.

Tasks 073/074 complete the eight owner-fixed cooperative traces in
[STRUCTURED_CONCURRENCY.md](STRUCTURED_CONCURRENCY.md). The
[19 October full gate](CLOUD_QUALIFICATION.md) executes the mapped native/OOM
laws and guest checks. Task 035 also passes the required bounded-memory stress.
The deliberate limits below remain in force.

## Scoped result trace (19 October 2026, working tree)

The partially mapped child-result trace now has a task-specific native law:
`structured tasks reject children returning group scoped callbacks and packages through OOM`
in `src/check/task_check_tests.zig`. Both a returned callback and a returned
existential package retain their child group's authority and produce
`task_escape`; the complete allocation-failure sweep passes.

The matching `tests/closed_stage_task_boundaries.test.ts` group rejects both
sources, executes the last accepted task program after each rejection, and
corrects to its exact prior Wasm. The project protocol reports the first
diagnostic: `task_escape` for the callback and `task_capture_transfer` for the
package; the native law also checks the package's subsequent `task_escape`. The
new native and guest checks pass in the complete LLVM gate, and the
tracing-replacement prerequisite is complete.

## Implemented boundary

Source checking, immutable Core admission and dependency replay independently
check task/group types, actual executable captures, affine handles and partition
owner/version/range evidence. A capture must enclose its destination group,
including when a newer scope is still active at the spawn site. Quoted task
bodies reconstruct fresh lexical group/view owners after emission.

The backend emits selected capture/result movers, counted native task contexts,
cooperative suspension checkpoints and a versioned descriptor manifest. The
instance adapter validates exact Wasm signatures and monotonic generations,
transfers resource cleanup journals, restores the correct native context before
host results allocate, and waits for all children before cleanup. Descendants
published by suspended children while their group closes are drained too.
Unstarted cancellation drops captures without invoking the thunk. Failure
selection preserves spawn order after every unabortable callback settles.

## Focused checks

Toolchain: Zig 0.17.0, Safe, native backend without LLVM. Each native build
batch checked `zig version`. Commands ran in the private implementation tree:

```sh
cd zig-native
zig build -Doptimize=safe -Dllvm=false
zig build test -Doptimize=safe -Dllvm=false -Dtest-suite=checker -Dtest-filter=task
zig build test -Doptimize=safe -Dllvm=false -Dtest-suite=backend -Dtest-filter=task
zig build test -Doptimize=safe -Dllvm=false -Dtest-suite=runtime -Dtest-filter='task context'
cd ..
deno test -A compiler/task_runtime.test.ts compiler/task_resources.test.ts zig-native/tests/task_context_execution.test.ts
deno test -A compiler/guest_async.test.ts compiler/guest_arrays.test.ts compiler/guest.test.ts compiler/resource_guest.test.ts compiler/resource_journal.test.ts zig-native/tests/task_execution.test.ts zig-native/tests/task_abi_execution.test.ts
deno test -A compiler/format.test.ts --filter=qualifier
deno test -A scripts/compiler_fixtures.test.ts
```

All selected checks passed: 12 checker laws, four backend laws, one native
context law, 26 task/context/resource laws, 35 guest/resource regression laws,
one formatter law and two fixture-selection laws. The native checker and backend
laws include complete allocation-failure sweeps and dependency/artifact round
trips. The backend confirms retained bytes equal fresh bytes and that failed
allocations do not mutate the frozen input. Native laws report zero leaks and
zero logged errors.

The Source guest law executes 34 actual descriptors in sync and JSPI modes,
including unique captures/results, returned owner aliases, packed rows,
read-only loans, disjoint writes, affine demands, cancellation, discarded
results and cleanup failure. Suspended callbacks settle in both orders; a
sibling failure waits for outstanding settlement. A 128-call warmup followed by
4096 mixed-group calls preserves committed native memory. Archive emission,
retained semantic edits, invalid-edit rollback, revert and compiler restart
produce executable descriptors. Quoted groups and locally owned partitions
execute after emission. Missing/duplicate/stale task manifests, invalid counts,
trailing metadata and incompatible actual adapter signatures reject. Task
feature version 2 carries only the descriptor count; exact typed start/move
adapters own capture transfer and the result envelope. Private layout interning
IDs are not published.

Portable adversarial laws alter actual named-call contracts, retarget a spawn to
an older destination, overlap literal partitions and forge their moved-owner
version. A scoped resource cleanup capture rejects; its scalar Array payload
does not erase the cleanup authority.

Selected Zig lint checked 413 of 466 source files with zero findings. The final
additional portable controls were checked separately with zero findings. Native
checker/context execution takes less than one second once built, the complete
backend allocation sweep about seven seconds and the selected 35 guest laws
about two seconds. These are iteration observations, not performance
qualification.

## Deliberate limits and remaining qualification

Execution is cooperative within one instance. There are no detached tasks,
shared mutable state across tasks, host worker transport or simultaneous Wasm
reentry. Unknown/overlapping partition evidence and shared pending demand
forcing reject. Partitions use one to sixteen literal half-open ranges and
retain a runtime check against actual Array length before their callback.

The independent staging capture proof conservatively rejects a quoted split
whose owning input has opaque provenance. A locally constructed unique Array
inside the future-stage function is supported. No rule infers absence of scoped
cleanup authority from an owning payload type. Selected local function/demand
capture templates transfer; a generic opaque function/demand environment whose
resource layout cannot be reconstructed declines emission.

The private slice is not integrated with all concurrent retained-type,
operation-header, fixture-relocation and ownership-performance work. Exact
before/source hashes and the separate shared staging delta are in its frozen
integration artifact. Root must merge that artifact, preserve its independently
qualified staging loan/resource work, and run the combined gate. No full-gate,
release-performance, commit or completed task status is claimed here.

## Trace-to-law index, 17 October 2026

This index maps the eight acceptance traces that the owner fixed for tasks 073
and 074 on 15 October 2026 to named laws in the passing gate at commit `05401a9`
(17 October 2026: 2,355 native laws with zero leaks, 1,501 guest tests). The
structured task laws above are now part of that full gate. Every law named below
appears in its output and is declared in the committed source. Paths are
relative to `zig-native/`. Seven traces are fully covered; one 074 trace is
partly covered, as noted under it.

Tasks 073 and 074 remain open: their closure also requires task 035 (tracing
removal) to be complete, and it is not.

### 073: Nested group exits normally with two unjoined children

Expected: Join children before closing group and releasing parent resource.
Coverage: complete.

```text
native src/check/task_backend_tests.zig: structured task backend owns replay retained helpers and every failed allocation
guest  ../compiler/task_runtime.test.ts: tasks: nested groups finish before parent cleanup and capture retirement
guest  ../compiler/task_runtime.test.ts: tasks: join moves a result once and close drops unused siblings in order
guest  ../compiler/task_resources.test.ts: task resource cancellation waits for settlement then cleans children before parent
guest  tests/task_execution.test.ts: structured source tasks execute sync JSPI affine join cancel and nested groups
```

### 073: Sibling 1 fails while sibling 2 is suspended

Expected: Request cancellation, await settlement, drop both, then report
failure. Coverage: complete.

```text
guest  ../compiler/task_runtime.test.ts: tasks: sibling failure waits for an unabortable suspension before reporting
guest  ../compiler/task_runtime.test.ts: tasks: primary failure uses spawn ordinal after every suspended child settles
guest  tests/task_context_execution.test.ts: task scheduler cancellation retains a native suspended child until settlement
guest  tests/task_context_execution.test.ts: JSPI task resumption restores its exact frame before cancellation and nested failure cleanup
```

### 073: Cancel before child starts

Expected: Do not invoke thunk; drop transferred owners once. Coverage: complete.

```text
guest  ../compiler/task_runtime.test.ts: tasks: cancellation before start drops captures without invoking the thunk
guest  ../compiler/task_resources.test.ts: task resource transfer does not retain or release the moved cleanup binding
```

### 074: Move unique capture to child, then parent uses old binding

Expected: Reject use after move. Coverage: complete.

```text
native src/check/task_check_tests.zig: structured task checking transfers unique captures and rejects ordinary Foreign contracts
native src/check/task_check_tests.zig: structured tasks move one affine demand and reject its parent reuse
```

### 074: Two sibling writes through aliases/overlapping views

Expected: Reject before scheduling. Coverage: complete.

```text
native src/check/task_check_tests.zig: structured task checking rejects overlapping unknown forged and escaping views
native src/check/task_backend_tests.zig: portable task partitions reject overlapping ranges and a forged moved owner version
native src/check/task_check_tests.zig: structured tasks retain read loans whose enclosing borrow owns the group
```

### 074: Two siblings force one pending demand

Expected: Reject; independent cells remain legal. Coverage: complete.

```text
native src/check/task_check_tests.zig: structured task checking rejects shared pending demand forcing and accepts ready immutable values
```

### 074: Child returns scoped callback/package/task handle

Expected: Reject escaped group/capability/loan. Coverage: partial. Group,
task-handle, view and loan escapes have task-specific named laws. A child
returning a scoped callback or a package relies on the ordinary capability and
package escape laws; no task-specific named law returns one from a child.

```text
native src/check/task_check_tests.zig: structured task checking rejects escaped groups and consumed handles
native src/check/task_check_tests.zig: task captures must enclose their actual destination group
native src/check/task_backend_tests.zig: portable task capture authority encloses the destination rather than only the spawn site
native src/check/task_check_tests.zig: task owner payload does not erase scoped resource cleanup authority
```

### 074: Host completes a stale generation

Expected: Reject without touching a recycled task. Coverage: complete; a retired
handle polls as `task_host_contract` and task IDs never recycle.

```text
guest  ../compiler/task_runtime.test.ts: tasks: join moves a result once and close drops unused siblings in order
guest  ../compiler/task_runtime.test.ts: tasks: a saved task context cannot introduce work after terminal cleanup
guest  tests/task_abi_execution.test.ts: task ABI rejects missing duplicate stale versions counts and forged adapter contracts
```
