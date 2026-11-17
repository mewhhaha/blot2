# Continue the Blot ownership conversion

All 210 Gdev test modules now reach execution. The compiler recovered all 34
modules blocked by `from`. The scene and editor hooks return their successor
world, and Ink runs the original 2,048-body prepared-physics workload under
the existing memory limits. The active compiler is Goose in `compiler-goose/`.

The [qualification record](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json)
pins Blot `2daea2b0`, Gdev `f658a1e`, Ink `efd978a` and Pen `1dfca8a`.
The subsequent Gdev commit `42e005c` makes both terrain restore sections own
their world. Its eight affected modules had the same 29 passes and four
failures, and all 482 files of a 240-frame Enter/Tab/Tab replay matched.

## Current results

| Suite | Previous | Qualified |
| --- | --- | --- |
| Gdev Pen | 919 passed, 112 failed, 44 unbuilt | 1,220 passed, 108 failed, 0 unbuilt |
| Ink Pen | 268 passed, 1 failed, 3 unbuilt | 280 passed, 0 failed, 0 unbuilt |
| Ink native | 92 passed, 21 failed on the pre-services reference | 110 passed, 3 failed |
| Compiler | | 189 recorded fixtures, 1,080 guest and host tests passed, 100 ignored |

All 919 prior Gdev passes survived. Of the earlier failures, 34 now pass.
Another 267 newly executable checks pass and 30 newly executable checks fail.
The village renderer alone cleared 38 bounds traps by iterating over the shared
prefix of its ECS columns. Six independent hauling witnesses now run in Pen.

Four interleaved fresh-process pairs put Gdev Main at **2.33 s median** and
**2,639,139 bytes**, compared with **2.27 s** and **2,633,057 bytes** at the
previous checkpoint. Each process compiled all 264 modules afresh. Pen checked
545 assets. All 242 packet, schema and snapshot files from 120 frames matched
the reference. The inspected 640×480 hardware frame and trace also matched.

## Remaining work

1. Migrate the remaining shared writers and borrowed returns. At Gdev
   `42e005c` and Ink `efd978a`, the source scan finds **1,196 candidate store
   lines and 25 `lent` declarations**, down from 1,558 and 55. The counts are
   approximate. The remaining terrain readers return live views into their
   owners. Preserve snapshot independence when converting them. Retire the
   mutation form of `=`, `lent` and the migration tooling once callers move.
2. Reduce the remaining Ink memory failures using their existing assertions.
   ABI 8 initially exposes 49,348,608 bytes of Wasm linear memory. The same
   UI/text module must fit a 512 KiB text run and support a larger UI run.
   Enabling Gdev's old fixed 2 MiB temporary budget exhausts its stack on the
   first frame. The SIMD callback law also found six scoped owners surviving a
   trap until the next entry. It needs immediate invocation cleanup.
3. Preserve lexical and effect order in the backend. Pure checked contract
   methods now run both original codec fixtures. Effectful methods still
   reject. The prototype reordered callbacks. A reduced case with two
   consecutive `persist.restore_into` calls still loses a branch result in a
   structurally inferred owning wrapper. Gdev names its concrete world at that
   boundary.
4. Track the 108 runtime failures by test name, retaining every passing case.
   The [raw evidence](benchmarks/evidence/qualification/2026-11-17-owned-runtime.raw.json.gz)
   includes the suite logs, named comparisons, memory probes, packet hashes,
   frame and actual rejected experiments. The [compile-speed plan](tasks/FAST_COMPILE.md)
   retains the subsecond and Wasm-size targets.

The terminal scratch pass releases an unaliased scalar producer after its last
reads and before the returned array allocates. Both 16,384-lane witnesses
return 16,837 with a 68 KiB stack. The general carry-compaction prototype
increased Main by 20,256 bytes and slowed a small loop, so it stayed isolated.
The historical Ink physics implementation at `58e6b02` can still exhaust its
stack inside `source_values`.

Use `deno task test:compiler` for compiler changes and the tracked
[Main build](scripts/integration/build_gdev.ts) and
[frame runner](scripts/integration/run_pen.py) for integration. Keep guest ABI 8,
session protocol 2 and save schema 26.
