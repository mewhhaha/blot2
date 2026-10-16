# Structured task implementation qualification

Tasks 073/074 implement the cooperative contract in
[STRUCTURED_CONCURRENCY.md](STRUCTURED_CONCURRENCY.md). This records focused
qualification, not completion of the combined release gate. Task 035 remains an
unmet prerequisite, and the final union must run `deno task test:compiler` and
`deno task lint:zig` before a milestone commit.

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
feature version2 carries only the descriptor count; exact typed start/move
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
