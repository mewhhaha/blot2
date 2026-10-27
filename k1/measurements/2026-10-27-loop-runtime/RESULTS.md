# Private scalar-loop runtime campaign

The accompanying `results.json` contains all 51 paired samples,
commands, source/binary/Wasm hashes, ABI inspection, 64 witness inputs, expected
results and every timed checksum. The two `cpu-*.stat` files are cgroup snapshots
around the whole campaign, including untimed preflight compilation.

On 2026-10-27, one idle-host campaign used one pinned logical CPU (0), 12 warmup
batches and 51 alternating-order pairs; each sample makes 256 passes through 64
identical ordered inputs. Node v24.19.0 / V8 13.6.233.17-node.51 ran both Wasm
modules in one process. Both modules had no imports; legacy exported `f(x)` and
private canonical exported `f(0, x)`. All witnesses and all sample checksums
matched the independent `x == 0 ? 17 : x - 1` oracle. The caller ABI differs,
and the private fixture has no public ABI guarantee.

Times per sample, milliseconds (p10/p90 use linear interpolation):

| Path | Min | P10 | Median | P90 | Max |
| --- | ---: | ---: | ---: | ---: | ---: |
| Legacy release | 3.246629 | 3.260445 | 3.281825 | 3.542674 | 3.971969 |
| Private canonical | 3.225158 | 3.241219 | 3.252971 | 3.382855 | 4.277552 |

Paired canonical/legacy ratios: median 0.99201, p10 0.94918, p90 1.01304,
min 0.82339, max 1.16413; 41 of 51 pairs favored the private path. Median
ratios by order were 0.99170 when legacy ran first (n=26) and 0.99201 when
canonical ran first (n=25). First-25 median ratio was 0.99434 versus 0.98994
for the last 26; their p90s were 1.05379 and 0.99839 respectively. These
exploratory slices indicate temporal variability; neither proves an order
interaction or general speed difference.

The cgroup had `cpu.max` 400000/100000 (four CPUs) while the process was pinned
to one. During the recorded campaign, cgroup `nr_periods` rose by 6 while
`nr_throttled` and `throttled_usec` did not increase. The host CPU was an AMD
EPYC 7763; non-cgroup host activity and scheduler effects were not eliminated.

Compiler SHA-256: legacy
`6532c36de09eef3f4a6fe32e4751891f7d4f25932778798a37c8224b7e1726a7`;
canonical adapter
`ff447da9f07fe27a09af525cfc427a7e9f4f338380e4b1e88238d533f1e65ea9`.
Wasm SHA-256: legacy
`1e063398961dfd364976a0087847a6a162d9040c912d1f6bf4f21500502a9dde`;
canonical
`34047008aae5f55d51f7fd2cf3122b9c3b6050bad125fd5b720e26461aaf79a5`.
Respective Wasm sizes were 1,174 and 503 bytes. Legacy persistent restart
cache was disabled and each preflight compiler record reported not loaded and
not saved. The release binary came from baseline revision
`1e39b5d8a4268b9edf769c2813d5231abe1c963b` plus uncommitted Zig changes.

No end-to-end compilation timing was recorded. The two compilers implement
different validation pipelines and output protocols; this is a single narrow
program, not a full compiler, general optimization, safety, ABI or K1 C09
comparison. The observed median difference is small relative to sample spread.
The two measured Wasm files, their benchmark sources, the runtime and compilation
harnesses, the private Goose adapter, and a source-hash manifest are included.
The exact 762-file Goose source snapshot and the compiler executables are not
included in this record. The manifest alone cannot reconstruct those files;
its stdlib hashes were observed after the build and are not a provenance
attestation. Binary hashes pin the observed executables but cannot reproduce
them on their own. The absolute paths in `results.json` record the original
scratch run and will not necessarily exist on another machine.

To recheck the supplied Wasm witnesses without taking timings, run:

```sh
node runtime_pair.mjs --legacy legacy.wasm --canonical canonical.wasm --verify-only
```

The harness can time this narrow runtime pair on another machine after an
appropriate warmup and under controlled load. Such a run will be a new
measurement; a full compiler rebuild additionally requires the exact missing
source snapshot, toolchain and compiler binaries. The complete local scratch
bundle used for this run was at `/tmp/k1-canonical-benchmark/bundle/`.
