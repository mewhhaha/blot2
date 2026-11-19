# Working on Blot and Gdev

Editing an existing salt pile now takes and returns its owner. Active piles
stay in slot order. A relocated pile queues its own slot for cleanup, and a
sparse sweep produces the same saved world as a full sweep. Player pickups,
haulers and miners use this path. A miner sees earlier successful withdrawals
in its tick and can retry a rejected throw without consuming a brick.

On the pinned Gdev sources, all 1,340 existing test outcomes matched and
three new checks passed (1,236 passes, 107 existing failures). All 242 files
from the 120-frame replay, the hardware screenshot and its trace matched.
Median fresh Main compile time was **966 → 989 ms** across seven eight-worker
pairs with warm files. Main grew **4,929 bytes** to **2,716,145**. Across 17
guest samples, batched edits took 0.408 → 0.373 ms, direct edits took
0.624 → 0.693 ms and the short economy run took 8.44 → 8.88 ms. The complete
published Gdev tree also built and rendered its first frame.
[Inputs, checks and timings](benchmarks/evidence/measurements/2026-11-19-owned-pile-edits.json)

The preceding insertion change made player and worker drops pass one salt owner through pile insertion, the
active index and the cleanup journal. Of 400 seeded piles, the first cleanup
previously queued 33 for another sweep. Checking the final positions left one
genuine retry. After it clears, inserting at slot 400 selects only that slot.
An explicit snapshot survives a later drop, and all three backing arrays keep
their address and capacity when shortened from eight to six and grown to seven.

That pinned Gdev comparison gained one repaired check and three new passes,
with 107 existing failures. All 242 replay files and the hardware frame matched.
Across seven fresh eight-worker build pairs on a shared host, median Main
compile time went from 2,326 to 2,339 ms and Wasm grew by 1,234 bytes to
2,658,171. The subsecond figures below belong to an earlier comparison.
[Salt ownership qualification](benchmarks/evidence/measurements/2026-11-19-owned-salt-insertion.json)

All 44 previously unbuilt Gdev test modules now execute. This includes the 34
blocked on result selection for `from`. The starting-salt, scene, terrain
restore and editor hooks now pass their successor world to their callers.
Ink runs its original 2,048-body prepared-physics workload. Pen releases
invocation-scoped owners and callbacks immediately after a return or a trap.

The Goose compiler now resolves a binary operation on its left operand and
can evaluate an ordinary callback or return a closure from `#run`. A
declared function can use this to build a lookup table from an asset at
compile time and accept its index at runtime.
[Qualification and exact inputs](benchmarks/evidence/measurements/2026-11-19-language-design.json)

A borrowed slice now rejects indexed stores, including writes through a
generic record field. The old compiler let such a helper change the middle
element of `#[5, 7, 11]` to 42 through a slice. Ink's collision and physics
queries now expose read-only ranges. Gdev builds its optional construction
previews separately so the original drawing stays available. The compiler
gate passed 1,109 tests. Ink passed 282 guest checks. The pinned Gdev
hardware screenshot and trace matched the previous frame, as did all 242
files of the 120-frame compiler comparison. All 1,332 named Gdev test
outcomes matched the control (1,224 passed, 108 failed). On six paired
fresh builds with eight workers and warm files, the previous compiler took
899 ms and this release took 873 ms at the median. Both emitted the same
2,656,241-byte Main. The standalone prepared-physics fixture grew by 12,003
bytes. Its normal, walker and joint workloads returned the same results at
256 and 2,048 static colliders.
[Slice and ownership qualification](benchmarks/evidence/measurements/2026-11-19-read-only-slices.json)

Gdev's hauling planner now imports the salt read model independently. Its
Wasm returns the expected height even when the salt writer has a type error.
Writing out public signatures in Ink's motion module gave **791 ms** to
compile Gdev Main and **51 ms** after an edit on eight workers. Leaving
those signatures inferred gave **789 ms** and **50 ms**. Private helpers
remain inferred. [Signature experiment](tasks/FAST_COMPILE.md#export-signatures-and-module-boundaries-19-november-2026)

The previous type-system checkpoint at Blot `be489b79` reduced six layers
of `(x, 0, x)` from a three-second timeout to 3.4 ms. Nested inferred
signatures still grow during construction.
[Type-system assessment](tasks/FAST_COMPILE.md#shared-types-in-ownership-analysis-19-november-2026)

Ordinary `#run` functions can construct records, tuples, constructors, arrays
and lists. `std/build.include` reads project-declared files. A real Gdev
asset probe changed the selected image and observed a new read set. Unselected
file edits reused the complete Wasm. Gdev's existing asset readers are still
in use. Scene consumers check against `SceneHooks world`; a storage edit
rechecked four modules, down from six. A terrain update reused the allocation
for all 169 tiles and preserved a copied snapshot.
[Scene interface](benchmarks/evidence/measurements/2026-11-18-gdev-scene-interface.json)

The released compiler now has a Blot benchmark for building and sharing
lists of Gdev intents. Joining 128 chunks and traversing them fell from
**169.7 to 14.7 µs** using chunk references. Bulk copies fell from 5,282,560
to 1,008 bytes. Grouping the packed payloads by width reserved **45.5 KiB**
for a 4,096-intent tail and two prefixes, down from 160 KiB. Packing still
costs Wasm bytes and the shipping layout remains fixed stride. A private
list can now grow through exclusive tail appends in `case` and `if` arms.
Selecting 1,171 home IDs copied **8,176 bytes** and kept **one owner**, down
from 2,740,140 bytes and 1,172 owners. The saved-prefix and callback-order
laws pass, and the 8,192-input regression now returns its complete array.
[Blot builder experiments](benchmarks/intent/README.md#building-and-sharing-lists-in-blot)

Workers transfer 13 more Core and interface tables as verified Goose arrays.
Across all 269 modules, writing the captured Core records fell from
**36.2 to 4.6 ms**. All 538 portable records matched, and total
checker replies fell from 72,858,303 to 71,856,423 bytes. The full compiler
gate, named Gdev and Ink outcomes, 120-frame replay and inspected frame
qualified the release.

Changing the history capacity from 64 to 65 in `world_storage.blot`
returns finished Wasm in **35.0 ms**, down from **82.2 ms**.
The retained checker reuses the checked type, callee and scalar argument
position. The session copies the changed module’s Core nodes and updates
one Wasm operand. Other body edits still use module-level checking.
[Measurements and qualification](benchmarks/evidence/measurements/2026-11-19-gdev-call-literals.json) · [Compiler work](tasks/FAST_COMPILE.md)

## Earlier runtime qualification at Blot `be489b79`

| Suite | Starting checkpoint | Qualified release |
| --- | --- | --- |
| Gdev Pen | 919 passed, 112 failed, 44 unbuilt | 1,220 passed, 108 failed, all 210 modules execute |
| Ink Pen | 268 passed, 1 failed, 3 unbuilt | 280 passed, all 73 modules execute |
| Ink native | 92 passed, 21 failed on the pre-services reference | 111 passed, 2 failed |
| Compiler | | 192 recorded Wasm fixtures, 212 lowering fixtures, both direct references, 1,101 guest and host tests passed, 100 ignored |

All 919 prior Gdev passes survived. Of the earlier failures, 34 now pass.
Another 267 newly executable checks pass and 30 fail. The remaining 108
failures comprise 70 assertions, 18 stack traps, 11 heap traps and 9 failed
`require` calls. Six independent hauling scenarios now run in Pen.

The qualified release matches every named Gdev and Ink outcome from the
ownership release. Pen checked Main, Devtools and 545 assets. All 242 files
of the 120-frame replay matched, including the final snapshot. The inspected
640×480 hardware frame and trace also matched. The earlier ownership release
used Blot `9b7cd3e8` and Gdev `42e005c`. Its 200,000-frame run measured
0.14 ms median and 1.00 ms p95 guest time on a shared host.
[Ownership qualification](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json)

All 136 prepared-physics exports and 1,800 tower tick packets matched the
reference. Two 16,384-lane compiler witnesses return 16,837 in a 68 KiB
temporary stack after releasing the last read of a terminal scalar producer.
The historical Ink physics source at `58e6b02` still exhausts its stack in
`source_values`.

## Remaining work

1. Require an owner for changes to an array's length as well as its elements.
   A borrowed `@storage.push` changed a saved alias's length from one to two.
   A borrowed `@storage.truncate` changed it to zero. An `own` helper
   rejects the live alias, and an explicit copy preserves its length.
   Next migrate Gdev's `salt.replace_stacks_into` and its borrowed grid
   rebuild. Replacement issues fresh pile IDs. Check that their order, the
   active prefix and spatial lookups survive replacement, and that a saved
   world restores its original IDs. The [source scan](scripts/integration/count_stores.py)
   counts **987 store-shaped lines** across the pinned Gdev and Ink sources,
   down from 1,004 on the same inputs. This includes rejection fixtures.
   Gdev and Ink have **zero `lent` declarations**, down from 15. The compiler
   still accepts `lent` and shared stores to arrays while callers migrate.
2. Reduce committed linear memory while preserving the contiguous scratch
   allocation fast path. The two remaining Ink native failures enforce memory
   limits for dense bodies, snapshots, UI and text. Default modules start at
   49,348,608 bytes. An on-demand allocator started at 64 KiB and passed the
   seven original workload limits, including 256 KiB for the 4,096-segment
   join against a 512 KiB cap. It slowed four warmed workloads by 37–55%.
   The release retains the current allocator. Measure the per-allocation checks
   before replacing it. Gdev exhausts its stack with the old fixed 2 MiB budget.
3. Preserve effect order and owning result types in lowering. Pure contract
   methods now run both original codec fixtures. Effectful methods still
   reject, and an experimental lowering reordered callbacks. A structurally
   inferred wrapper around two `persist.restore_into` calls can lose the branch
   result. The attempted compiler fix trapped on real resident and picking
   restores. Gdev names its concrete `FrameAccess` at this boundary.
4. Work through the remaining Gdev failures by name. Compare the affected
   tests and the 120-frame replay against the pinned reference. The
   [raw evidence](benchmarks/evidence/qualification/2026-11-17-owned-runtime.raw.json.gz)
   includes all named outcomes, memory probes, replay hashes, PNG and trap
   cleanup receipts. The [compile-speed plan](tasks/FAST_COMPILE.md) retains
   the subsecond and Wasm-size targets.

Keep guest ABI 8, session protocol 2 and save schema 26. The optional
`blot:finish_invocation` export released all six owners after the SIMD fault.
Native, JSPI and worker checks cover callback lifetime across suspension.
The JSPI and worker adapters ran under Deno. The export changed 93 Wasm
references, with every existing fixture function body byte-identical.

Use `deno task test:compiler` for compiler changes and the tracked
[Main build](scripts/integration/build_gdev.ts) and
[frame runner](scripts/integration/run_pen.py) for integration.
