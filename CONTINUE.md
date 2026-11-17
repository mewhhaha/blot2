# Continue the Blot ownership conversion

The save/restore callers and Gdev test layout are checked and pushed. The
active compiler is Goose with the direct Wasm backend in `compiler-goose/`.
The [qualification record](benchmarks/evidence/qualification/2026-11-17-owned-save-restore.json)
pins the release compiler, Gdev `c42efef`, Ink `d689527` and Pen `1dfca8a`.

## Next batch

1. Recover more executable coverage before changing the world hooks. Of the
   44 Gdev module runs that still fail to compile, 34 first report an unresolved
   result type at `std/prelude.blot`'s `from`. Start with
   `tests/ascension_announcement.blot` and `tests/ascension_stream.blot`.
   Trace the call site and reduce one case. An explicit `F32.from` fixed
   devtools where the destination was known. If a caller already supplies
   the expected type, follow it through lowering. Measure how many of the 34
   reach Wasm with the fix.
2. Follow Gdev's `starting_salt` callback from the scene and title handlers
   through `Hooks.reset_salt` to `reset_starting_salt_into`. Both handlers
   already own the world. Then take the editor path from Ink's `editor.toggle`
   through `Hooks.restore_scene`. A writer returns its successor world, and
   callers rebind it alongside any result. Keep the hook and toolbar checks
   that exercise the edge consuming a newly requested restore.
3. Continue top-down through value-returning writers, capturing closures and
   the Ink libraries Gdev calls. Ink's physics experiment at `58e6b02` was
   reverted in `719e0c7`. Its `prepared-physics` workload needs loop
   temporaries released while allocations carried to the next iteration survive.

The [store counter](scripts/integration/count_stores.py) finds **1,558 candidate
store lines and 55 lent functions** across Ink lib/tests and Gdev
src/tests/test_support/devtools/performance. The [writer scan](scripts/integration/world_writers.py)
finds 320 direct or transitive Gdev world writers, 108 already taking ownership.
Both counts are approximate. Retire the mutation form of `=`, `lent`,
`migrate-stores` and its reporting switches after the callers move. Preserve
ABI 8, session protocol 2 and save schema 26.

## Verified on 17 November

| Pen suite, same test layout on both source pairs | Passed | Failed | Module runs unable to compile |
| --- | ---: | ---: | ---: |
| Gdev reference (`e431d43` with Ink `719e0c7`) | 890 | 123 | 46 of 209 |
| Gdev current | 919 | 112 | 44 of 209 |
| Ink reference and current | 268 | 1 | 3 of 73 |

All previously passing tests still run and pass. Eleven Gdev failures now
pass and 18 additional tests execute and pass. The original Gdev layout
reported only 391 passes and 107 unbuilt module runs. Moving its shared Pen
entry to `tests/` fixed all missing-file diagnostics. Two additional Ink
codec fixtures type-check on both source pairs and still stop at
`contract_method` during emission.

- Gdev Main compiled in **2.27 s median** over three fresh compiler processes
  (2.15–2.29 s), emitting the same **2,633,057-byte** Wasm every time. All
  264 modules were fresh. Devtools also emits Wasm, and Pen checks all 545 assets.
- The 10,000-actor round trip uses **31,024,064 bytes** of the 32 MiB heap.
  The state and scene match the reference byte for byte. All four sparse
  walking and hauling exports now run 40 frames with 50 actors.
- All 120 input packets, 120 output packets, the schema and final snapshot
  match the reference. The first 640×480 frame was inspected. A 200,000-frame
  run completed at 0.113 ms median guest time and 0.472 ms p95.
- The release compiler, tooling, three reference suites and packaging passed.
  The guest/host stage hit a temporary executable-busy error. Its complete
  rerun on the same release passed 1,074 tests, with 101 ignored.

The [raw evidence](benchmarks/evidence/qualification/2026-11-17-owned-save-restore.raw.json.gz)
contains named outcomes, both comparison runs, the packet manifest and the
inspected frame. Run a focused `pen test-blot tests/NAME.blot` from Gdev or
Ink, then compare the full affected suite by test name. Use
`deno task test:compiler` for compiler changes and the
[Main build](scripts/integration/build_gdev.ts) and [frame runner](scripts/integration/run_pen.py)
after game semantics change. The [memory model](tasks/MEMORY_MODEL.md) and
[compile-speed plan](tasks/FAST_COMPILE.md) retain the wider work, including
the subsecond target.
