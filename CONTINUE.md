# Working on Blot and Gdev

All 44 previously unbuilt Gdev test modules now execute. This includes the 34
blocked on result selection for `from`. The starting-salt, scene, terrain
restore and editor hooks now pass their successor world to their callers.
Ink runs its original 2,048-body prepared-physics workload. Pen releases
invocation-scoped owners and callbacks immediately after a return or a trap.

The qualified compiler is Blot `27476846`, with Gdev `0e0d772`,
Ink `3f2e603` and Pen `ad9766c`. Fresh Gdev Main took **763.8 ms**
median with eight frontend workers and emitted **2,639,648 bytes** across
270 modules. [Paired fresh and edit measurements](benchmarks/evidence/measurements/2026-11-18-gdev-entry-symbols.json)

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

Renaming Gdev Main’s entry parameter now checks **1 of 270 modules**.
Delivery of the complete Wasm took **45.2 ms**, down from **710.8 ms**
over eight paired sessions. The loader links the entry’s parsed names after
its dependencies. A changed entry can still shadow an import, report a new
error or emit different code. Lighting edits took **37.3 ms**
against **36.8 ms**. The same rename inside the imported
world-storage module rechecked **270 modules**.
[Measurements and qualification](benchmarks/evidence/measurements/2026-11-18-gdev-entry-symbols.json) · [Compiler work](tasks/FAST_COMPILE.md)

## Current results

| Suite | Starting checkpoint | Qualified release |
| --- | --- | --- |
| Gdev Pen | 919 passed, 112 failed, 44 unbuilt | 1,220 passed, 108 failed, all 210 modules execute |
| Ink Pen | 268 passed, 1 failed, 3 unbuilt | 280 passed, all 73 modules execute |
| Ink native | 92 passed, 21 failed on the pre-services reference | 111 passed, 2 failed |
| Compiler | | 192 recorded Wasm fixtures, 212 lowering fixtures, both direct references, 1,098 guest and host tests passed, 100 ignored |

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

1. Migrate the remaining shared writers and borrowed returns. The
   [source scan](scripts/integration/count_stores.py) finds **1,190 candidate
   store lines and 15 `lent` declarations**, down from 1,558 and 55. The
   [world-writer scan](scripts/integration/world_writers.py) finds 20 writers
   each in `player/hand` and `world/salt`. Follow their callers as a group and
   preserve snapshot independence when replacing live terrain views. Retire
   the mutation form of `=`, `lent` and their migration tools once callers move.
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
