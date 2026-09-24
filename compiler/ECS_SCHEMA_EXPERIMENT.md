# ECS schema compilation experiment

`ecs_schema_experiment.ts` generates four standalone Blot programs for each
requested number of typed cells. They make the same state transition: starting
with cell `i` containing `i`, add the runtime `U32` argument to every cell, read
every cell back, and return their sum. The runner compiles each program with the
same retained native compiler version, instantiates its Wasm, and checks the
result for arguments 0, 1 and 17. Each sample is a **stateless clean request**;
process startup, Wasm instantiation and execution are outside the timed
interval.

The variants isolate different parts of the gdev ECS design:

| Variant            | Shape and access                                                                                                 |
| ------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `builder`          | Gdev-style generic `insert_cell` chain; one `@effect.run` handler per cell.                                      |
| `fixed_handlers`   | One explicit `World` record and one statically written handler per cell; retains the same generic State action.  |
| `direct_accessors` | Explicit `World` record, typed getter/setter functions for each cell, and no effect handler chain.               |
| `direct_record`    | Explicit `World` record and a direct state transition; a lower-bound control with no generic access abstraction. |

`builder` and `fixed_handlers` compare dynamic builder construction with an
explicit schema while keeping effectful access. `direct_accessors` shows the
cost of a concrete typed capability API; `direct_record` shows the cost when
that API is also inlined into the application. These programs do not contain
gdev's snapshot cells, component queries, systems, graphics or numeric protocol.
The 18-cell row matches only the count of gdev's nested world cells, not its
whole workload or runtime behavior. Therefore their differences are **not**
predictions of a gdev speedup.

From the blot2 root, the final current-compiler run used:

```sh
python3 build/gdev-checkpoint/run_normal_priority.py deno run --allow-all compiler/ecs_schema_experiment.ts 3 2,8,18 1 . build/gdev-ecs-experiment/final-current-threads1.json
```

The runner keeps only its owned Deno/native process tree at Linux `SCHED_BATCH`
policy 3, nice 0, because the desktop may demote Deno to `SCHED_IDLE`. It does
not change unrelated processes. The final compiler executable SHA-256 is
`8bf231efcd20e2734cee2314290ce6fcdc6f24d9b4e95ea089ad41ea324f2f5e`. The
[raw report](../build/gdev-ecs-experiment/final-current-threads1.json) and
[run log](../build/gdev-ecs-experiment/final-current-threads1.log) contain all
per-request wall/CPU samples, source and Wasm hashes, native PIDs and scheduler
metadata. Generated fixtures are also under `build/gdev-ecs-experiment/`.

Each value below is the median of three stateless clean requests after one
untimed warmup, in milliseconds. CPU is the native child's user+system time from
`/proc/<pid>/stat`, with 10 ms tick resolution on this host. Wall time includes
the API request and can vary with desktop contention.

| Cells | Builder wall / CPU | Fixed handlers wall / CPU | Direct accessors wall / CPU | Direct record wall / CPU |
| ----: | -----------------: | ------------------------: | --------------------------: | -----------------------: |
|     2 |            55 / 50 |                   49 / 40 |                     44 / 40 |                  37 / 40 |
|     8 |          121 / 110 |                   92 / 90 |                     85 / 80 |                  44 / 40 |
|    18 |          473 / 460 |                 471 / 370 |                   458 / 350 |                 119 / 90 |

For the 18-cell fixtures, source SHA-256 hashes are:

| Variant          | Source SHA-256                                                     |
| ---------------- | ------------------------------------------------------------------ |
| Builder          | `49649a17b5ee017d586fa26e7a78355e854756c94dc476790104215e4b191855` |
| Fixed handlers   | `b1651f7ae3f5e5afd15b70c0b016aa3054b96a71983c7e503c867493e19ad4e9` |
| Direct accessors | `e293704d23502c12bf0c19a911b5abb526d4a8864728b49155f3593d7ccb4001` |
| Direct record    | `e5fcb1b4d21be2926ad54248d863504c64cff256f369c1dc0df7b14bb0061bce` |

All 48 compiles and Wasm executions passed the expected output checks. At 18
cells, explicit handlers or typed accessors reduce native CPU work relative to
the generic builder, and the fully direct record is a smaller lower-bound
control. The wall medians for handlers/accessors are close to the builder
despite CPU differences, illustrating the remaining desktop contention. These
small fixtures do not establish a whole-gdev speedup or preserve the features
listed above.

For historical comparison, the frozen compiler/source snapshot was run with:

```sh
deno run --allow-all compiler/ecs_schema_experiment.ts 5 2,4,8,12,18 1 build/gdev-optimization-baseline build/gdev-ecs-experiment/threads1.json
deno run --allow-all compiler/ecs_schema_experiment.ts 5 2,8,18 8 build/gdev-optimization-baseline build/gdev-ecs-experiment/threads8.json
```

The arguments are sample count, comma-separated cell counts, native threads,
compiler root, and report path. The runner writes generated `.blot` source to
`build/gdev-ecs-experiment/` for inspection. It records source, Wasm and
compiler-executable hashes. It uses one untimed warmup request per
variant/count, alternates variant order in later rounds, verifies every compiled
artifact, and records individual request times, median, source size and Wasm
size. Use `.` as the compiler root to try the current tree; a frozen root is
necessary for a before/after comparison. The runner imports `native.ts` from
that same root, so protocol changes in the working tree cannot silently affect
an old executable.

## Historical exploratory baseline (inconclusive)

The frozen baseline produced valid, import-free Wasm for all four variants at
the tested sizes. For each generated `entry(delta)`, execution at `delta = 0`,
`1` and `17` returned the expected `n(n−1)/2 + n·delta`.

Exploratory five-sample one-thread medians for the runtime-argument version
(milliseconds):

| Cells | Builder | Fixed handlers | Direct accessors | Direct record |
| ----: | ------: | -------------: | ---------------: | ------------: |
|     2 |      80 |             83 |               64 |            61 |
|     8 |     335 |            286 |              316 |           126 |
|    18 |    1447 |           1234 |              812 |           298 |

Another workspace was building Rust release tests during this run, saturating
CPU cores. Individual 18-cell builder samples ranged from 1090 to 1890 ms;
direct-record samples ranged from 125 to 626 ms. Earlier runs of the same
runtime-argument three variants yielded 840/637/179 ms at one thread and
708/449/142 ms at eight threads for 18 cells. Their raw reports are
`build/gdev-ecs-experiment/three-variants-threads1.json`, `threads8.json`, and
`four-variants-threads1.json`. **These timings are inconclusive** as speedup
estimates; the final current-compiler run above supplies native CPU samples
under a normalized scheduler for the smaller matched workload.

The fixed-handler variant retains all N handlers yet reduces the source-level
builder/type-growth machinery. The direct-accessor variant removes handlers but
still reconstructs the record on each typed setter; its source size and work
grow faster than the inlined direct transition. A production fixed-schema
rewrite would also need to preserve gdev's plugin composition, component
querying, snapshots, state migration and saved-state behavior. Such a rewrite
needs whole-application parity and paired timing before replacing the current
builder API.
