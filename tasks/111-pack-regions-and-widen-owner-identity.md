# 111 — Pack regions and widen owner identity

Status: runtime integrated; final whole-application qualification pending.
Native storage laws and executed-Wasm capacity/identity witnesses pass.

Complete the runtime foundation described in the
[rewrite review](../zig-native/STORAGE_REWRITE_REVIEW.md) and
[task index](STORAGE_REWRITE.md). This replaces the current storage scheme; it
does not add an optional allocator or counted fallback.

## Dependencies and early contract

Task 110 supplies the planner interface and checked layout/lifetime summaries.
Agree that interface before implementing placement: region ID, byte capacity,
owner ID, owner epoch, frame mark, initialized extent and destination region.
The compiler/root integration chooses the concrete Wasm representation of the
owner ID plus u64 epoch; the runtime must retain all identity bits. Task 113
consumes independent persistent and transport region budgets.

## Exclusive file ownership

- `zig-native/src/runtime/data_stacks.zig`.
- `zig-native/src/runtime/data_stacks_tests.zig` and `data_stacks_fixture.zig`.
- New `zig-native/src/runtime/data_stack_regions_tests.zig` and
  `data_stack_regions_fixture.zig` if the existing fixture cannot express the
  packed-region boundaries. Do not create a separate fixture per case.

Task 110 owns planner/emitter edits. Root owns shared Wasm ABI integration and
test registration; provide the required signatures rather than editing those
files concurrently. Do not edit generated Wasm or sibling application code.

## Required implementation

1. Replace the uniform 1 MiB interval per owner with checked region byte
   capacities from the plan. Remove the 255-slot limit and token low-eight-bit
   indexing. Use full-width checked owner and region indexes.
2. Separate owner identity from placement. Maintain an explicitly budgeted owner
   metadata table containing region, base, initialized extent, layout,
   capability and u64 epoch. A region may contain multiple independent owners.
   Reuse of a metadata entry must invalidate old descriptors.
3. Pack fixed extents sequentially. Completed/frozen values may permit following
   allocations without moving their bytes. Freezing must never implicitly copy a
   live value or remove identity checks.
4. Give independently growing persistent pools configured nonmoving lanes. A
   grower may extend only at its region's top. Check capacity and arithmetic
   before publishing length/top changes; do not relocate on overflow.
5. Add transient frame marks and rewind. Nested allocations obstruct growth
   until rewound, unless the plan assigns them another region. Rewind
   invalidates affected owners while preserving earlier live owners and their
   addresses.
6. Support caller-provided destination regions for transferred results through
   task 110's interface. Scope exit must not rewind a promoted result.
7. Make reset/rewind work proportional to regions and affected owner metadata,
   without walking array elements, graph edges or counted references. Preserve
   persistent lanes during invocation recovery after traps.
8. Emit checked total memory requirements from the real plan. Fixed initial
   committed memory is acceptable. Independent sparse demand commitment is not a
   Wasm capability; defer optional contiguous-prefix `memory.grow` support.

Do not implement variable-tail aggregate elements, compaction or allocation into
arbitrary payload holes. Metadata-entry reuse is distinct from payload-hole
recycling. Flat pools may use application free indexes/tombstones; owner epochs
do not replace node generations when logical pool elements are reused.

## Narrow acceptance witnesses

- Two fixed owners share a region; releasing one cannot validate its stale
  descriptor against the other, including after metadata-entry reuse.
- A live grower rejects obstructed growth; rewinding a nested frame restores
  growth while preserving its base and initialized values.
- Near-boundary u64 epoch handling cannot wrap into a valid old identity. Seed a
  fixture near the boundary instead of running a soak test.
- Capacity/overflow failures leave published lengths and unrelated persistent
  owners intact; the next invocation recovers transient storage.
- More than 255 small owners work within the configured budget, and memory
  reflects planned bytes rather than one MiB per owner.
- Caller-owned results survive child rewind; nested borrows retain their exact
  owners and initialized-extent checks.

## Integration and completion

Implement the runtime and planner contract in batches; do not build per edit.
Join the single shared integration gate defined in the task index, including the
narrow laws above. Use Zig 0.17.0 and the native backend without LLVM. The
required final compiler/lint qualification remains a shared completion gate.
Report planned/reserved bytes and owner-table capacity for the application
fixture. No throughput or full-replacement claim follows from fixture success.

## Per-owner capacity integration, 2026-10-30

`@storage.reserve owner literalCount` records an element request for one named
Grow/Resize owner. It changes neither length nor identity and preserves live
borrows. Repeated requests use their maximum; zero retains the header and known
initial literal contents. Unreserved owner sites keep their configured fallback.
Shared physical slots accommodate every contributing owner site, and all row,
header and alignment arithmetic is checked before Wasm publication.

The executed witness grows one pool beyond the default while keeping a nearby
pool small, verifies its existing view, traps on the smaller pool's exhaustion,
and successfully invokes the module again. Dynamic counts and size overflow are
rejected. Gdev's 1,048,576-lane history capacity is explicit at its owner sites;
neither the history limits nor all other pools were enlarged.

Owner metadata now tracks the last live slot. Closing and rewinding trim dead
trailing entries; holes below a later live owner remain available for reuse.
Rewind/reset scans stop at that extent instead of the configured owner capacity.
Existing epoch, bounds and failure-before-mutation checks remain in place. The
shared 64-law Wasm phase passes, including a new high persistent owner / reused
hole / region rewind witness. Retained-render interpolation's six checks pass in
about 275 ms where the prior fixture exceeded a 45-second bound; these are
fixture observations, not application performance qualification.
