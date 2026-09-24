# Gdev type-annotation experiment

The checkpoint is Blot2 `827175d` and gdev `6c9221c`. All measurements used the
checkpoint native compiler (`generated/compiler/blotc`, SHA-256
`eb3a04d0fffb31b389de21d6f65b24198c11d68956bd9d29c79349f68cc467a5`), fresh
native processes, fresh source-project loads, and the 16-module gdev
application. Each row alternated baseline and candidate order in one process.
The source changes were swapped before each run and restored afterward. The
source trees are back at their checkpoint versions. Filesystem caches were not
flushed; timing includes concurrent desktop load. CPU time samples only the
native compiler child, while wall time samples the compile call.

| Candidate                                               | Pairs | Baseline / candidate compile wall median | Baseline / candidate native CPU median |        Wasm bytes |
| ------------------------------------------------------- | ----: | ---------------------------------------: | -------------------------------------: | ----------------: |
| Prelude Bool/U32/F32 primitives: input and result types |     3 |                         2,753 / 2,910 ms |                       2,620 / 2,740 ms | 192,168 / 192,168 |
| Same prelude primitives: input types only               |     3 |                         2,591 / 2,813 ms |                       2,460 / 2,650 ms | 192,168 / 192,168 |
| Gdev math: input and result types                       |     5 |                         2,784 / 2,799 ms |                       2,630 / 2,630 ms | 192,168 / 181,943 |
| Gdev math: input types only                             |     3 |                         2,741 / 2,812 ms |                       2,620 / 2,620 ms | 192,168 / 185,889 |
| Gdev ECS: selected scalar and generic signatures        |     3 |                         2,782 / 2,781 ms |                       2,660 / 2,670 ms | 192,168 / 192,168 |

The prelude and ECS variants produced the exact baseline Wasm hash
`3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`. Math
annotations changed the Wasm artifact, so their functional equivalence is not
established; neither math variant produced a repeatable compile-time gain. An
earlier three-pair math run looked faster (2,723 / 2,632 ms wall), but the
five-pair repeat above did not reproduce it. These samples give no reason to add
the annotations as a performance optimization.

Worker-count comparison on the unmodified source and the same native executable:

| Native workers | Pairs | One-worker / candidate compile wall median | One-worker / candidate native CPU median |
| -------------- | ----: | -----------------------------------------: | ---------------------------------------: |
| 2              |     3 |                           2,663 / 2,951 ms |                         2,490 / 3,240 ms |
| 4              |     3 |                           2,747 / 2,830 ms |                         2,600 / 3,290 ms |

All worker-count runs produced the same baseline Wasm hash. More workers did not
reduce wall time in this workload and increased aggregate CPU use.

The benchmark helper and exact source variants are local investigation files in
`build/gdev-cold-investigation/` (ignored by Git). The larger measured costs are
repeated specialization and final checking; see
[the phase breakdown](COLD_COMPILE_RESULTS.md) and
[the optimization plan](COLD_COMPILE_PLAN.md). A change to those stages needs
paired native CPU, compile-wall, artifact, and behavior checks before adoption.
