# Cycle ownership qualification

Focused qualification on 12 October 2026. Task 034 remains awaiting the root
agent's mandatory combined compiler gate. Tracing remains enabled; task 035 is
open. The algorithm and ownership boundaries are in
[CYCLIC_OWNERSHIP.md](CYCLIC_OWNERSHIP.md).

## Exact pins

Incoming is qualified `f184dde`, tree
`1431522db1bd9b93b1e0b3f3f69949e2122aa5e6`. Its Fast / LLVM executable is
`build/bench/joint-052-033-038-054/final/blotc-candidate`, SHA-256
`5c689ad5caad6952f1c4643f5c40e10d6e41bcf819bf016f751ac105d82020a1`,
compiler-input identity
`bb6bda62bee29cebe741d9f3baf9b8184cc722a1691c109ecc43e1feef2f1ed5`.

The frozen candidate is
`/var/tmp/blot2-cycles-034/build/bench/cycles/blotc-candidate-final`, SHA-256
`a0d1e4a8be72c0b7f1bd18bc60e8a8b46a5945c3c41c7c08c6903e4b9705bca7`,
compiler-input identity
`1a74bc888ba273f5a6dcdc3e0b5181bbe3ce7cae42cd5016adc6eaa07fd0188b`. The executed
private runtime fixture has SHA-256
`2d4fbe8bac3259cc32670da8838f8f670adb6305d0baf42dfe0c76e752167245`.

Historical `*-ae7e` files preserve the first candidate before explicit
collection summary barriers. `*-pre-mask` files preserve the barrier-corrected
candidate before sparse-mask scan bounds. Neither qualifies the final source.
The final standard build log is `release-mask-final-build.log`; no generated
output was patched.

## Focused checks

Zig 0.17.0 was checked before every build batch. The final standard build used
`taskset -c 4 deno task build:compiler`. Native development used Safe / noLLVM
and the production test suite's named filters, without a standalone full gate.

- `native-mask-final.log`: 24 native laws pass, including source preparation,
  immutable Core, exact fresh/retained/checkpoint/replay Wasm and exhaustive OOM
  paths for zero-child and strong-cycle sources; iterative phases have no
  allocation, imports or recursive graph traversal. Summary invalidation is an
  explicit independent assertion.
- `release-mask-focused.log`: 43 executed laws pass: 35 cycle, typed RC, roots,
  suspension and unchanged arena laws, plus all eight unchanged compile-cost
  budgets. The original State/closure/strong-demand cycle law is unchanged. New
  source laws require ownership `[2, 2, 0]`, positive local reclamation counters
  and zero terminal roots/leases. Fixture laws cover exhausted allocation,
  reuse, tracing/weak-queue interaction, duplicate capacity edges, both
  finite-mask boundary bits and scalar pointer-looking tails.
- `analyzer-mask-final.log`: 344 Zig files, zero findings. Formatting and local
  documentation links pass. No budget or semantic expectation was weakened.

## Paired costs

Both compilers use standard Fast / LLVM builds. Measurements use CPU 6, process
CPU clocks, alternating order and 25 measured pairs. Compiler preparation has
two discarded rounds; runtime probes have 3000 warm-up calls per control and
three 20000-cycle calls. The compiler edit changes an Array initializer from 41
to 42. Native work, frontend, backend, semantic work and specialization counters
match in every compiler pair. Runtime values match; executed laws preserve
effect traces. Load averages span 1.14–1.56, with builds restricted to CPU 4.

All times are CPU milliseconds per batch. Scalar batches have 10000 calls; Array
and request batches have 2000; cycle batches have one finite-loop invocation
creating 20000 discarded cycles. JSPI callbacks settle through a Promise
microtask. p95 uses the nearest-rank statistic of the 25 measured runs.

| Workload       | Incoming median | Candidate median |  Change | Incoming / candidate p95 |
| -------------- | --------------: | ---------------: | ------: | -----------------------: |
| Compiler fresh |           6.603 |            6.638 |  +0.53% |                        — |
| Compiler edit  |           2.923 |            3.032 |  +3.74% |                        — |
| Sync scalar    |           5.121 |            5.206 |  +1.66% |          10.420 / 12.209 |
| Sync Arrays    |           4.823 |            4.804 |  −0.39% |          10.577 / 10.364 |
| Sync requests  |           8.343 |            8.544 |  +2.41% |          12.007 / 10.008 |
| Sync cycles    |          33.537 |           38.250 | +14.05% |          33.750 / 38.419 |
| JSPI scalar    |          20.338 |           23.594 | +16.01% |          26.611 / 44.025 |
| JSPI Arrays    |           8.074 |            8.076 |  +0.02% |          11.914 / 17.493 |
| JSPI requests  |          11.477 |           11.678 |  +1.75% |          14.995 / 15.289 |
| JSPI cycles    |          33.543 |           38.316 | +14.23% |          33.749 / 38.517 |

These are focused costs, with material cycle/JSPI regressions and p95 outliers.
They do not satisfy task 035's final CPU qualification. The earlier task 033
host-call costs remain in [SUSPENDED_OWNERSHIP.md](SUSPENDED_OWNERSHIP.md).

Warmed control memory is 131072 bytes for both compilers. The finite cycle
workload uses 5373952 bytes incoming and 131072 bytes candidate; every measured
batch remains flat at its respective warmed size. This is distinct from the
unchanged forever-loop cycle law's one-page warmed bound. The mixed workload's
Wasm grows from 10268 to 12053 bytes. Header size stays 32 bytes and physical
List capacity stays 244 words; this task adds no geometry cost. Tracing fallback
and unbounded source limits remain explicit.

## Local work and pauses

The exact runtime fixture repeatedly drops 64 aliases to the same live parent,
then explicitly collects. Membership remains one candidate. Each pass visits two
vertices and the specified number of owning slots, despite a separately
allocated heap. The parent and shared child remain live; final release destroys
both and leaves zero leases. Measurements have three discarded rounds and 20
measured rounds; wall time covers the complete synchronous pass.

| Owning slots | Parent scalar tail | Median CPU ms | Median wall ms | Maximum wall ms |
| -----------: | -----------------: | ------------: | -------------: | --------------: |
|            1 |               None |         0.002 |        0.00189 |         0.00790 |
|         8192 |               None |         0.088 |        0.08846 |         0.60659 |
|      1048576 |               None |         5.685 |        5.70547 |         5.76789 |
|            1 |      4 MiB payload |         0.002 |        0.00180 |         0.00324 |

The sparse-tail comparison measures the finite-mask bound directly. Bit 31 still
covers every physically retained tail slot. An independent law proves a
candidate closure does not scan an unrelated 8192-object heap. Another reaches
the 64 KiB removal trigger without allocating, while the source large-retained
heap law verifies that the tracer's larger budget does not postpone local
passes. Large still-live reference closures can be rescanned; this synchronous
complete-pass strategy has no latency guarantee independent of closure size.

Raw rounds, logs, exact programs and harnesses remain under the isolated
`build/bench/cycles/` directory. Content pins:

| Evidence              | SHA-256                                                            |
| --------------------- | ------------------------------------------------------------------ |
| `cost.blot`           | `e8453fb91db389710b3f30e0401951637a055de945275f9391c134f81efb63a6` |
| `measure_compiler.py` | `2082a3a4317ab82f63cfa98de15ae6ab7e678896005961652ca05418d1ad12d4` |
| `measure_runtime.ts`  | `a919bba89b9a9297572c95c9f38633efcddad87eb9447afa63b2a5e9ac9e2404` |
| `measure_graphs.ts`   | `932f2c43fbadbe107051d078053f3fab3a715d21e49f0e34ebae45061fa3a72e` |
| `compiler-cost.json`  | `073d921e2571d04e4459cd14f50ab12df5c5faeb8c3ac9fe6834f62394b5909f` |
| `runtime-cost.json`   | `a265d9612f933930ae6dff843fc7810414b7b5b434214f9a5957a91497b3712b` |
| `graph-cost.json`     | `2c41703f91e1d78a238465d2e899458d6ce20b210c1e087f4cd04681167b4099` |
