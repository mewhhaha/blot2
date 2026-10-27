# Integrated private resolver job benchmark

This campaign measures the actual integrated `semantic_job` against `semantic_job_baseline`. The [earlier prototype campaign](../RESULTS.md) used the separately namespaced `semantic_job_fast`; its samples and binary are distinct.

The integrated private semantic-job route had lower paired elapsed times on all five successful fixed workloads in this controlled run. Invalid-input, missing-module and depth-failure controls were noisy and their paired ranges include parity. This is not a complete compiler comparison, runtime benchmark, complete C09 accounting result, or claim about other workloads.

A freshly compiled single binary calls the actual integrated `semantic_job::compile` and frozen test-only `semantic_job_baseline::compile` directly. Each subprocess performs 32 fresh resolver reads and compile jobs against fixed sources; it checks each result against the first. The measured time includes process startup, root open/close, filesystem reads, source and target validation, internal result comparisons and returned bytes. Compiler result caches are not used; operating-system and filesystem caches are warm. Before timing, both modes' single and 32-call batches were checked for exact status and output-byte parity across all 10 cases. Successful Wasm was executed under Node against edge inputs; failures returned no bytes. All timed output matched those witnesses, and all dependency/input/driver hashes matched after the run.

Each case had four warmups per mode and 31 paired measurements. Case order was shuffled using seed 370037; the first mode alternated per pair and case. Ratios below are paired candidate/baseline; p10 and p90 interpolate linearly from the 31 ratios. Time medians are per 32-job batch in microseconds. The separate time medians and median paired ratio need not divide exactly because their paired distributions differ.

| Case | Baseline median μs | Integrated median μs | Paired ratio median | Ratio p10–p90 |
| --- | ---: | ---: | ---: | ---: |
| U32 identity | 6,982 | 4,915 | 0.707 | 0.625–0.779 |
| Bool short circuit | 22,590 | 12,544 | 0.559 | 0.511–0.584 |
| Guarded offset | 17,741 | 10,059 | 0.561 | 0.505–0.622 |
| Bounded loop | 13,229 | 7,989 | 0.604 | 0.532–0.647 |
| 4 KiB comment | 14,243 | 9,436 | 0.663 | 0.586–0.718 |
| Invalid effect | 2,267 | 2,254 | 0.985 | 0.505–2.013 |
| Invalid type | 3,136 | 3,105 | 0.992 | 0.651–1.519 |
| Depth exhausted | 4,407 | 4,242 | 0.955 | 0.706–1.250 |
| Wrong declaration | 3,742 | 3,722 | 0.997 | 0.688–1.371 |
| Missing module | 1,228 | 2,105 | 0.977 | 0.504–2.091 |

For successful workloads, the difference between baseline-first and integrated-first median paired ratios was at most 0.014; the difference between first-half and second-half median ratios was at most 0.026. Failure controls have wide tails and separate median times can be misleading; the paired samples are retained for inspection. Process affinity was CPU 0, cgroup quota `400000 100000`, effective cpuset `0-4`. Over 52 cgroup periods, neither throttled periods nor throttled microseconds increased; initial/final system load averages were 0.60/0.66. These observations do not rule out CPU frequency changes, descheduling, or interference not reflected in cgroup throttling.

`recorded-results/timings.json` contains all raw paired durations, execution order, affinity and before/after cgroup counters. Its SHA-256 is `a8c39f78d67317b1bac77e6e756a3d8e1e332cd33681dbf83a0d6b4820cd06c5`. `recorded-results/manifest.json` and status-byte-prefixed `*.out` files record source/dependency/input/target hashes and outputs; manifest SHA-256 is `57980ff496d6c96fc3be4d28386fb1076565d47016ced9eb8aac92ee2ab356eb`. The one benchmark binary's SHA-256 is `8a4bbe14cb2afeea56e7717c04a9eb114a27b0f915701ae4c400fa9633c43d14`. `build-record.json` records exact build command, fresh Goose home, compiler/tool hashes and pre/post source hashes; the native benchmark binary, full Goose runtime and system libraries are not included. The benchmark source closure is included under `k1/`; a rerun rebuilds the binary and its hash may differ. Hash checks before and after the campaign do not detect temporary concurrent modifications. Reruns require an exclusively immutable source snapshot and controlled idle machine.

The integrated path relies on the checked emitter's independent source/Core revalidation and full target decoding. This experimental route has no complete C09 receipt. Reducing repeated traversals changes logical work counts; warm-cache and budget equivalence require a fully instrumented versioned schedule before use as C09 authority.
