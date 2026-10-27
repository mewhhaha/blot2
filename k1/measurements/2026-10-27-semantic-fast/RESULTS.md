# Private resolver-to-target paired experiment

This record measured the pre-integration `semantic_job_fast` prototype. The later [integrated-route record](integrated-route/RESULTS.md) measures the actual shared `semantic_job` against the frozen baseline; the two are separate campaigns.

On this machine the fused candidate reduced measured time on all five successful private workloads; the four front-end failures were close to parity at the median. Depth exhaustion showed a small median reduction with a range overlapping parity. This is a bounded experiment on the experimental private source-owned scalar/loop job, not a full compiler comparison, runtime benchmark, C09 equivalence claim, or guarantee for other workloads.

A single freshly built binary contains both the original `semantic_job::compile` and the reviewed `semantic_job_fast::compile`. Each timed subprocess opens one trusted package root and runs 32 fresh resolver reads and compile jobs; every result is compared to the first. Both branches use the same source files, driver, input validation, capacity and exact output controls. Timed duration includes subprocess startup, root handling, filesystem reads, source checks, compilation, internal equality checks and returned bytes. The process is pinned to CPU 0. Inputs are fixed, no persistent compiler result cache is used; filesystem and OS caches are warm. Four warmups per case and path precede 31 paired rounds, with case order shuffled using seed 370037 and baseline/candidate order alternating per case. A preflight confirms each single and 32-call baseline/candidate result has the same exact status and bytes; Node independently executes each successful target on the case's edge values. All timed output must equal preflight and all hashes are checked again afterward.

Median elapsed times below are per 32-job batch, in microseconds. Ratios are paired candidate/baseline; p10 and p90 use linear interpolation of those 31 ratios.

| Case | Baseline median μs | Candidate median μs | Ratio median | Ratio p10–p90 |
| --- | ---: | ---: | ---: | ---: |
| U32 identity | 5,789 | 3,858 | 0.669 | 0.639–0.845 |
| Bool short circuit | 21,524 | 11,485 | 0.529 | 0.500–0.584 |
| Guarded offset | 16,819 | 9,085 | 0.544 | 0.521–0.607 |
| Bounded loop | 12,393 | 6,955 | 0.568 | 0.516–0.650 |
| 4 KiB comment | 13,302 | 8,413 | 0.632 | 0.576–0.666 |
| Invalid effect | 2,298 | 2,298 | 1.008 | 0.962–1.795 |
| Invalid type | 3,085 | 3,089 | 1.003 | 0.955–1.519 |
| Depth exhausted | 4,395 | 4,188 | 0.952 | 0.892–1.010 |
| Wrong declaration | 3,723 | 3,722 | 0.999 | 0.955–1.034 |
| Missing module | 2,141 | 2,145 | 0.998 | 0.958–1.032 |

For successful cases, per-order median paired ratios differed by at most 0.013 and first versus second half medians by at most 0.016. Invalid effect/type had substantial upper-tail noise. Cgroup `nr_throttled` and `throttled_usec` did not increase; quota was `400000 100000`, effective cpuset `0-4`, and initial/final load averages were 0.25/0.31. This does not exclude operating-system preemption, frequency variation, or other noise. Raw timing samples preserve case, pair, execution order and individual durations for independent analysis.

`recorded-results/timings.json` contains raw samples, cgroup counters and affinity. `recorded-results/manifest.json` holds case/result and direct Goose import closure hashes, driver and tool identities; status-byte-prefixed output witnesses are stored as `recorded-results/*.out`. Its SHA-256 is `cb352b3af6f23fc85c258184ce2078a833274b8b84d4cf4d86d7027f69f45fbb`; the combined binary SHA-256 is `6b0ffe3f429719577d7a2b090e937be6a34721b7e079e4bfec2f4bbb58af7869`. `build-record.json` identifies the build command, fresh Goose build directory, Goose/C compiler hashes, dependency hashes and log. The complete Goose runtime/toolchain and system libraries are not snapshotted. The native benchmark binary is not included. Before/after hashes do not detect temporary concurrent changes, so a rerun requires immutable exclusive inputs and a quiet machine. Source and scripts are included under `k1/`; a rerun rebuilds the native binary, whose hash may differ with toolchain and paths.

The candidate removes repeated validation after successful checks on unchanged compiler-owned data while retaining original owner identity/source/contract replay, the emitter's independent source/Core replay and the full independent target decoder. The number of visits differs from the baseline, so a complete versioned semantic work schedule and cache invalidation remain necessary before using it as a C09-budgeted production path. See `NOTES.md`.
